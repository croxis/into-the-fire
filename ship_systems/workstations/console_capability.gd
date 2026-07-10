extends Node
class_name ConsoleCapability
@export var system_node_path: NodePath

var system: Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	system = get_node_or_null(system_node_path)


func is_available() -> bool:
	# Server-authoritative: system must exist, be powered, and not destroyed
	if system == null or not is_instance_valid(system):
		return false
	if system.has_method("is_operational"):
		return system.is_operational()
	return true


# Override in subclasses to expose domain-specific actions
func execute(command: String, args: Dictionary = {}) -> Variant:
	if system == null:
		push_error("Capability %s has no system bound" % name)
		return null
	if system.has_method(command):
		return system.callv(command, args.values())
	return null
