class_name PatrolGoal
extends Goal
## Simple GdPAI goal to eat food and keep hunger up.


# Override
func compute_reward(agent: GdPAIAgent) -> float:
	#TODO: Alert status
	#TODO: Radar
	# For now, desire 5 ships launched
	#print_debug(100.0 - agent.blackboard.get_property("launched_pilots", 5) * 20.0)
	return 100.0 - agent.blackboard.get_property("launched_pilots", 5) * 20.0


# Override
func get_desired_state(agent: GdPAIAgent) -> Array[Precondition]:
	var current_pilots: float = agent.blackboard.get_property("launched_pilots")
	#print_debug(current_pilots, Precondition.agent_property_greater_than("launched_pilots", current_pilots))
	return [Precondition.agent_property_greater_than("launched_pilots", current_pilots)]


# Override
func get_title() -> String:
	return "Current Pilots"


# Override
func get_description() -> String:
	return "Try and keep the number of pilots out and about."
