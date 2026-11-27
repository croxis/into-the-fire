extends GutTest
## Command-line parsing for run modes.

const Mode := LaunchOptions.Mode


func test_no_flags_is_client() -> void:
	var o := LaunchOptions.parse(PackedStringArray())
	assert_eq(o.mode, Mode.CLIENT)
	assert_true(o.has_ui())


func test_server_flag_is_dedicated_with_settings() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--server", "--game=Epsilon", "--password=pw", "--port=3000"]))
	assert_eq(o.mode, Mode.DEDICATED)
	assert_false(o.has_ui())
	assert_eq(o.game_name, "Epsilon")
	assert_eq(o.password, "pw")
	assert_eq(o.port, 3000, "port is an int, not the raw string")


func test_dedicated_feature_is_dedicated() -> void:
	var o := LaunchOptions.parse(PackedStringArray(), false, true)
	assert_eq(o.mode, Mode.DEDICATED)


func test_headless_without_flags_is_dedicated() -> void:
	var o := LaunchOptions.parse(PackedStringArray(), true)
	assert_eq(o.mode, Mode.DEDICATED)


func test_headless_test_server_keeps_its_mode() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--testserver"]), true)
	assert_eq(o.mode, Mode.TEST_SERVER)


func test_test_player() -> void:
	assert_eq(LaunchOptions.parse(PackedStringArray(["--testplayer"])).mode, Mode.TEST_PLAYER)


func test_values_may_contain_equals() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--password=a=b"]))
	assert_eq(o.password, "a=b")


func test_test_player_joins_localhost_by_default() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--testplayer"]))
	assert_eq(o.host, "127.0.0.1")


func test_host_flag_sets_join_address() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--testplayer", "--host=192.168.1.20"]))
	assert_eq(o.host, "192.168.1.20")
	assert_does_not_have(o.unknown, "--host")


func test_empty_host_keeps_default() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--testplayer", "--host="]))
	assert_eq(o.host, LaunchOptions.DEFAULT_HOST)


func test_bad_port_keeps_default() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--server", "--port=abc"]))
	assert_eq(o.port, LaunchOptions.DEFAULT_PORT)
	assert_has(o.unknown, "--port=abc")


func test_xr_flag() -> void:
	assert_true(LaunchOptions.parse(PackedStringArray(["--xr_mode"])).xr)


func test_unknown_flags_are_reported() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--bogus", "stray"]))
	assert_has(o.unknown, "--bogus")
	assert_has(o.unknown, "stray")
	assert_eq(o.mode, Mode.CLIENT)


func test_test_player_can_pick_a_faction() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--testplayer", "--faction=Zeta Wing"]))
	assert_eq(o.faction, "Zeta Wing")
	assert_eq(o.unknown.size(), 0)
	assert_eq(LaunchOptions.parse(PackedStringArray(["--testplayer"])).faction, "",
			"no faction: wait in the join menu")


func test_test_player_can_pick_a_spawn_point() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--testplayer", "--faction=Zeta Wing",
			"--spawn-at=EASS Hyperion"]))
	assert_eq(o.spawn_at, "EASS Hyperion")
	assert_eq(o.unknown.size(), 0)
	assert_eq(LaunchOptions.parse(PackedStringArray(["--testplayer"])).spawn_at, "",
			"none: the first spawn point")


## restart_args: the arguments for restarting the game with XR on or off.

func test_restart_into_xr_adds_the_engine_flag() -> void:
	var args := LaunchOptions.restart_args(PackedStringArray(["--testserver"]), true, "", true)
	assert_eq(args, PackedStringArray(["--testserver", "--xr-mode", "on"]))


func test_restart_out_of_xr_has_no_engine_flag() -> void:
	# The engine consumed --xr-mode, so it isn't in the current arguments.
	var args := LaunchOptions.restart_args(PackedStringArray(["--testserver"]), false, "", true)
	assert_eq(args, PackedStringArray(["--testserver"]))


func test_restart_drops_the_old_game_xr_flag() -> void:
	var args := LaunchOptions.restart_args(PackedStringArray(["--xr_mode"]), false, "", true)
	assert_eq(args, PackedStringArray(), "otherwise it would restart into the XR hint and quit")


func test_restart_from_source_keeps_the_project_path() -> void:
	# The engine consumes --path too; a source run needs it to find the project again.
	var args := LaunchOptions.restart_args(PackedStringArray(), true, "/home/me/ITF", false)
	assert_eq(args, PackedStringArray(["--path", "/home/me/ITF", "--xr-mode", "on"]))


# Discord rich presence runs only where a player is looking at a screen.

func test_discord_runs_for_a_client_with_a_screen() -> void:
	assert_true(LaunchOptions.parse(PackedStringArray()).wants_discord())
	assert_true(LaunchOptions.parse(PackedStringArray(["--testserver"])).wants_discord())


func test_no_discord_on_a_dedicated_server() -> void:
	assert_false(LaunchOptions.parse(PackedStringArray(["--server"])).wants_discord())
	assert_false(LaunchOptions.parse(PackedStringArray(), false, true).wants_discord(), "dedicated_server export")


func test_no_discord_when_headless() -> void:
	# A headless test player still has a menu, but nobody to show presence for.
	assert_false(LaunchOptions.parse(PackedStringArray(["--testplayer"]), true).wants_discord())
	assert_false(LaunchOptions.parse(PackedStringArray(), true).wants_discord())


func test_no_discord_when_its_extension_did_not_load() -> void:
	# A missing system library (CI lacked libatomic) leaves the Discord classes undefined.
	assert_false(LaunchOptions.parse(PackedStringArray()).wants_discord(false))


func test_entry_does_not_need_discord_to_compile() -> void:
	# A preload makes entry.gd fail to compile, and nothing boots, when Discord is missing.
	var preloaded: Array[String] = []
	for value in (load("res://entry.gd") as Script).get_script_constant_map().values():
		if value is Resource:
			preloaded.append(value.resource_path)
	assert_does_not_have(preloaded, "res://discord.gd")


func test_launch_flag_for_automated_flight_tests() -> void:
	# --testplayer --faction=X --launch: board, then launch, with no menu clicks.
	var options := LaunchOptions.parse(PackedStringArray(["--testplayer", "--faction=Zeta Wing", "--launch"]))
	assert_true(options.launch)
	assert_false("--launch" in options.unknown)
	assert_false(LaunchOptions.parse(PackedStringArray(["--testplayer"])).launch)


# Window title: which window is which when a host and clients run side by side.

func test_window_title_names_the_role_and_player() -> void:
	assert_eq(LaunchOptions.window_title("Into The Fire", "Host", "Test Host"),
			"Into The Fire [Host: Test Host]")
	assert_eq(LaunchOptions.window_title("Into The Fire", "Client", "Test Player"),
			"Into The Fire [Client: Test Player]")


func test_window_title_without_a_player_name() -> void:
	assert_eq(LaunchOptions.window_title("Into The Fire", "Client", ""), "Into The Fire [Client]")


func test_test_players_can_fly_a_pattern() -> void:
	var options := LaunchOptions.parse(PackedStringArray(["--testplayer", "--faction=Zeta Wing", "--launch", "--fly"]))
	assert_true(options.fly)
	assert_false("--fly" in options.unknown)
