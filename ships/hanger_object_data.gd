class_name HangerObject
extends GdPAIObjectData

## Reference to GdPAI interactable.
@export var interactable_attribs: GdPAIInteractable
## Reference to GdPAI location data.
@export var location_data: GdPAILocationData


# Override
func _init() -> void:
	# In case extending _init(), make sure to call super() so that the group is assigned.
	super()


# Override
func get_group_labels() -> Array[String]:
	return ["HangerObject", "GdPAIObjectData"]

	
# Override
#func get_provided_actions() -> Array[Action]:
	# Overwrite the get_provided_actions function to serve any actions that become possible because
	# this object exists out in the world.
	#var launch_fighters_action: LaunchFighterAction = LaunchFighterAction.new(
	#	interactable_attribs,
	#	entity,
	#)
	#return [launch_fighters_action]


# Override
func copy_for_simulation() -> HangerObject:
	# Make sure to replace <GdPAIObjectData> with the subclass name,
	# and to duplicate any new properties.
	var new_data: HangerObject = HangerObject.new()
	assign_uid_and_entity(new_data)
	return new_data
