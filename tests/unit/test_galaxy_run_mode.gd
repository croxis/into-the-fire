extends GutTest
## Galaxy asks its own multiplayer whether this machine runs the world, not the
## entry node: a world works without entry (tests, later several worlds in one
## server). Offline counts as the server, as everywhere in Galaxy; entry only
## sets a world up once hosting succeeded.

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


func test_the_server_starts_its_world_without_entry() -> void:
	assert_null(get_tree().root.get_node_or_null("entry"))
	watch_signals(galaxy)
	galaxy.setup_new_galaxy(false, func() -> void: pass)
	assert_signal_emitted(galaxy, "load_scenes", "the scenario's scenes are loading")
	assert_true(galaxy.active_galaxy)


func test_a_client_starts_no_world() -> void:
	_make_client()
	watch_signals(galaxy)
	galaxy.setup_new_galaxy(false, func() -> void: pass)
	assert_signal_not_emitted(galaxy, "load_scenes")
	assert_false(galaxy.active_galaxy)


func test_a_joining_client_populates_nothing() -> void:
	# Its systems and ships come from the server's spawners.
	_make_client()
	watch_signals(galaxy)
	galaxy.finish_setup_galaxy_client()
	assert_signal_emitted(galaxy, "ready_to_spawn")
	assert_eq(galaxy.zones.systems().size(), 0)
