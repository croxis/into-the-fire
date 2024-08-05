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
		var game_name := "default"
		var game_pass := ""
		if "game" in arguments:
			game_name = arguments["game"]
		if "password" in arguments:
			game_pass = arguments["password"]
		if "port" in arguments:
			success = $network.start_server(game_name, game_pass, arguments["port"])
		else:
			success = $network.start_server(game_name, game_pass)
		if not success:
			print("Failure to activate network. Is port in use?")
			get_tree().quit()
		_dedicated_server = true
		$Galaxy.setup_new_galaxy(true)
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
			print_debug("resolution:", AppConfig.get_value("graphics", "resolution_x"))
		$loading.load_scene("res://title_screen.tscn", get_tree().root, true, true)
		$MainMenu.visible = true
		
	# Yes this is gross
	$network.players = $Galaxy/Players


func end_title_sequence() -> void:
	if get_parent().has_node("title screen"):
		print_debug("ending title")
		get_parent().get_node("title screen").queue_free()
	$MainMenu.visible = false
	

func _on_network_connection_succeeded():
	end_title_sequence()


func _on_main_menu_new_game(game_name, player_name, port, server_password, player_password):
	if not $network.host_server(game_name, player_name, port, server_password, player_password):
		return
	end_title_sequence()
	
	
