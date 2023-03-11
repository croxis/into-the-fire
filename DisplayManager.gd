extends Node


func set_resolution(resolution: Vector2i) -> void:
	# if server:
	#	return
	var interface = XRServer.find_interface("OpenXR")
	if interface and interface.is_initialized():
		return
	
	# If x is 0, use screen native
	if resolution.x == 0:
		resolution = DisplayServer.screen_get_size()
	
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(resolution)

	get_viewport().size = resolution
	get_window().content_scale_size = Vector2i(0, 0)
	$"../Galaxy".set_resolution(resolution)


func _on_main_menu_set_msaa(status):
	get_viewport().msaa_3d = status


func _on_main_menu_set_taa(status):
	get_viewport().use_taa = status
