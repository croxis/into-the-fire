extends GutTest
## WorldReplicator: what a joining client is told about the world, besides the
## ships and crews its spawners bring (those go by interest, network/). A
## snapshot on join, replacing the client's copy as a whole; never patched from
## client data. Offline, this machine is the server: its world is always ready.

var galaxy: Galaxy
var _peer: ENetMultiplayerPeer


func before_each() -> void:
	galaxy = preload("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)


func after_each() -> void:
	if _peer:
		_peer.close()
		get_tree().set_multiplayer(null, galaxy.get_path())
		_peer = null


func _make_client() -> void:
	var client := SceneMultiplayer.new()
	_peer = ENetMultiplayerPeer.new()
	_peer.create_client("127.0.0.1", 9)  # Never connects: a client all the same.
	client.multiplayer_peer = _peer
	get_tree().set_multiplayer(client, galaxy.get_path())


func test_the_server_world_is_ready_at_once() -> void:
	assert_true(galaxy.replicator.world_ready())


func test_a_client_waits_for_the_snapshot() -> void:
	_make_client()
	assert_false(galaxy.replicator.world_ready())


func test_a_snapshot_replaces_the_clients_factions() -> void:
	var server_factions := FactionRegistry.new()
	server_factions.create("Earth Alliance", false, true)
	server_factions.create("Narn Regime")
	var snapshot := WorldReplicator.snapshot_of(server_factions)
	_make_client()
	galaxy.factions.create("Stale")
	watch_signals(galaxy.replicator)
	galaxy.replicator.apply_snapshot(snapshot)
	assert_signal_emitted(galaxy.replicator, "snapshot_received")
	assert_true(galaxy.replicator.world_ready())
	assert_eq(galaxy.factions.size(), 2)
	assert_null(galaxy.factions.find_by_name("Stale"))
	assert_not_null(galaxy.factions.find_by_name("Earth Alliance"))


func test_a_snapshot_from_another_version_is_refused() -> void:
	# A server and client from different builds must not half-apply a world.
	_make_client()
	var snapshot := WorldReplicator.snapshot_of(FactionRegistry.new())
	snapshot["version"] = WorldReplicator.SNAPSHOT_VERSION + 1
	galaxy.factions.create("Mine")
	galaxy.replicator.apply_snapshot(snapshot)
	assert_false(galaxy.replicator.world_ready())
	assert_not_null(galaxy.factions.find_by_name("Mine"), "left as it was")
