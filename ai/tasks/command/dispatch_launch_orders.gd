@tool
extends BTAction  # or BTCondition, BTDecorator, BTComposite

# Task parameters (editable in the Inspector)
#@export var doctrine_var: StringName = &"doctrine"
#@export var out_fighters_needed: StringName = &"fighters_needed"
@export var free_crew_var: StringName = &"free_crew"

# Generates the display name in the behavior tree editor (requires @tool).
func _generate_name() -> String:
	return "DispatchLaunchOrders"

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
	return SUCCESS

# Warnings shown in the editor if configuration is invalid.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	return warnings
