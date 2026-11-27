extends Node

var _dedicated_server := false
var _vr := false
var interface : XRInterface
var VR_DEBUG := false

const MainMenuScene := preload("res://ui/main_menu/main_menu.tscn")

var options: LaunchOptions
## Only exists when this process has a UI (not on a dedicated server).
var main_menu: Control
## The faction and spawn picker; only with a UI, and not for a test player
## given --faction (it spawns without the menu).
var join_flow: JoinFlow


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
	$Galaxy.scene_loader = $loading.load_scenes  # In the background, with a progress bar.
	if not options.headless:
		add_child(RenderWarmup.new())  # Draws every ship once behind the title screen.
	if options.has_ui():
		_add_main_menu()
		if not options.faction:
			join_flow = JoinFlow.new($Galaxy)
			add_child(join_flow)
	if options.wants_discord():
		_add_discord()

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
	main_menu.join_game.connect(func(_ip, _port, player_name, _s, _p) -> void:
			_show_role("Client", player_name))
	main_menu.join_game.connect($network._on_main_menu_join_game)
	main_menu.new_game.connect(_on_main_menu_new_game)
	main_menu.set_msaa.connect($DisplayManager._on_main_menu_set_msaa)
	main_menu.set_resolution.connect($DisplayManager.set_resolution)
	# set_ssaa has no handler yet; the old scene connection pointed at a missing method.
	main_menu.set_taa.connect($DisplayManager._on_main_menu_set_taa)


## Discord rich presence, only where someone plays on a screen. (The Discord
## GDExtension itself is loaded by the engine at startup in every mode; this
## keeps its client and per-frame callbacks off servers and headless runs.)
## discord.gd is loaded here, not preloaded: it uses the extension's classes, so
## a preload would stop this script compiling, and the game booting, whenever
## the extension fails to load.
func _add_discord() -> void:
	var discord := Control.new()
	discord.name = "Discord"
	discord.set_script(load("res://discord.gd"))
	add_child(discord)


## Puts "Host" or "Client" and the player's name in the window title.
func _show_role(role: String, player_name: String) -> void:
	if options.has_ui():
		get_window().title = LaunchOptions.window_title(
				ProjectSettings.get_setting("application/config/name"), role, player_name)


func _start_dedicated() -> void:
	_dedicated_server = true
	$Galaxy.max_rewind_ticks = ShotField.ticks_for_ms(options.max_rewind_ms)
	if not $network.start_server(options.game_name, options.password, options.port):
		print("Failure to activate network. Is port in use?")
		get_tree().quit(1)
		return
	$Galaxy.game_name = options.game_name
	if not $Galaxy.start_new_world():
		print("No world to serve: the scenario is missing or invalid (see the log).")
		get_tree().quit(1)


func _start_test_server() -> void:
	$Galaxy.max_rewind_ticks = ShotField.ticks_for_ms(options.max_rewind_ms)
	if not $network.host_server("Test Server", "Test Host", options.port):
		print("Failure to activate network. Is port in use?")
		get_tree().quit(1)
		return
	_show_role("Host", "Test Host")
	$Galaxy.game_name = "Test Server"
	$Galaxy.start_new_world(true)


func _start_test_player() -> void:
	if options.faction:
		# Spawn as soon as the server's factions arrive, as if picked in the menu.
		$Galaxy.factions_synced.connect(func() -> void:
				$Galaxy.spawns.request_spawn(options.faction, "", options.spawn_at),
				CONNECT_ONE_SHOT)
	if options.launch:
		_launch_when_aboard()
	_show_role("Client", options.player_name)
	await get_tree().create_timer(5.0).timeout
	$network.join_game(options.host, options.port, options.player_name, "", "")
	$loading.visible = false


## --launch: press Launch once the passenger HUD appears, as a player would.
func _launch_when_aboard() -> void:
	var hud: HudLayer = $Galaxy.hud
	while hud.passenger == null:
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(1.0).timeout
	Log.log(["Test player launching"], Log.MessageType.INFO)
	hud.passenger.request_launch.emit()
	if options.fire or options.fly:
		await get_tree().create_timer(3.0).timeout  # Clear of the arm.
	if options.fire:
		Log.log(["Test player holding the trigger"], Log.MessageType.INFO)
		Input.action_press("fire_primary")
	if options.fly:
		_fly_pattern()


## --fly: full thrust, then turns that change every 2 s (yaw, pitch, roll and
## combinations), as a pilot steering would; prediction tests count the
## corrections this costs.
func _fly_pattern() -> void:
	Log.log(["Test player flying a pattern"], Log.MessageType.INFO)
	Input.action_press("forward_full_thrust")
	var turns: Array[Array] = [["rotate_left_full"], ["rotate_up_full"], ["rotate_right_full", "clockwise_full"],
			[], ["rotate_down_full", "rotate_left_full"], ["counter_clockwise_full"]]
	var i := 0
	while is_inside_tree():
		for action in turns[i % turns.size()]:
			Input.action_press(action)
		await get_tree().create_timer(2.0).timeout
		for action in turns[i % turns.size()]:
			Input.action_release(action)
		i += 1


func _start_client() -> void:
	# OpenXR can only start with the engine (it picks the Vulkan device), so the
	# project leaves it off and XR runs only when the engine was started with
	# Godot's own `--xr-mode on`. The game uses XR whenever the engine started it.
	interface = XRServer.find_interface("OpenXR")
	var xr_running := interface != null and interface.is_initialized()
	if xr_running or options.xr or VR_DEBUG:
		if xr_running or (interface and interface.initialize()):
			print("OpenXR initialised successfully")
			_vr = true
			get_viewport().use_xr = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		else:
			print("OpenXR is not running. Start the game with --xr-mode on, ",
					"with the headset connected and an OpenXR runtime (e.g. SteamVR) active.")
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
	$Galaxy.max_rewind_ticks = ShotField.ticks_for_ms(options.max_rewind_ms)
	if not $network.host_server(game_name, player_name, port, server_password, player_password):
		return
	_show_role("Host", player_name)
	end_title_sequence()
	# Only once hosting worked: offline, this machine would count as the server
	# and start a world nobody can join.
	$Galaxy.game_name = game_name
	$Galaxy.start_new_world(true)
	


func _on_network_auth_failed(peer: Variant, reason: String) -> void:
	$AcceptDialog.dialog_text = reason
	$AcceptDialog.popup_centered()
