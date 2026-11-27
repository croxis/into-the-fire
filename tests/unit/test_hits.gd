extends GutTest
## Weapons netcode, slice W5: a hit is the server's. It tells the clients that
## know the shooter (its pilot too), each naming the shot by the tick that
## client knows it by; they drop that shot and show the hit.

const Ticks := preload("res://tests/unit/ticks.gd")
const SystemScene := preload("res://systems/system_template.tscn")

var stepper: ZoneStepper
var system: System
var _peer: ENetMultiplayerPeer


func before_each() -> void:
	stepper = ZoneStepper.new()
	add_child_autofree(stepper)
	system = SystemScene.instantiate()
	add_child_autofree(system)
	stepper.add_zone(system)


func after_each() -> void:
	if _peer:
		get_tree().set_multiplayer(null, system.get_path())
		_peer.close()
		_peer = null


func _starfury(at := Vector3.ZERO) -> Ship:
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(ship)
	ship.place(Transform3D(Basis(), at))
	return ship


func _as_client() -> void:
	var client := SceneMultiplayer.new()
	_peer = ENetMultiplayerPeer.new()
	_peer.create_client("127.0.0.1", 9)  # Never connects: a client all the same.
	client.multiplayer_peer = _peer
	get_tree().set_multiplayer(client, system.get_path())


func test_a_hit_event_survives_the_wire() -> void:
	var back: Dictionary = ShotField.decode_hit(ShotField.encode_hit(3, 4567, Vector3(-80000.5, 2, 1.0e9)))
	assert_eq(back.gun, 3)
	assert_eq(back.tick, 4567)
	assert_eq(back.position, Vector3(-80000.5, 2, 1.0e9))
	assert_null(ShotField.decode_hit(PackedByteArray([1])))
	assert_null(ShotField.decode_hit(null))


func test_a_remote_pilots_shot_remembers_their_input_tick() -> void:
	var ship := _starfury()
	var pilot: Character = ship.get_node("CrewMultiplayerSpawner").spawn(Character.pilot_data("Remote", 0, 99, 1))
	(ship.get_node("Consoles/Cockpit") as Console).occupy(pilot)
	pilot._player_pilot_id = 5
	var fire := func(tick: int) -> Dictionary:
		return InputChannel.make_record(tick, Vector3.ZERO, Vector3.ZERO, false, false, false, true)
	pilot.receive_inputs_from(99, [fire.call(7), fire.call(8)])
	await Ticks.run(1, 30)
	var shot: Shot = system.shots.all()[0]
	assert_eq(shot.fire_tick, 30, "the server's tick")
	assert_eq(shot.client_tick, 7, "and the tick the pilot's client fired its own copy at")
	assert_eq(shot.gun_index, 0)


func test_the_server_reports_a_hit() -> void:
	var shooter := _starfury()
	var gun := shooter.get_node("Guns").get_child(0) as Gun
	var target := _starfury(Vector3(gun.global_position.x, gun.global_position.y, -300))
	gun.speed = 3000.0
	await Ticks.run(1)
	watch_signals(system.shots)
	gun.fire_at(1)
	await Ticks.run(12, 2)
	assert_signal_emitted(system.shots, "hit")
	var args: Array = get_signal_parameters(system.shots, "hit")
	assert_eq(args[1], target)
	assert_lt(absf(args[2].z - -300.0), 15.0, "where it hit, on the target's hull")


func test_a_client_drops_the_shot_that_hit() -> void:
	var ship := _starfury()
	_as_client()
	var mine := Shot.new(Vector3.ZERO, Vector3(0, 0, -900), 40, 20.0, ship)
	mine.gun_index = 1
	var other := Shot.new(Vector3.ZERO, Vector3(0, 0, -900), 41, 20.0, ship)
	other.gun_index = 1
	system.shots.add(mine)
	system.shots.add(other)
	ship._shot_hit(ShotField.encode_hit(1, 40, Vector3(0, 0, -100)))
	assert_eq(system.shots.all(), [other], "only the shot named: gun 1 at tick 40")


func test_test_players_can_hold_the_trigger() -> void:
	var options := LaunchOptions.parse(PackedStringArray(["--testplayer", "--faction=Zeta Wing", "--launch", "--fire"]))
	assert_true(options.fire)
	assert_false("--fire" in options.unknown)


func test_shots_are_counted_for_the_log() -> void:
	assert_eq(system.shots.report(), "", "nothing to say")
	system.shots.add(Shot.new(Vector3.ZERO, Vector3.ZERO, 1, 1.0))
	assert_eq(system.shots.report(), "1 fired, 0 hits")
	assert_eq(system.shots.report(), "", "counted since the last report")


func test_a_struck_event_survives_the_wire() -> void:
	assert_eq(ShotField.decode_struck(ShotField.encode_struck(Vector3(-80000.5, 2, 1.0e9))), Vector3(-80000.5, 2, 1.0e9))
	assert_null(ShotField.decode_struck(PackedByteArray([1, 2])))
	var bytes := ShotField.encode_struck(Vector3.ZERO)
	bytes.encode_double(0, NAN)
	assert_null(ShotField.decode_struck(bytes), "not finite")


func test_clients_that_know_only_the_target_are_told_it_was_struck() -> void:
	# Told through the shooter: 5 and 6. Know the target: 6 and 7.
	assert_eq(ShotField.struck_only([6, 7], [5, 6]), [7])
