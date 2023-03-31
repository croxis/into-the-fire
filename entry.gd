extends Node

var _dedicated_server := false
var _vr := false
var interface : XRInterface
var VR_DEBUG := false

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		$MainMenu.visible = not $MainMenu.visible
	if Input.is_action_pressed("ui_debug"):
		print_debug("Debug UI")
		$MonitorOverlay.visible = not $MonitorOverlay.visible


func _ready():
	var arguments = {}
	for argument in OS.get_cmdline_args():
		if argument.find("=") > -1:
			var key_value = argument.split("=")
			arguments[key_value[0].lstrip("--")] = key_value[1]
		else:
			arguments[argument.lstrip("--")] = 1
	print("Arguments: ", arguments)
	if ("server" in arguments || OS.has_feature("dedicated_server")):
		var success := false
		if "port" in arguments:
			success = $network.host_server("Server", arguments["port"])
		else:
			success = $network.host_server("Server")
		if not success:
			print("Failure to activate network. Is port in use?")
			get_tree().quit()
		_dedicated_server = true
	else:
		if "xr_mode" in arguments or VR_DEBUG:
			interface = XRServer.find_interface("OpenXR")
			print_debug(interface)
			interface.initialize()
			if interface and interface.is_initialized():
				print("OpenXR initialised successfully")
				_vr = true
				get_viewport().use_xr = true
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			else:
				print("OpenXR not initialised, please check if your headset is connected")
				get_tree().quit()
		else:
			#TODO: Do this all with an option window, but this is default!
			$DisplayManager.set_resolution(Vector2i(0, 0))
		$loading.load_scene("res://title_screen.tscn", get_tree().root, true, true)
		$MainMenu.visible = true


func end_title_sequence() -> void:
	if get_parent().has_node("title screen"):
		print_debug("ending title")
		get_parent().get_node("title screen").queue_free()
	$MainMenu.visible = false
	

func _process(_delta):
	if not _dedicated_server:
		return
		#Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'FPS', 'value': "FPS: " + str(Performance.get_monitor(Performance.TIME_FPS)) })
		#Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Physics Time', 'value': str(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) / 1000.0) + " ms" })
		#Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Objects', 'value': str(Performance.get_monitor(Performance.OBJECT_COUNT)) + " objects" })
		#Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Objects Frame', 'value': str(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)) + " objects in frame" })
		#Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Primatives Frame', 'value': str(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) + " primatives in frame" })
		#Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Draws', 'value': str(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)) + " draws" })
		#Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Video Mem', 'value': str(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0) + " MB" })
		#Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Texture Mem', 'value': str(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0) + " MB texture" })


func _on_network_connection_succeeded():
	end_title_sequence()
	# Hack until we figure out what we are doing
	$Galaxy.player_enter_system("test_system")


func _on_main_menu_new_game(player_name, port):
	if not $network.host_server(player_name, port):
		return
	end_title_sequence()
	# Hack until we figure out what we are doing
	$Galaxy.player_enter_system("test_system")
	$Galaxy._on_network_connection_succeeded()
	


