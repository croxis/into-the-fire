@tool
extends BTAction
## Crew: aboard a carrier with a patrol claimed, asks to launch in a fighter
## (CrewOrders.launch_for_orders: the same path as a player's). Fails until it
## can (no free bay yet, no orders).


func _generate_name() -> String:
	return "LaunchForObjective"


func _tick(_delta: float) -> Status:
	var character := CommanderPatrol.character_of(agent)
	var galaxy := Galaxy.find_for(character) if character else null
	if galaxy == null:
		return FAILURE
	return SUCCESS if CrewOrders.launch_for_orders(character, galaxy) == "" else FAILURE
