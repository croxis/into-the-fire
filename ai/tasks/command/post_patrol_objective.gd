@tool
extends BTAction
## Commander: keeps one patrol posting round its ship with slots for the
## fighters wanted that aren't out yet (CommanderPatrol.keep_patrol_posted).
## Pilots claim it themselves. Only adds fighters in the first NPC AI pass.

@export var fighters_wanted_var: StringName = &"fighters_wanted"


func _generate_name() -> String:
	return "PostPatrolObjective (%s)" % LimboUtility.decorate_var(fighters_wanted_var)


func _tick(_delta: float) -> Status:
	var commander := CommanderPatrol.character_of(agent)
	var ship := commander.current_ship if commander else null
	var galaxy := Galaxy.find_for(ship) if ship else null
	if galaxy == null or ship.faction == null:
		return FAILURE
	var doctrine: FactionDoctrine = ship.faction.doctrine
	var radius := doctrine.patrol_radius if doctrine else 20000.0
	CommanderPatrol.keep_patrol_posted(galaxy.state.objectives, commander.pilot_id, ship,
			blackboard.get_var(fighters_wanted_var, 0), radius)
	return SUCCESS
