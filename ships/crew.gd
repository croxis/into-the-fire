extends Node


@export var max_crew := 1  ## It is important to include the number of stations on the ship.
## unless you want more stations than crew.


## Crew only ever arrive through the ship's CrewMultiplayerSpawner
## (Ship.spawn_crew), never by add_child or reparenting: a spawner only tracks
## nodes it spawned, so a character moved in from elsewhere would not exist on
## clients (docking did this until 2026-11-27).


## Takes [param character] off this ship (out of its console first), without
## freeing it. Returns it, or null when it isn't aboard.
func remove_passenger(character: Character) -> Character:
	if character == null or character.get_parent() != self:
		return null
	if character.current_console:
		character.current_console.vacate()
	remove_child(character)
	return character


func _on_child_exiting_tree(node: Node) -> void:
	pass
