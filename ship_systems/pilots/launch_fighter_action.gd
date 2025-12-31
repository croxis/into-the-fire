class_name LaunchFighterAction
extends SpatialAction
## Simple GdPAI spatial action to shake the tree (in 2D) for the GdPAI usage demo.

## While not necessary, I'm encoding a duration into shaking the tree here, just to make the
## simulation a little more visually interesting.
const SHAKE_DURATION: float = 0.5

## Reference to the food item that provided this action.
var parent_ship: Ship
## An internal param to cache how much food the tree is guaranteed to drop.
var free_pilots: int


# Override
func _init(
		p_object_location: GdPAILocationData,
		p_interactable_attribs: GdPAIInteractable,
		p_parent_ship: Ship,
) -> void:
	# If extending _init(), make sure to call super() so references are assigned.
	super(p_object_location, p_interactable_attribs)
	self.parent_ship = p_parent_ship

	# I am faking that the agent will restore hunger by shaking the tree.  It doesn't
	# actually do that; it drops fruit.  Faking it makes it easier to hook preconditions, rather
	# than trying to simulate the creation of new objects.

	free_pilots = parent_ship.get_crew().size() - 1


# Override
## List of static preconditions needed for the action to be considered.  This is
## evaluated at the time of assigning wordly actions (so, there is no need to grab sim data).
##[br]
##[br]
## For multithreaded planning, it is possible to await information with GdPAIUTILS.await_callv(..).
func get_validity_checks() -> Array[Precondition]:
	var checks: Array[Precondition] = super()
	checks.append(Precondition.agent_has_property("crew"))
	checks.append(Precondition.check_is_object_valid(parent_ship))
	checks.append(Precondition.agent_property_greater_than("crew", 1))

	return checks


# Override
func get_action_cost(
		agent_blackboard: GdPAIBlackboard,
		world_state: GdPAIBlackboard,
) -> float:
	var cost: float = super(agent_blackboard, world_state)
	if cost == INF:
		return INF
	# This action needs a high cost to discourage shaking the tree
	# when there are alternatives.
	return 100 + cost


# Override
func get_preconditions() -> Array[Precondition]:
	# So long as we can get to the tree (handled in validity checks), we can shake it.
	return []


# Override
func simulate_effect(
		agent_blackboard: GdPAIBlackboard,
		world_state: GdPAIBlackboard,
) -> void:
	super(agent_blackboard, world_state)
	var crew_count: int = agent_blackboard.get_property("crew")
	agent_blackboard.set_property("crew", crew_count - 1)


# Override
func reverse_simulate_effect(
		_agent_blackboard: GdPAIBlackboard,
		_world_state: GdPAIBlackboard,
) -> void:
	pass


# Override
func pre_perform_action(agent: GdPAIAgent) -> Action.Status:
	if super(agent) == Action.Status.FAILURE:
		return Action.Status.FAILURE
	agent.blackboard.set_property(uid_property("shake_duration"), 0)
	return Action.Status.SUCCESS


# Override
## Perform the action in the actual simulation.  Can return RUNNING for actions that have a
## duration.
##[br]
##[br]
## Need to monitor any validity checks that could become false after some time.
func perform_action(
		agent: GdPAIAgent,
		delta: float,
) -> Action.Status:
	var parent_status: Action.Status = super(agent, delta)
	if parent_status == Action.Status.FAILURE:
		return Action.Status.FAILURE

	# Check that the tree has not been shaken by another agent.
	if parent_ship.get_crew().size() <= 1:
		return Action.Status.FAILURE

	if not agent.blackboard.get_property(uid_property("target_reached")):
		return Action.Status.RUNNING

	# Update how long we've been eating the food item.
	#var shake_duration: float = agent.blackboard.get_property(uid_property("shake_duration"))
	#shake_duration += delta
	#agent.blackboard.set_property(uid_property("shake_duration"), shake_duration)

	# spawn the food.
	parent_ship.request_launch(0, parent_ship.get_crew()[1].pilot_id)
	return Action.Status.SUCCESS
	#return Action.Status.RUNNING


# Override
func post_perform_action(agent: GdPAIAgent) -> Action.Status:
	super(agent)
	agent.blackboard.erase_property(uid_property("shake_duration"))
	return Action.Status.SUCCESS


# Override
func get_title() -> String:
	return "Shake Tree"


# Override
func get_description() -> String:
	return "Shake a fruit tree to drop fruit."
