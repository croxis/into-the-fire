extends GutTest
## The server checks what clients ask for (netcode slice N1). Clients can send
## anything: logins, spawn and launch requests, inputs. Never trust their IDs.

const Network := preload("res://network/network.gd")
const SystemScene := preload("res://systems/system_template.tscn")


# Logins ---------------------------------------------------------------------

func _login(overrides := {}) -> Dictionary:
	var login := {
		"client_token": "me2",
		"server_password": "",
		"player_name": "Ivanova",
		"player_password": "secret",
	}
	login.merge(overrides, true)
	return login


func test_a_well_formed_login_is_accepted() -> void:
	assert_eq(Network.check_login(_login()), "")


func test_a_login_that_is_not_a_dictionary_is_refused() -> void:
	assert_ne(Network.check_login("hello"), "")
	assert_ne(Network.check_login(null), "")
	assert_ne(Network.check_login([1, 2]), "")


func test_a_login_with_missing_or_wrong_fields_is_refused() -> void:
	var missing := _login()
	missing.erase("player_name")
	assert_ne(Network.check_login(missing), "")
	assert_ne(Network.check_login(_login({"player_password": 42})), "", "fields must be strings")


func test_player_names_must_be_safe_node_names() -> void:
	# Names become node names under Players, and are looked up with has_node.
	for name in ["Ivanova", "G'Kar", "Lt Commander Ivanova", "Zack_Allan-2"]:
		assert_true(Network.valid_player_name(name), name)
	for name in ["", "..", "../Systems", "a/b", "Dr. Franklin", "x:y", "%unique", " Sheridan",
			"An extremely long player name over 32"]:
		assert_false(Network.valid_player_name(name), name)


# Spawning -------------------------------------------------------------------

func _system() -> System:
	var system: System = SystemScene.instantiate()
	add_child_autofree(system)
	return system


func _carrier(system: System) -> Ship:
	var ship: Ship = Content.instantiate(&"b5:hyperion")
	system.add_ship(ship)
	return ship


func _player_aboard(ship: Ship, player_id: int, peer := 1) -> Character:
	return ship.spawn_crew(Character.pilot_data("Player %d" % player_id, 0, peer, player_id, player_id))


## Aboard without the camera and HUD RPCs spawn_crew sends (for ships without a
## passenger camera, or a peer that isn't connected).
func _aboard_quietly(ship: Ship, player_id: int, peer: int) -> Character:
	var data := Character.pilot_data("Player %d" % player_id, 0, peer, player_id, player_id)
	return ship.get_node("CrewMultiplayerSpawner").spawn(data)


func test_a_player_already_in_the_world_is_found() -> void:
	var systems := Node.new()
	add_child_autofree(systems)
	var system: System = SystemScene.instantiate()
	systems.add_child(system)
	var carrier := _carrier(system)
	var me := _player_aboard(carrier, 3)
	assert_eq(Galaxy.find_player_character(systems, 3), me)
	assert_null(Galaxy.find_player_character(systems, 4), "player 4 has no character yet")


# Launching ------------------------------------------------------------------

func test_launch_takes_the_senders_own_character() -> void:
	var system := _system()
	var carrier := _carrier(system)
	var me := _player_aboard(carrier, 3)
	var someone_else := _player_aboard(carrier, 4)
	assert_eq(carrier.launch_player(3, WorldIds.new()), "")
	assert_does_not_have(carrier.get_crew(), me, "I launched")
	assert_has(carrier.get_crew(), someone_else, "they stayed aboard")


func test_launch_is_refused_for_a_player_who_is_not_aboard() -> void:
	var system := _system()
	var carrier := _carrier(system)
	_player_aboard(carrier, 4)
	var ships_before := system.get_ships().size()
	assert_ne(carrier.launch_player(3, WorldIds.new()), "")
	assert_eq(system.get_ships().size(), ships_before, "no fighter is built")


func test_launch_is_refused_from_a_ship_without_launch_bays() -> void:
	var system := _system()
	var fighter: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(fighter)
	_aboard_quietly(fighter, 3, 1)
	assert_ne(fighter.launch_player(3, WorldIds.new()), "")


# Debug commands -------------------------------------------------------------

func test_debug_commands_only_from_this_machines_own_player() -> void:
	# On a listen server the host's own character may all-stop; a remote
	# client's inputs arrive here too, and must not.
	var system := _system()
	var carrier := _carrier(system)
	var host := _player_aboard(carrier, 3, multiplayer.get_unique_id())
	var remote := _aboard_quietly(carrier, 4, 99)
	assert_true(host.debug_commands_allowed())
	assert_false(remote.debug_commands_allowed())
