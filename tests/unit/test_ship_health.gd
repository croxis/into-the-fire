extends GutTest
## A ship's health: it starts at its own max_health, and only the server
## destroys a ship (clients learn of it as a despawn), once.

const ShipScene := preload("res://ships/Ship.tscn")


func _ship() -> Ship:
	var ship: Ship = ShipScene.instantiate()
	add_child_autofree(ship)
	return ship


func test_a_ship_starts_at_its_own_max_health() -> void:
	var hyperion: Ship = Content.instantiate(&"b5:hyperion")
	add_child_autofree(hyperion)
	assert_eq(hyperion.max_health, 1000)
	assert_eq(hyperion.health, hyperion.max_health,
			"health was set from the default max_health before the scene's own was applied")


func test_the_server_destroys_a_ship_at_zero_health() -> void:
	var ship := _ship()
	watch_signals(ship)
	ship.health = 0
	assert_true(ship.is_queued_for_deletion())
	assert_signal_emit_count(ship, "destroyed", 1)


func test_a_ship_is_destroyed_once() -> void:
	var ship := _ship()
	watch_signals(ship)
	ship.health = 0
	ship.health = -10  # Another hit in the same frame.
	assert_signal_emit_count(ship, "destroyed", 1, "a second destroyed would respawn its crew twice")


func test_a_client_never_destroys_a_ship() -> void:
	var ship := _ship()
	var client := SceneMultiplayer.new()
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", 9)  # Never connects: a client all the same.
	client.multiplayer_peer = peer
	get_tree().set_multiplayer(client, ship.get_path())
	watch_signals(ship)
	ship.health = 0  # As the synchronizer sets it.
	get_tree().set_multiplayer(null, ship.get_path())
	peer.close()
	assert_false(ship.is_queued_for_deletion(), "left for the server's despawn")
	assert_signal_not_emitted(ship, "destroyed")
