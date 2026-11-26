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


func test_a_client_whose_connection_ends_goes_offline() -> void:
	# A refused login (or a server that goes away) closes the client's ENet
	# peer. Kept as the multiplayer peer, it still counts as "a peer" and
	# is_server() errors on it, every frame, in Galaxy._process.
	var network: Node = add_child_autofree(Network.new())
	var client := SceneMultiplayer.new()
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", 9)  # Never connects.
	client.multiplayer_peer = peer
	get_tree().set_multiplayer(client, network.get_path())
	peer.close()
	network.on_server_disconnected()
	assert_true(network.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "back to offline")
	assert_true(network.multiplayer.is_server(), "offline counts as the server, without errors")
	get_tree().set_multiplayer(null, network.get_path())


func test_a_player_can_join_again_after_a_refusal() -> void:
	# Each join connected the client's signals again, which Godot refuses with
	# an error ("already connected") on the second try.
	var network: Node = add_child_autofree(Network.new())
	var client := SceneMultiplayer.new()
	client.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().set_multiplayer(client, network.get_path())
	network.join_game("127.0.0.1", 9, "Ivanova", "", "")  # Never connects.
	network.on_server_disconnected()  # As after a refused login.
	network.join_game("127.0.0.1", 9, "Ivanova", "", "")
	assert_true(network.multiplayer.multiplayer_peer is ENetMultiplayerPeer, "joining again")
	assert_eq(network.multiplayer.server_disconnected.get_connections().size(), 1)
	network.multiplayer.multiplayer_peer.close()
	get_tree().set_multiplayer(null, network.get_path())


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
	assert_eq(ShipLaunch.launch_player(carrier, 3, WorldIds.new()), "")
	assert_does_not_have(carrier.get_crew(), me, "I launched")
	assert_has(carrier.get_crew(), someone_else, "they stayed aboard")


func test_a_launched_craft_is_shown_to_clients_once_it_is_in_the_bay() -> void:
	# Showing a ship sends its spawn at once, with its position then: shown as it
	# entered the world (at the origin), it appeared on clients 5.8 km from the
	# Hyperion and snapped over. Shown after it is placed, it starts in the bay.
	var galaxy: Galaxy = load("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)
	var system := SystemScene.instantiate() as System
	galaxy.get_node("Systems").add_child(system)
	var carrier := _carrier(system)
	carrier.position = Vector3(5800, 0, 0)
	var wing := galaxy.factions.create("Zeta Wing", true, true)
	carrier.spawn_crew(Character.pilot_data("Player 3", wing.faction_id, 1, 3, 3))
	var launched_at: Array[Vector3] = []
	var launched_sides: Array[int] = []
	var player_in_world: Array[bool] = []
	galaxy.interest_refreshed.connect(func() -> void:
			player_in_world.append(Galaxy.find_player_character(galaxy.get_node("Systems"), 3) != null)
			for ship in system.get_ships():
				if ship.is_spawning:
					launched_at.append(ship.global_position)
					launched_sides.append(ship.faction_id))
	assert_eq(ShipLaunch.launch_player(carrier, 3, WorldIds.new()), "")
	assert_false(launched_at.is_empty(), "shown during the launch")
	for at in launched_at:
		assert_gt(at.x, 5000.0, "in the Hyperion's bay, not at the origin")
	# Between leaving the carrier and boarding the craft the player has no
	# character, and a client without one knows no ships at all.
	assert_false(false in player_in_world, "never refreshed while the player was between ships")
	# Fog of war (N5b3): the pilot's client knows it through their faction's
	# picture, so it must be theirs already.
	assert_false(FactionRegistry.NO_FACTION in launched_sides, "the pilot's side's when shown")


func test_launch_is_refused_for_a_player_who_is_not_aboard() -> void:
	var system := _system()
	var carrier := _carrier(system)
	_player_aboard(carrier, 4)
	var ships_before := system.get_ships().size()
	assert_ne(ShipLaunch.launch_player(carrier, 3, WorldIds.new()), "")
	assert_eq(system.get_ships().size(), ships_before, "no fighter is built")


func test_launch_is_refused_from_a_ship_without_launch_bays() -> void:
	var system := _system()
	var fighter: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(fighter)
	_aboard_quietly(fighter, 3, 1)
	assert_ne(ShipLaunch.launch_player(fighter, 3, WorldIds.new()), "")


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
