@tool
extends BTAction  # or BTCondition, BTDecorator, BTComposite

# Task parameters (editable in the Inspector)
@export var doctrine_var: StringName = &"doctrine"
@export var out_fighters_needed: StringName = &"fighters_needed"

# Generates the display name in the behavior tree editor (requires @tool).
func _generate_name() -> String:
	return "BuildPatrolAssignment"

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
	var doctrine = blackboard.get_var(doctrine_var)
	if doctrine == null:
		blackboard.set_var(out_fighters_needed, 0)
		return FAILURE
	var current_ship: Ship = blackboard.get_var(&"current_ship")
	var free_crew: Array[Character] = []
	var faction: Faction = blackboard.get_var(&"faction")
	var valid_factions: Array[Faction] = faction.get_wings()
	# Append chapital/station faction last so wing members get prioritized first
	valid_factions.append(faction)
	var needed: int = blackboard.get_var(&"fighters_needed")
	for character: Character in current_ship.crew:
		if character.current_console != null: continue
		if character.faction not in valid_factions: continue
		free_crew.append(character)
		needed -= 1
		if needed == 0: break
	blackboard.set_var(&"free_crew", free_crew)
	return SUCCESS

# Warnings shown in the editor if configuration is invalid.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	return warnings
