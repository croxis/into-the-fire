extends LimboState
@onready var bt_player: BTPlayer = $BTPlayer


func _setup() -> void:
	bt_player.behavior_tree_finished.connect(_on_tree_finished)


func _enter() -> void:
	Log.log([agent, "hsm entering operating console"], Log.MessageType.QUESTION)
	var character: Character = agent
	var console: Console = character.current_console
	bt_player.restart()
	bt_player.active = true
	
	# Something went wrong
	if console == null or console.capabilities.size() == 0:
		print_debug("Error going to console: ", agent)
		dispatch(&"leave_console")
	
	for capability in console.capabilities:
		blackboard.set_var("cap_" + capability.name, capability)
	Log.log([agent, "hsm entered operating console"], Log.MessageType.SUCCESS)


func _on_tree_finished(status: int) -> void:
	if status == BTTask.SUCCESS:
		get_root().dispatch(&"console_success")
	elif status == BTTask.FAILURE:
		get_root().dispatch(&"console_failure")


func _update(delta: float) -> void:
	if bt_player.behavior_tree:
		bt_player.update(delta)


func _exit() -> void:
	bt_player.set_active(false)
