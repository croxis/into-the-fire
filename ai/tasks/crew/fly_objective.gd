@tool
extends BTAction
## Pilot: at a helm with a patrol claimed, hands its route to the AI pilot
## (CrewOrders.fly_orders; only when the orders change). Fails without one.


func _generate_name() -> String:
	return "FlyObjective"


func _tick(_delta: float) -> Status:
	var character := CommanderPatrol.character_of(agent)
	var galaxy := Galaxy.find_for(character) if character else null
	if galaxy == null:
		return FAILURE
	return SUCCESS if CrewOrders.fly_orders(character, galaxy) else FAILURE
