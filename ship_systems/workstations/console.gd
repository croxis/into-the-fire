extends Node3D
class_name Console

var occupant: Character
@export_node_path("Camera3D") var camera_path: NodePath
@onready var camera: Camera3D = get_node_or_null(camera_path)

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
	character.current_console = self
	set_camera.rpc_id(character.multiplayer_id)
	
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
	# The station is alive as long as at least one role is working.
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
		occupant.current_console = null
		for b_tree in occupant.get_node("BrainHSM/OperatingConsoleState").get_children():
			b_tree.queue_free()
	occupant = null


@rpc("call_local")
func set_camera():
	Log.log(["Setting Camera"], Log.MessageType.QUESTION)
	camera.far = 30000
	camera.near = 0.3
	camera.current = true


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
