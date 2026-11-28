@tool
extends BTAction
## Commander: how many fighters its side's doctrine wants out at the threat
## AssessThreat found (CommanderPatrol.wanted_fighters).

@export var threat_var: StringName = &"threat"
@export var out_fighters_wanted: StringName = &"fighters_wanted"


func _generate_name() -> String:
	return "EvaluateFighterNeed -> %s" % LimboUtility.decorate_var(out_fighters_wanted)


func _tick(_delta: float) -> Status:
	var commander := CommanderPatrol.character_of(agent)
	if commander == null or commander.current_ship == null:
		return FAILURE
	var side := commander.current_ship.faction
	var doctrine: FactionDoctrine = side.doctrine if side else null
	blackboard.set_var(out_fighters_wanted,
			CommanderPatrol.wanted_fighters(doctrine, blackboard.get_var(threat_var, 0.0)))
	return SUCCESS
