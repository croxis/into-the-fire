extends MeshInstance3D


func _process(delta):
	var active_camera := get_viewport().get_camera_3d()
	if active_camera:
		position = active_camera.global_position
