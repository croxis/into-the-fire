extends Node

@export var captain: String
@export var pilot: String
@export var max_gunners := 0
@export var max_passengers := 0
@export var gunners: Array[String] = []


func set_captain(new_captain: Pilot) -> bool:
	if add_passenger(new_captain):
		if new_captain not in get_children():
			if new_captain.get_parent():
				new_captain.reparent(self)
			else:
				add_child(new_captain, true)
		captain = new_captain.name
		return true
	return false


func set_pilot(new_pilot: Pilot) -> bool:
	if add_passenger(new_pilot):
		if new_pilot not in get_children():
			if new_pilot.get_parent():
				new_pilot.reparent(self)
			else:
				add_child(new_pilot, true)
		captain = new_pilot.name
		return true
	return false


func add_passenger(pilot: Pilot) -> bool:
	if pilot in get_children():
		return true
	var max_capacity: int = max_passengers
	if pilot:
		max_capacity += 1
	if captain:
		max_capacity += 1
	if get_child_count() >= max_capacity:
		Logger.log(["Too many passengers."], Logger.MessageType.WARNING)
		return false
	if pilot.get_parent():
		pilot.reparent(self)
	else:
		add_child(pilot)
	return true
