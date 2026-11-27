extends Node


@export var max_crew := 1  ## It is important to include the number of stations on the ship.
## unless you want more stations than crew.


## Crew only ever arrive through the ship's CrewMultiplayerSpawner
## (Ship.spawn_crew), never by add_child or reparenting: a spawner only tracks
## nodes it spawned, so a character moved in from elsewhere would not exist on
## clients (docking did this until 2026-11-27).


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
