extends MeshInstance3D


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	$"../SubViewportWindow/window_ui".velocity = $"..".global_transform.basis.transposed() * $"..".linear_velocity
	
