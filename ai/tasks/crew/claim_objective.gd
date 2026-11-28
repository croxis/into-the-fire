@tool
extends BTAction
## Crew: keeps the objective this character has claimed, or claims the best
## open one it can do (CrewOrders.claim_best, utility). Fails with none.


func _generate_name() -> String:
	return "ClaimObjective"


func _tick(_delta: float) -> Status:
	var character := CommanderPatrol.character_of(agent)
	var galaxy := Galaxy.find_for(character) if character else null
	if galaxy == null:
		return FAILURE
	return SUCCESS if CrewOrders.claim_best(character, galaxy) else FAILURE
