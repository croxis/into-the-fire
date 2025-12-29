# meta-description: GdPAI PropertyUpdater template.
# meta-default: true
class_name FleetPropertyUpdater
extends PropertyUpdater

## Add your configurable properties here.  They can be passed in from
## the GdPAIBehaviorConfig that instantiates the PropertyUpdater.
## How many ships are subservent in the fleet.
var total_pilots: int = 0
var launched_pilots: int = 0
var total_fighters: int = 0
var launched_fighters: int = 0
var total_capitals: int = 0
var total_stations: int = 0


func _init(p_total_pilots: int = 0) -> void:
	# Assign any parameters here.
	self.total_pilots = p_total_pilots


# Override
func initialize(agent: GdPAIAgent) -> void:
	# Set up initial property values with the agent.
	agent.blackboard.set_property("total_pilots", total_pilots)
	agent.blackboard.set_property("launched_pilots", launched_pilots)
	agent.blackboard.set_property("total_fighters", total_fighters)
	agent.blackboard.set_property("launched_fighters", launched_fighters)
	agent.blackboard.set_property("total_capitals", total_capitals)
	agent.blackboard.set_property("total_stations", total_stations)


# Override
func update_properties(
		agent: GdPAIAgent,
		_delta: float,
) -> void:
	# Update agent properties that need to be maintained as part of this behavior.
	#var runtime_value: float = agent.blackboard.get_property("example_parameter")
	#agent.blackboard.set_property("example_parameter", runtime_value + delta)
	agent.blackboard.set_property("total_pilots", total_pilots)
	agent.blackboard.set_property("launched_pilots", launched_pilots)
	agent.blackboard.set_property("total_fighters", total_fighters)
	agent.blackboard.set_property("launched_fighters", launched_fighters)
	agent.blackboard.set_property("total_capitals", total_capitals)
	agent.blackboard.set_property("total_stations", total_stations)
