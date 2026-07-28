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
	#var c_state: BTState = character.get_node("BrainHSM/OperatingConsoleState")
	#var bt_instance = c_state.get_bt_instance()
#
	#if bt_instance == null:
		#Log.log(["bt_instance is null! Assign a placeholder BehaviorTree to OperatingConsoleState."], Log.MessageType.ERROR)
		#push_error("bt_instance is null! Assign a placeholder BehaviorTree to OperatingConsoleState.")
		#return false
	#
	#var root: BTParallel = bt_instance.get_root_task() as BTParallel
#
	## Clear any stale children from a previous console
	#for child in root.get_children():
		#root.remove_child(child)
		#child.free()
	#
	## Configure parallel to match the console's capability count
	#root.num_failures_required = get_children().size()
	#root.num_successes_required = 0
	#root.repeat = false
	#
	#
	##var parallel: BTParallel = BTParallel.new()
	## The station is alive as long as at least one role is working.
	## Only fail if EVERY role reports FAILURE.
	##parallel.num_failures_required = get_children().size()
	##parallel.num_successes_required = 0
	## Do not force re-enter; let continuous tasks stay RUNNING.
	##parallel.repeat = false
	#
	#for console_capability in get_children():
		#var c_c: = console_capability as ConsoleCapability
		#if c_c.behavior_tree:
			#var subtree: BTSubtree = BTSubtree.new()
			#subtree.set_subtree(c_c.behavior_tree)
			##parallel.add_child(subtree)
			#root.add_child(subtree)
	#var combo_tree: BehaviorTree = BehaviorTree.new()
	##combo_tree.set_root_task(parallel)
	#c_state.behavior_tree = combo_tree
	
	var c_state: LimboState = character.get_node("BrainHSM/OperatingConsoleState")
	var bt_player: BTPlayer  = c_state.bt_player
	var combo_tree: BehaviorTree = BehaviorTree.new()
	var parallel: BTParallel = BTParallel.new()
	# The station is alive as long as at least one role is working.
	# Only fail if EVERY role reports FAILURE.
	parallel.num_failures_required = get_children().size()
	parallel.num_successes_required = 0
	# Do not force re-enter; let continuous tasks stay RUNNING.
	parallel.repeat = false
	for console_capability in get_children():
		var c_c: = console_capability as ConsoleCapability
		if c_c.behavior_tree:
			var subtree: BTSubtree = BTSubtree.new()
			subtree.set_subtree(c_c.behavior_tree)
			parallel.add_child(subtree)
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


func has_capability(capability: String) -> bool:
	for c in capabilities:
		if c.name.to_lower() == capability.to_lower():
			return true
	return false
