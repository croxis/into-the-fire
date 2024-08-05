extends Node


func get_faction(faction_name: String) -> Faction:
	return find_child(faction_name)
