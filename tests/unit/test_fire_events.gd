extends GutTest
## Weapons netcode, slice W3: the server tells clients that know a ship when
## its guns fire (a fire event); each client flies the shot itself. The
## shooter's own client has already fired it (predicted), on its own timeline.

const SystemScene := preload("res://systems/system_template.tscn")

var system: System
var _peer: ENetMultiplayerPeer


func before_each() -> void:
	system = SystemScene.instantiate()
	add_child_autofree(system)


func after_each() -> void:
	if _peer:
		get_tree().set_multiplayer(null, system.get_path())
		_peer.close()
		_peer = null


func _starfury() -> Ship:
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(ship)
	return ship


func _as_client() -> void:
	var client := SceneMultiplayer.new()
	_peer = ENetMultiplayerPeer.new()
	_peer.create_client("127.0.0.1", 9)  # Never connects: a client all the same.
	client.multiplayer_peer = _peer
	get_tree().set_multiplayer(client, system.get_path())


func test_a_fire_event_survives_the_wire() -> void:
	var shot := Shot.new(Vector3(-80000.125, 3.5, 1.0e9), Vector3(10, -2000.5, 3), 4321, 20.0)
	var back: Dictionary = ShotField.decode_fire(ShotField.encode_fire(2, shot))
	assert_eq(back.gun, 2)
	assert_eq(back.tick, 4321)
	assert_eq(back.origin, shot.origin, "positions stay doubles")
	assert_almost_eq(back.velocity, shot.velocity, Vector3.ONE * 0.001)


func test_anything_else_is_not_a_fire_event() -> void:
	assert_null(ShotField.decode_fire("pew"))
	assert_null(ShotField.decode_fire(PackedByteArray([1, 2, 3])))
	var bytes := ShotField.encode_fire(0, Shot.new(Vector3.ZERO, Vector3.ZERO, 1, 1.0))
	bytes.encode_double(5, INF)
	assert_null(ShotField.decode_fire(bytes), "not finite")


func test_a_client_flies_a_shot_it_is_told_about() -> void:
	var ship := _starfury()
	_as_client()
	var shot := Shot.new(Vector3(5, 0, 0), Vector3(0, 0, -900), 77, 20.0)
	ship._shot_fired(ShotField.encode_fire(1, shot))
	assert_eq(system.shots.count(), 1)
	var told: Shot = system.shots.all()[0]
	assert_eq(told.fire_tick, 77)
	assert_eq(told.shooter, ship)
	assert_false(told.predicted, "drawn with the ship that fired it, in the past")
	assert_eq(told.damage, (ship.get_node("Guns").get_child(1) as Gun).damage)


func test_a_fire_event_for_a_gun_that_does_not_exist_is_ignored() -> void:
	var ship := _starfury()
	_as_client()
	ship._shot_fired(ShotField.encode_fire(200, Shot.new(Vector3.ZERO, Vector3.ZERO, 1, 1.0)))
	assert_eq(system.shots.count(), 0)


func test_the_shooters_client_fires_its_own_shot_at_once() -> void:
	var ship := _starfury()
	ship.prediction_forced = true  # Our player flies it.
	(ship.get_node("Guns").get_child(0) as Gun).fire_at(10)
	assert_eq(system.shots.count(), 1)
	assert_true(system.shots.all()[0].predicted, "drawn on this client's own timeline, with its ship")


func test_a_client_does_not_fire_guns_it_only_watches() -> void:
	var ship := _starfury()
	_as_client()
	(ship.get_node("Guns").get_child(0) as Gun).fire_at(10)  # An NPC's synced trigger, say.
	assert_eq(system.shots.count(), 0, "the server's fire event brings that shot")


func test_a_predicted_shot_is_drawn_at_this_machines_tick() -> void:
	var predicted := Shot.new(Vector3.ZERO, Vector3.ZERO, 1, 1.0)
	predicted.predicted = true
	var bolt := Bolt.new()
	add_child_autofree(bolt)
	bolt.shot = predicted
	assert_eq(bolt.drawn_tick(), NetworkTime.tick + NetworkTime.tick_factor)


func test_a_told_shot_has_its_guns_bolt_size() -> void:
	var ship := _starfury()
	_as_client()
	var gun := ship.get_node("Guns").get_child(1) as Gun
	ship._shot_fired(ShotField.encode_fire(1, Shot.new(Vector3.ZERO, Vector3(0, 0, -900), 5, 1.0)))
	var told: Shot = system.shots.all()[0]
	assert_eq(told.radius, gun.bolt_radius)
	assert_eq(told.growth, gun.growth)
