extends Node

var _dedicated_server := false
var is_server := false
var _vr := false
var interface : XRInterface
var VR_DEBUG := false

const MainMenuScene := preload("res://ui/main_menu/main_menu.tscn")

var options: LaunchOptions
## Only exists when this process has a UI (not on a dedicated server).
var main_menu: Control


func _input(event):
	if event.is_action_pressed("ui_cancel") and main_menu:
		main_menu.visible = not main_menu.visible
	if Input.is_action_pressed("ui_debug"):
		print_debug("Debug UI")
		$MonitorOverlay.visible = not $MonitorOverlay.visible


func _ready():
	options = LaunchOptions.parse(OS.get_cmdline_args(),
			DisplayServer.get_name() == "headless", OS.has_feature("dedicated_server"))
	Log.log(["Launch: ", options], Log.MessageType.INFO)
	if not options.unknown.is_empty():
		Log.log(["Ignored arguments: ", options.unknown], Log.MessageType.INFO)
	$network.players = $Galaxy/Players
	if options.has_ui():
		_add_main_menu()

	match options.mode:
		LaunchOptions.Mode.DEDICATED:
			_start_dedicated()
		LaunchOptions.Mode.TEST_SERVER:
			_start_test_server()
		LaunchOptions.Mode.TEST_PLAYER:
			_start_test_player()
		LaunchOptions.Mode.CLIENT:
			_start_client()


## The menu builds option screens that need a real display server, so a
## dedicated server never creates it.
func _add_main_menu() -> void:
	main_menu = MainMenuScene.instantiate()
	main_menu.name = "MainMenu"
	main_menu.visible = false
	add_child(main_menu)
	move_child(main_menu, $network.get_index() + 1)  # Same draw order as before.
	# Order matters: entry hosts the server before Galaxy checks is_server.
	main_menu.join_game.connect($Galaxy._on_main_menu_join_game)
	main_menu.join_game.connect($network._on_main_menu_join_game)
	main_menu.new_game.connect(_on_main_menu_new_game)
	main_menu.new_game.connect($Galaxy._on_main_menu_new_game)
	main_menu.set_msaa.connect($DisplayManager._on_main_menu_set_msaa)
	main_menu.set_resolution.connect($DisplayManager.set_resolution)
	# set_ssaa has no handler yet; the old scene connection pointed at a missing method.
	main_menu.set_taa.connect($DisplayManager._on_main_menu_set_taa)


func _start_dedicated() -> void:
	_dedicated_server = true
	if not $network.start_server(options.game_name, options.password, options.port):
		print("Failure to activate network. Is port in use?")
		get_tree().quit(1)
		return
	$Galaxy.setup_new_galaxy(true)


func _start_test_server() -> void:
	if not $network.host_server("Test Server", "Test Host", options.port):
		print("Failure to activate network. Is port in use?")
		get_tree().quit(1)
		return
	var callback := Callable($Galaxy, "finish_setup_galaxy_client")
	$Galaxy.game_name = "Test Server"
	$Galaxy.setup_new_galaxy(false, callback)


func _start_test_player() -> void:
	if options.faction:
		# Spawn as soon as the server's factions arrive, as if picked in the menu.
		$Galaxy.factions_synced.connect(func() -> void:
				$Galaxy._on_join_game_request_spawn(options.faction, "test_system", ""),
				CONNECT_ONE_SHOT)
	await get_tree().create_timer(5.0).timeout
	$network.join_game("127.0.0.1", options.port, "Test Player", "", "")
	$loading.visible = false


func _start_client() -> void:
	if options.xr or VR_DEBUG:
		interface = XRServer.find_interface("OpenXR")
		print_debug(interface)
		if interface and interface.initialize():
			print("OpenXR initialised successfully")
			_vr = true
			get_viewport().use_xr = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		else:
			print("OpenXR not initialised, please check if your headset is connected")
			get_tree().quit(1)
			return
	else:
		print_debug("resolution:", PlayerConfig.get_config("graphics", "resolution_x"))
	$loading.load_scene("res://title_screen.tscn", get_tree().root, true, true)
	main_menu.visible = true


func end_title_sequence() -> void:
	Log.log(["Trying to end title"], Log.MessageType.INFO)
	if get_parent().has_node("title screen"):
		Log.log(["Ending Title"], Log.MessageType.INFO)
		get_parent().get_node("title screen").queue_free()
	if main_menu:
		main_menu.visible = false
	

func _on_network_connection_succeeded():
	Log.log(["Connection Succeded"], Log.MessageType.INFO)
	end_title_sequence()


func _on_main_menu_new_game(game_name, player_name, port, server_password, player_password):
	if not $network.host_server(game_name, player_name, port, server_password, player_password):
		return
	end_title_sequence()
	


func _on_network_auth_failed(peer: Variant, reason: String) -> void:
	$AcceptDialog.dialog_text = reason
	$AcceptDialog.popup_centered()
