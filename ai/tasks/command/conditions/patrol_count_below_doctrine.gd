@tool
extends BTCondition

@export var fighters_deployed_var: StringName = &"fighters_deployed"
@export var doctrine_var: StringName = &"doctrine"

func _generate_name() -> String:
	return "PatrolCountBelowDoctrine"

func _tick(_delta: float) -> Status:
	var active_patrols: int = blackboard.get_var(fighters_deployed_var, 0).size()
	var doctrine: FactionDoctrine = blackboard.get_var(doctrine_var)

	if doctrine == null:
		return FAILURE

	var max_patrols: int = doctrine.minimum_patrol_fighters
	if active_patrols < max_patrols:
		return SUCCESS
	return FAILURE
