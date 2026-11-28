extends LimboState
## An NPC with no console (a passenger): runs the crew tree
## (ai/roles/crew.tres: claim an objective, launch for it). Like
## OperatingConsoleState, the tree is updated by hand, with the state.

@onready var bt_player: BTPlayer = $BTPlayer


func _enter() -> void:
	# A fresh player builds its tree when activated; restart only an old one
	# (back from a console), so it doesn't resume mid-way.
	if bt_player.get_bt_instance():
		bt_player.restart()
	bt_player.active = true


func _update(delta: float) -> void:
	if bt_player.behavior_tree:
		bt_player.update(delta)


func _exit() -> void:
	bt_player.set_active(false)
