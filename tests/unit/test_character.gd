extends GutTest
## Character brain activation and serialization.
##
## GUT runs with Godot's default OfflineMultiplayerPeer, so
## multiplayer.is_server() is true, like single player or a host.

const CharacterScene := preload("res://characters/character.tscn")


func _spawn(character_name: String) -> Character:
	var c: Character = CharacterScene.instantiate()
	c.name = character_name
	add_child_autofree(c)
	return c


func test_npc_brain_is_active_on_server() -> void:
	var npc := _spawn("NPC")
	assert_true(npc.hsm.is_active(), "NPCs think on the server")


func test_player_brain_is_inactive() -> void:
	var player := _spawn("Player")
	player._player_pilot_id = 1
	assert_false(player.hsm.is_active(), "players drive their own character")


func test_player_brain_turns_back_on_when_released() -> void:
	var c := _spawn("Possessed")
	c._player_pilot_id = 1
	c._player_pilot_id = 0
	assert_true(c.hsm.is_active(), "an NPC again once no player controls it")


func test_console_behavior_tree_is_driven_only_by_the_brain() -> void:
	# OperatingConsoleState ticks the BTPlayer itself. If the player also
	# updated on its own, NPC trees would tick twice and players would get AI.
	var c := _spawn("Gunner")
	var bt_player: BTPlayer = c.get_node("BrainHSM/OperatingConsoleState/BTPlayer")
	assert_eq(bt_player.update_mode, BTPlayer.UpdateMode.MANUAL)
	assert_false(bt_player.active, "inactive until the character sits at a console")


func test_player_id_can_be_set_before_entering_tree() -> void:
	# MultiplayerSpawner spawn functions restore state before add_child().
	var c: Character = CharacterScene.instantiate()
	c._player_pilot_id = 3
	add_child_autofree(c)
	assert_eq(c._player_pilot_id, 3)
	assert_false(c.hsm.is_active())


func test_serialize_restore_round_trip() -> void:
	var original := _spawn("Susan")
	original.pilot_id = 7
	original.multiplayer_id = 42
	original._player_pilot_id = 2
	original.hsm.blackboard.set_var(&"fighters_needed", 2)

	var payload := original.serialize()
	var copy: Character = CharacterScene.instantiate()
	copy.restore(payload)
	# Another parent, as when crew moves ships: siblings can't share a name.
	var other_ship_crew: Node = add_child_autofree(Node.new())
	other_ship_crew.add_child(copy)

	assert_eq(String(copy.name), "Susan")
	assert_eq(copy.pilot_id, 7)
	assert_eq(copy.multiplayer_id, 42)
	assert_eq(copy._player_pilot_id, 2)
	assert_eq(copy.faction_id, 0)
	assert_eq(copy.hsm.blackboard.get_var(&"fighters_needed"), 2)


func test_serialize_payload_has_no_objects() -> void:
	# Spawn payloads cross the network, which cannot carry Object references.
	var c := _spawn("Bot")
	c.hsm.blackboard.set_var(&"current_ship", autofree(Node.new()))
	c.hsm.blackboard.set_var(&"fighters_needed", 2)

	var payload := c.serialize()

	assert_false(payload.has("bb_current_ship"), "runtime object refs are rebuilt, not sent")
	assert_eq(payload.get("bb_fighters_needed"), 2)
	for key in payload:
		assert_false(payload[key] is Object, "payload[%s] must not be an Object" % key)


func test_serialize_orders_cross_the_network() -> void:
	# OrderData are Objects, and typed arrays of them can't be decoded by the
	# receiving peer ("Cannot assign contents of Array[Object]").
	var c := _spawn("Ordered")
	c.active_orders.append(OrderData.new())
	var payload := c.serialize()
	for key in ["active_orders", "pending_orders"]:
		var orders: Array = payload[key]
		assert_false(orders.is_typed(), "%s is a plain array" % key)
		for order in orders:
			assert_false(order is Object, "%s holds no Objects" % key)


## A player who disconnects keeps their character in the world; it is theirs
## again when they log back in. Meanwhile a one-seat craft brakes to a stop.

func _remote_pilot() -> Array:
	var fury: Ship = Content.instantiate(&"b5:aurora_starfury")
	add_child_autofree(fury)
	# Peer 7: a player on another machine, so the server flies them from their
	# tick-stamped input.
	var pilot: Character = fury.get_node("CrewMultiplayerSpawner").spawn(
			Character.pilot_data("Ivanova", 0, 7, 4))  # Seated as an NPC: no RPCs to a peer that isn't there.
	var cockpit := fury.get_node("Consoles/Cockpit") as Console
	cockpit.occupy(pilot)
	pilot._player_pilot_id = 3
	return [fury, pilot, cockpit.get_capability(HelmCapability)]


func test_a_disconnected_pilots_controls_go_neutral() -> void:
	var parts := _remote_pilot()
	var pilot: Character = parts[1]
	var helm: HelmCapability = parts[2]
	# Their last input, which the server would otherwise keep holding.
	pilot.input_channel._last = InputChannel.make_record(10, Vector3(0, 0, -1), Vector3(0, 1, 0))
	pilot.pilot_disconnected()
	pilot._apply_input(1.0 / 60.0, 11)
	assert_eq(helm.throttle, Vector3.ZERO)
	assert_eq(helm.input_rotation_throttle, Vector3.ZERO)


func test_a_one_seat_craft_brakes_to_a_stop() -> void:
	var parts := _remote_pilot()
	var helm: HelmCapability = parts[2]
	(parts[1] as Character).pilot_disconnected()
	assert_true(helm.autobreak, "stops moving")
	assert_true(helm.autospin, "stops turning")


func test_a_crewed_ship_is_left_to_its_crew() -> void:
	# Multi-crew ships: an NPC may take over the seat later (not built yet).
	var parts := _remote_pilot()
	var fury: Ship = parts[0]
	fury.get_node("Crew").max_crew = 4
	(parts[1] as Character).pilot_disconnected()
	assert_false((parts[2] as HelmCapability).autobreak)


func test_a_rejoining_player_takes_their_character_back() -> void:
	var parts := _remote_pilot()
	var pilot: Character = parts[1]
	pilot.pilot_disconnected()
	pilot.input_channel._last = InputChannel.make_record(50, Vector3(0, 0, -1), Vector3.ZERO)
	pilot.pilot_rejoined(9)  # A new connection, a new peer id.
	assert_eq(pilot.multiplayer_id, 9)
	assert_eq(pilot.get_node("InputsSync").get_multiplayer_authority(), 9, "their input again")
	assert_true(pilot.player_connected)
	assert_eq(pilot.input_channel.last_applied_tick, -1, "a fresh channel: the new client counts ticks anew")
	assert_eq([pilot._held_at_last_report, pilot._skipped_at_last_report], [0, 0], "its report counts from zero")


func test_a_new_player_id_moves_input_authority_with_it() -> void:
	# Clients learn the new peer from CharacterSync, which sets the property.
	var c := _spawn("Garibaldi")
	c.multiplayer_id = 12
	assert_eq(c.get_node("InputsSync").get_multiplayer_authority(), 12)
