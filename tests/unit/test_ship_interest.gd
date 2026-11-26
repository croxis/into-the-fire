extends GutTest
## A ship exists on a client only while interest management says the client
## knows it (netcode slice N5a2). Godot spawns a node on a peer, and syncs to
## it, only while the node's synchronizers are visible to that peer, so every
## synchronizer in the ship, its crew's too, asks Interest. (Godot doesn't let
## scripts read a synchronizer's filters or ask it is_visible_to, so these check
## that each one was given the ship's filter, and what the filter says.)

var interest: Interest
var ship: Ship


func before_each() -> void:
	interest = Interest.new()
	ship = Content.instantiate(&"b5:aurora_starfury")
	ship.interest_override = interest
	add_child_autofree(ship)
	var here := RefCounted.new()  # Stand-ins for systems.
	var elsewhere := RefCounted.new()
	interest.update({7: here, 8: elsewhere}, {ship: here}, [])  # 7 knows the ship, 8 doesn't.


func _synchronizers(node: Node) -> Array[Node]:
	return node.find_children("*", "MultiplayerSynchronizer", true, false)


func test_the_filter_says_who_knows_the_ship() -> void:
	ship._add_peer_with_ship(7)
	ship._add_peer_with_ship(8)
	assert_true(ship.is_known_to(7))
	assert_false(ship.is_known_to(8))
	assert_true(ship.is_held_by(7))


func test_nothing_but_the_spawn_goes_before_the_client_has_the_ship() -> void:
	# Snapshots and the helms' syncs are unreliable: sent at once, they overtook
	# the (larger, reliable) spawn and found no ship. They wait for the client's
	# _have_ship, which it sends from the ship's _ready.
	assert_false(ship.is_known_to(7), "spawned, not yet confirmed")
	assert_true(ship.is_held_by(7), "but the spawn goes")
	ship._add_peer_with_ship(7)
	assert_true(ship.is_known_to(7))


func test_a_despawn_forgets_that_the_client_had_the_ship() -> void:
	# Its next copy there confirms itself again.
	ship._add_peer_with_ship(7)
	ship.forget_peer_with_ship(7)  # update_interest(peer, false, true) does this.
	assert_false(ship.is_known_to(7))


func test_synchronizers_that_keep_a_node_spawned_last_until_it_goes() -> void:
	# A leaving ship (Interest.holds, not knows) stays on the client: its own
	# and its crew's synchronizers decide that. The rest stop at once.
	var npc := ship.spawn_crew(Character.pilot_data("Karren", 0, 1, 1))
	assert_true(ship._filtered[ship.get_node("MultiplayerSynchronizer") as MultiplayerSynchronizer], "the ship's own: held")
	assert_true(ship._filtered[npc.get_node("CharacterSync") as MultiplayerSynchronizer], "crew: held")
	var helm_sync: MultiplayerSynchronizer = ship.get_node("Consoles/Cockpit").find_children(
			"*", "MultiplayerSynchronizer", true, false)[0]
	assert_false(ship._filtered[helm_sync], "the helm's: known only")


func test_held_synchronizers_send_nothing_unreliable() -> void:
	# While a ship is leaving they still send; anything unreliable could arrive
	# after the despawn and find no node. On change is sent reliably.
	var npc := ship.spawn_crew(Character.pilot_data("Karren", 0, 1, 1))
	for sync: MultiplayerSynchronizer in ship._filtered:
		if not ship._filtered[sync]:
			continue
		var config := sync.replication_config
		for path in config.get_properties():
			assert_ne(config.property_get_replication_mode(path), SceneReplicationConfig.REPLICATION_MODE_ALWAYS,
					"%s %s" % [sync.get_parent().name, path])


func test_we_decide_when_visibility_is_checked() -> void:
	# Not every frame: that is a filter call per synchronizer per client per
	# frame, and the order (crew before their ship) would be Godot's.
	for sync: MultiplayerSynchronizer in _synchronizers(ship):
		assert_eq(sync.visibility_update_mode, MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE)


func test_every_synchronizer_in_the_ship_follows_interest() -> void:
	var syncs := _synchronizers(ship)
	assert_gt(syncs.size(), 1, "the ship's own and its helm's at least")
	for sync: MultiplayerSynchronizer in syncs:
		assert_true(ship._filtered.has(sync), String(ship.get_path_to(sync)))


func test_crew_that_board_later_follow_it_too() -> void:
	var npc := ship.spawn_crew(Character.pilot_data("Karren", 0, 1, 1))  # Server-owned inputs.
	for sync: MultiplayerSynchronizer in _synchronizers(npc):
		assert_true(ship._filtered.has(sync), String(sync.name))


func test_hidden_crew_go_before_their_ship_and_come_back_after_it() -> void:
	# A client must never hold crew without their ship (they would have no
	# parent), so crew despawn first and spawn last.
	var npc := ship.spawn_crew(Character.pilot_data("Karren", 0, 1, 1))
	var root: Node = ship.get_node("MultiplayerSynchronizer")
	var crew_sync: Node = npc.get_node("CharacterSync")
	var hiding: Array[MultiplayerSynchronizer] = ship.synchronizers_in_order(false)
	var showing: Array[MultiplayerSynchronizer] = ship.synchronizers_in_order(true)
	assert_eq(hiding[-1], root, "the ship last when hiding")
	assert_lt(hiding.find(crew_sync), hiding.find(root))
	assert_eq(showing[0], root, "the ship first when showing")
	assert_gt(showing.find(crew_sync), showing.find(root))
	assert_eq(hiding.size(), _synchronizers(ship).size(), "all of them")


func test_a_players_own_inputs_go_only_to_the_server() -> void:
	# Remote pilots send input through InputChannel; a client-owned InputsSync
	# sent everywhere would reach clients that don't have the character.
	var c: Character = autofree(preload("res://characters/character.tscn").instantiate())
	c.send_inputs_only_to_server()
	var sync: MultiplayerSynchronizer = c.get_node("InputsSync")
	assert_false(sync.public_visibility)
	assert_true(sync.get_visibility_for(1))
	assert_false(sync.get_visibility_for(5))


func test_boarding_a_ship_refreshes_interest_at_once() -> void:
	# A player who spawns aboard must know the ship before the server's camera
	# and HUD RPCs reach them: Godot refuses an RPC to a peer that can't see the
	# node. Waiting for the next 0.5 s refresh lost them (the HUD never showed).
	var galaxy: Galaxy = load("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)
	var system: System = load("res://systems/system_template.tscn").instantiate()
	galaxy.get_node("Systems").add_child(system)
	var aboard: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(aboard)
	var crew_then: Array[int] = []
	galaxy.interest_refreshed.connect(func() -> void: crew_then.append(aboard.get_crew().size()))
	aboard.spawn_crew(Character.pilot_data("Susan", 0, 1, 1))
	assert_eq(crew_then, [1] as Array[int], "refreshed once, with her aboard")
