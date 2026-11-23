extends Node3D
class_name Console

var occupant: Character
@export_node_path("Camera3D") var camera_path: NodePath
@onready var camera: Camera3D = get_node_or_null(camera_path)
## Shown in the main window while a player sits here (see HudLayer). Optional:
## a console without one shows no HUD. The scene's root may define
## bind_console(console) to get this console.
@export var hud_scene: PackedScene
## Set this to use a HUD layer directly (unit tests). Otherwise Galaxy.hud.
var hud_layer: HudLayer

var capabilities: Array[ConsoleCapability]:
	get():
		var c: Array[ConsoleCapability] = []
		for child in get_children():
			if child is ConsoleCapability:
				c.append(child as ConsoleCapability)
		return c


func occupy(character: Character) -> bool:
	if occupant != null:
		return false
	Log.log([character.name, "trying to sit at", self.name, "on", character.current_ship], Log.MessageType.QUESTION)
	occupant = character
	character.seat = character.get_path_to(self)  # Also sets current_console; replicated.
	# Only players get a view and a HUD. NPC crew carry the server's peer id, so
	# without this check a host-and-play server would show them on the host.
	if character.is_player():
		set_camera.rpc_id(character.multiplayer_id)
		_show_hud.rpc_id(character.multiplayer_id)

	var c_state: LimboState = character.get_node("BrainHSM/OperatingConsoleState")
	var bt_player: BTPlayer  = c_state.bt_player
	var combo_tree: BehaviorTree = BehaviorTree.new()
	var parallel: BTParallel = BTParallel.new()
	# Consoles also hold cameras, reticles and UI, so only capabilities count.
	var role_count := 0
	for capability in capabilities:
		if capability.behavior_tree:
			var subtree: BTSubtree = BTSubtree.new()
			subtree.set_subtree(capability.behavior_tree)
			parallel.add_child(subtree)
			role_count += 1
	# The console is alive as long as at least one role is working.
	# Only fail if EVERY role reports FAILURE.
	parallel.num_failures_required = maxi(role_count, 1)
	parallel.num_successes_required = 0
	# Do not force re-enter; let continuous tasks stay RUNNING.
	parallel.repeat = false
	combo_tree.set_root_task(parallel)
	var hsm_blackboard: Blackboard = character.hsm.get_blackboard()
	bt_player.set_blackboard(hsm_blackboard)
	
	bt_player.behavior_tree = combo_tree
	bt_player.active = true
	
	character.hsm.dispatch(&"move_console")
	Log.log([character.name, "sat at", self.name, "on", character.current_ship], Log.MessageType.SUCCESS)
	return true


func vacate():
	if occupant:
		if occupant.is_player():
			_hide_hud.rpc_id(occupant.multiplayer_id)
		occupant.seat = NodePath()  # Also clears current_console; replicated.
		for b_tree in occupant.get_node("BrainHSM/OperatingConsoleState").get_children():
			b_tree.queue_free()
	occupant = null


@rpc("call_local")
func set_camera():
	Log.log(["Setting Camera"], Log.MessageType.QUESTION)
	camera.far = 30000
	camera.near = 0.3
	camera.current = true


## Sent by the server to the player who sat down here.
@rpc("call_local")
func _show_hud() -> void:
	var hud := _hud()
	if hud:
		hud.show_console(self, hud_scene)


## Sent by the server to the player who left this console.
@rpc("call_local")
func _hide_hud() -> void:
	var hud := _hud()
	if hud:
		hud.hide_console(self)


func _hud() -> HudLayer:
	if hud_layer:
		return hud_layer
	var g := Galaxy.find_for(self)
	return g.hud if g else null


func change_camera():
	Log.log(["Changing Camera for: ", self.name, "on", $".".name], Log.MessageType.QUESTION)
	if $Camera3DPilot.current:
		$Camera3DChase.current = true
	elif $Node3D/OrbitCamera.current:
		$Camera3DPilot.current = true
	else:
		$Node3D/OrbitCamera.current = true


## The first capability that is an instance of [param type] (a class such as
## HelmCapability), or null. Prefer this over node names, which vary by scene.
func get_capability(type: Script) -> ConsoleCapability:
	for c in capabilities:
		if is_instance_of(c, type):
			return c
	return null


func has_capability(capability: String) -> bool:
	for c in capabilities:
		if c.name.to_lower() == capability.to_lower():
			return true
	return false
