class_name FleetBehaviorConfig
extends GdPAIBehaviorConfig

# Add your configurable properties here with @export for serialization.
@export var desired_launched_fighters: int = 5


# Override _self_init to set up goals and actions after @export values are applied.
func _self_init() -> void:
	super()
	# Configure goals, self_actions, and property_updaters here.
	# You can pass @export properties to your custom classes.
	goals.append(PatrolGoal.new())
	#self_actions.append(Action.new())
	property_updaters.append(FleetPropertyUpdater.new(desired_launched_fighters))
