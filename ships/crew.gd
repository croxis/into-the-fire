extends Node


@export var max_crew := 1  ## It is important to include the number of stations on the ship.
## unless you want more stations than crew.


func add_passenger(passenger: Character) -> bool:
	if passenger in get_children():
		return true
	var max_capacity: int = max_crew
	if get_child_count() >= max_capacity:
		Log.log(["Too many passengers."], Log.MessageType.WARNING)
		return false
	if passenger.get_parent():
		passenger.reparent(self)
	else:
		add_child(passenger)
	return true


func remove_passenger_by_id(pilot_id: int) -> Character:
	for child in get_children():
		if child._player_pilot_id == pilot_id:
			if child is Character:
				var character: Character = child as Character
				if character.current_console:
					character.current_console.vacate()
				remove_child(child)
				return child
	return null


func remove_passenger_by_multiplayerid(multiplayer_id: int) -> Character:
	for child in get_children():
		if child.multiplayer_id == multiplayer_id:
			if child is Character:
				var character: Character = child as Character
				if character.current_console:
					character.current_console.vacate()
				remove_child(child)
				return child
	return null


func _on_child_exiting_tree(node: Node) -> void:
	pass
