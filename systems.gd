extends Node


func add_station(station: Ship, system_name: String) -> void:
	var system := find_child(system_name, false, false)
	if not system:
		print_debug("System not found: ", system_name)
		return
	system.add_station(station)


func add_ship(ship: Ship, system_name: String) -> void:
	var system := find_child(system_name, false, false)
	if not system:
		print_debug("System not found: ", system_name)
		return
	system.add_station(ship)
