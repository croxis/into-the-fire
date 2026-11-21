extends GutTest
## Character brain activation and serialization.
##
## GUT runs with Godot's default OfflineMultiplayerPeer, so
## multiplayer.is_server() is true, like single player or a host.

const CharacterScene := preload("res://characters/character.tscn")


func before_each() -> void:
	Faction.factions.clear()
	Faction._next_id = 0
	# Characters default to faction_id 0, so faction 0 must exist.
	Faction.new_faction("Test Faction", false, true, false)


func after_all() -> void:
	Faction.factions.clear()
	Faction._next_id = 0


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
