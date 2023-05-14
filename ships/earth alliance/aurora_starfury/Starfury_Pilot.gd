extends MeshInstance3D


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if Input.is_action_just_released("camera_change"):
		if $Camera3DPilot.current:
			$Camera3DChase.current = true
		else:
			$Camera3DPilot.current = true
