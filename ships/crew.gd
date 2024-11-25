extends Node

@export var captain_name: String
@export var pilot_name: String
@export var max_gunners := 0
@export var max_passengers := 0
var captain: Pilot:
	get:
		if captain_name:
			return get_node(captain_name)
		else:
			return null
	set(c):
		captain_name = c.name
		captain = c
var pilot: Pilot:
	get:
		if pilot_name:
			return get_node(pilot_name)
		return null
	set(p):
		pilot_name = p.name
		pilot = p


func set_captain(new_captain: Pilot) -> bool:
	if add_passenger(new_captain):
		captain_name = new_captain.name
		return true
	return false


func set_pilot(new_pilot: Pilot) -> bool:
	if add_passenger(new_pilot):
		pilot_name = new_pilot.name
		return true
	return false


func add_passenger(passenger: Pilot) -> bool:
	if passenger in get_children():
		return true
	var max_capacity: int = max_passengers
	if get_child_count() >= max_capacity:
		Logger.log(["Too many passengers."], Logger.MessageType.WARNING)
		return false
	if passenger.get_parent():
		passenger.reparent(self)
	else:
		add_child(passenger)
	return true


func remove_passenger_by_id(pilot_id: int) -> Pilot:
	for child in get_children():
		if child._player_pilot_id == pilot_id:
			remove_child(child)
			return child
	return null


func _on_child_exiting_tree(node: Node) -> void:
	if node.name == captain_name:
		captain_name = ""
	if node.name == pilot_name:
		pilot_name = ""
