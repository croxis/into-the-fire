@tool
extends BTAction  # or BTCondition, BTDecorator, BTComposite

# Task parameters (editable in the Inspector)
@export var doctrine_var: StringName = &"doctrine"
@export var out_fighters_needed: StringName = &"fighters_needed"

# Generates the display name in the behavior tree editor (requires @tool).
func _generate_name() -> String:
	return "EvaluateFighterNeed  -> %s" % LimboUtility.decorate_var(out_fighters_needed)

# Called once when the behavior tree is initialized.
func _setup() -> void:
	pass

# Called each time the task becomes the active node.
func _enter() -> void:
	pass

# Called when the task stops being active (SUCCESS, FAILURE, or aborted).
func _exit() -> void:
	pass

# Called every tick while this task is running. MUST return a Status.
func _tick(delta: float) -> Status:
	var doctrine: FactionDoctrine = blackboard.get_var(doctrine_var)

	if doctrine == null:
		blackboard.set_var(out_fighters_needed, 0)
		return SUCCESS
	var needed: int = max(0, doctrine.minimum_patrol_fighters - blackboard.get_var("fighters_deployed").size())
	#TODO: Also calculate how many fighters are needed from threat level.
	#If threat, should take another branch in the tree so that intercept orders
	#are given instead of patrol
	blackboard.set_var(out_fighters_needed, needed)
	return SUCCESS

# Warnings shown in the editor if configuration is invalid.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	return warnings
