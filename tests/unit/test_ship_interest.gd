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
	interest.update({7: Interest.view(here, null, {ship: true}),
			8: Interest.view(elsewhere, null, {ship: true})}, {ship: here})  # 7 knows the ship, 8 doesn't.


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


## Galaxy.view_of: what a player's client may know (fog of war, N5b3): the
## sensor picture of their top-level faction (its ships and what they detect),
## in their system, and the ship they are aboard.

func _world() -> Dictionary:
	var galaxy: Galaxy = load("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)
	var system: System = load("res://systems/system_template.tscn").instantiate()
	galaxy.get_node("Systems").add_child(system)
	var ea := galaxy.factions.create("Earth Alliance")
	var zeta := galaxy.factions.create("Zeta Wing", true, true, false, ea)
	var narn := galaxy.factions.create("Narn Regime")
	var carrier: Ship = Content.instantiate(&"b5:hyperion")  # Sensitivity 10 (EM).
	system.add_ship(carrier)
	carrier.faction_id = ea.faction_id
	var raider: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(raider)
	raider.faction_id = narn.faction_id
	raider.position = Vector3(50000, 0, 0)  # 50 km: far out of sensor range.
	var player := carrier.get_node("CrewMultiplayerSpawner").spawn(
			Character.pilot_data("Player", zeta.faction_id, 1, 1, 3)) as Character
	return {"galaxy": galaxy, "system": system, "carrier": carrier, "raider": raider, "player": player}


func test_a_player_knows_their_own_sides_ships_and_not_an_unseen_enemy() -> void:
	var w := _world()
	var seen: Dictionary = (w.galaxy as Galaxy).view_of(w.player)
	assert_eq(seen["system"], w.system)
	assert_eq(seen["aboard"], w.carrier)
	assert_true((seen["picture"] as Dictionary).has(w.carrier), "Earth Alliance's own: a wing sees its parents'")
	assert_false((seen["picture"] as Dictionary).has(w.raider), "the Narn, unseen")


func test_once_detected_an_enemy_is_in_the_picture() -> void:
	var w := _world()
	(w.raider as Ship).position = Vector3(300, 0, 0)  # Within the carrier's sensors.
	(w.system as System).ship_scanner_check()
	var seen: Dictionary = (w.galaxy as Galaxy).view_of(w.player)
	assert_true((seen["picture"] as Dictionary).has(w.raider))


## Ghosts of lost contacts (N5c): what the server tells a client about a ship
## its side has lost, and the marker the client draws.

func test_a_lost_contact_is_reported_as_last_seen() -> void:
	var w := _world()
	var raider: Ship = w.raider
	raider.ship_id = 9
	raider.linear_velocity = Vector3(0, 0, -40)
	var data := Galaxy.contact_data(raider, 1234)
	assert_eq(data["name"], String(raider.name))
	assert_eq(data["faction_id"], raider.faction_id)
	assert_eq(data["system"], String((w.system as System).name))
	assert_almost_eq((data["transform"] as Transform3D).origin, raider.global_position, Vector3.ONE * 1e-6)
	assert_eq(data["velocity"], raider.linear_velocity)
	assert_false(data["immobile"], "a ship moves")
	assert_eq(data["tick"], 1234)
	assert_true(Galaxy.contact_data(w.carrier, 0)["immobile"] == (w.carrier as Ship).is_station)


func test_a_ghost_marker_drifts_fades_and_goes() -> void:
	var contacts := ContactLog.new(1.0 / 60.0)
	contacts.fade_seconds = 1.0
	contacts.lost(9, {"name": "Raider", "faction_id": 7, "system": "s", "velocity": Vector3(60, 0, 0),
			"transform": Transform3D(), "immobile": false, "tick": 0})
	var now := [0.0]
	var marker := GhostMarker.new()
	marker.setup(contacts, 9, func() -> float: return now[0])
	add_child_autofree(marker)
	marker._process(0.0)
	assert_almost_eq(marker.position, Vector3.ZERO, Vector3.ONE * 1e-9)
	assert_string_contains(marker.label_text(), "Raider")
	now[0] = 30.0  # Half a second: half faded, 30 m on.
	marker._process(0.0)
	assert_almost_eq(marker.position, Vector3(30, 0, 0), Vector3.ONE * 1e-9)
	assert_almost_eq(marker.alpha(), 0.5, 1e-6)
	now[0] = 61.0
	marker._process(0.0)
	assert_true(marker.is_queued_for_deletion(), "faded out: gone, though still on record")
	assert_false(contacts.get_contact(9).is_empty())


## Exclusions: a ship, wing or station kept out of its side's shared picture,
## withholding its position and what it detects. One-way: an excluded wing
## still sees the shared picture.

func _covert(w: Dictionary) -> Dictionary:
	var g: Galaxy = w.galaxy
	var ea := g.factions.find_by_name("Earth Alliance")
	var covert := g.factions.create("Covert Wing", true, true, false, ea)
	covert.excluded_from_picture = true
	var black: Ship = Content.instantiate(&"b5:aurora_starfury")
	(w.system as System).add_ship(black)
	black.faction_id = covert.faction_id
	black.position = Vector3(0, 0, 40000)  # Out of the carrier's sight.
	var spook := black.get_node("CrewMultiplayerSpawner").spawn(
			Character.pilot_data("Spook", covert.faction_id, 1, 2, 4)) as Character
	w["covert"] = covert
	w["black"] = black
	w["spook"] = spook
	return w


func test_an_excluded_wings_ships_are_not_in_the_shared_picture() -> void:
	var w := _covert(_world())
	var seen: Dictionary = (w.galaxy as Galaxy).view_of(w.player)  # A Zeta Wing pilot.
	assert_false((seen["picture"] as Dictionary).has(w.black), "the covert ship is withheld")
	assert_true((seen["picture"] as Dictionary).has(w.carrier), "the rest of the side is shared")


func test_an_excluded_wing_still_sees_the_shared_picture() -> void:
	var w := _covert(_world())
	var seen: Dictionary = (w.galaxy as Galaxy).view_of(w.spook)
	assert_true((seen["picture"] as Dictionary).has(w.carrier), "one-way: it gets the fleet's picture")
	assert_true((seen["picture"] as Dictionary).has(w.black), "and its own ships")


func test_what_an_excluded_ship_detects_is_withheld_too() -> void:
	var w := _covert(_world())
	(w.raider as Ship).position = (w.black as Ship).position + Vector3(300, 0, 0)  # Next to the covert ship.
	(w.system as System).ship_scanner_check()
	var zeta: Dictionary = (w.galaxy as Galaxy).view_of(w.player)
	assert_false((zeta["picture"] as Dictionary).has(w.raider), "only the covert ship saw it")
	var spook: Dictionary = (w.galaxy as Galaxy).view_of(w.spook)
	assert_true((spook["picture"] as Dictionary).has(w.raider))


func test_a_single_excluded_ship_is_seen_only_by_its_own_crew() -> void:
	var w := _world()
	var carrier: Ship = w.carrier
	carrier.excluded_from_picture = true
	var g: Galaxy = w.galaxy
	var zeta := g.factions.find_by_name("Zeta Wing")
	var other: Ship = Content.instantiate(&"b5:aurora_starfury")
	(w.system as System).add_ship(other)
	other.faction_id = zeta.faction_id
	var outsider := other.get_node("CrewMultiplayerSpawner").spawn(
			Character.pilot_data("Outsider", zeta.faction_id, 1, 5, 6)) as Character
	assert_false((g.view_of(outsider)["picture"] as Dictionary).has(carrier), "withheld from the side")
	assert_true(g.view_of(w.player)["aboard"] == carrier, "its own crew are aboard, so they know it")


## Galaxy.check_exclusion_change: only a leader of the owning faction, or of one
## above it, may change an exclusion (no UI yet; this is the server's check).

func test_only_leaders_above_may_change_an_exclusion() -> void:
	var w := _covert(_world())
	var g: Galaxy = w.galaxy
	var ea := g.factions.find_by_name("Earth Alliance")
	var player: Character = w.player  # pilot_id 1, Zeta Wing.
	assert_ne(Galaxy.check_exclusion_change(player, w.black), "", "not a leader")
	ea.leader_id = player.pilot_id
	assert_eq(Galaxy.check_exclusion_change(player, w.black), "", "leads a faction above it")
	assert_eq(Galaxy.check_exclusion_change(player, w.covert), "", "and above the wing")
	var narn := g.factions.find_by_name("Narn Regime")
	assert_ne(Galaxy.check_exclusion_change(player, w.raider), "", "not over another side's ships")
	narn.leader_id = 99
	(w.spook as Character).faction.leader_id = (w.spook as Character).pilot_id
	assert_eq(Galaxy.check_exclusion_change(w.spook, w.covert), "", "a wing's own leader")
	assert_ne(Galaxy.check_exclusion_change(w.spook, w.carrier), "", "but not the rest of the fleet")


func test_exclusions_are_not_sent_to_clients() -> void:
	# Which wings are covert is the server's to know.
	var w := _covert(_world())
	var data: Dictionary = (w.galaxy as Galaxy).factions.to_data()
	for entry: Dictionary in data["factions"]:
		assert_false(entry.has("excluded_from_picture"), entry["name"])
