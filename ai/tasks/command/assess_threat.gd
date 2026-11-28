@tool
extends BTAction
## Commander: rates the threat to its ship into the blackboard
## (ThreatAssessment; always 0 in the first NPC AI pass).

@export var out_threat: StringName = &"threat"


func _generate_name() -> String:
	return "AssessThreat -> %s" % LimboUtility.decorate_var(out_threat)


func _tick(_delta: float) -> Status:
	var commander := CommanderPatrol.character_of(agent)
	if commander == null or commander.current_ship == null:
		return FAILURE
	blackboard.set_var(out_threat, ThreatAssessment.threat_to(commander.current_ship))
	return SUCCESS
