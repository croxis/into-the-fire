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
