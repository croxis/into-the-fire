extends Node3D
class_name Console

var occupant: Character
@export_node_path("Camera3D") var camera_path: NodePath
@onready var camera: Camera3D = get_node_or_null(camera_path)

var capabilities: Array[ConsoleCapability]:
	get():
		var c: Array[ConsoleCapability] = []
		for child in get_children():
			if child is ConsoleCapability:
				c.append(child as ConsoleCapability)
		return c


func occupy(character: Character) -> bool:
	if occupant != null:
		return false
	occupant = character
	character.current_console = self
	set_camera.rpc_id(character.multiplayer_id)
	return true


func vacate():
	if occupant:
		occupant.current_console = null
	occupant = null


@rpc("call_local")
func set_camera():
	Log.log(["Setting Camera"], Log.MessageType.QUESTION)
	camera.far = 30000
	camera.near = 0.3
	camera.current = true


func change_camera():
	Log.log(["Changing Camera for: ", self.name, "on", $".".name], Log.MessageType.QUESTION)
	if $Camera3DPilot.current:
		$Camera3DChase.current = true
	elif $Node3D/OrbitCamera.current:
		$Camera3DPilot.current = true
	else:
		$Node3D/OrbitCamera.current = true


func has_capability(capability: String) -> bool:
	for c in capabilities:
		if c.name.to_lower() == capability.to_lower():
			return true
	return false
