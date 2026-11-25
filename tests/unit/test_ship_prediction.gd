extends GutTest
## ShipPrediction: the pilot's client flies its own ship at once, and when the
## server's state for an earlier tick arrives, starts again from it and replays
## its own thrust since (netcode slices N3b/N3c).

const DT := 1.0 / 60.0
## Forward thrust and a little yaw, in the ship's own frame.
const PUSH := Vector3(0, 0, -2000)
const TWIST := Vector3(0, 300, 0)

var flight: FlightIntegrator
var prediction: ShipPrediction


func before_each() -> void:
	flight = FlightIntegrator.new()
	flight.inverse_mass = 1.0 / 1000.0
	flight.inverse_inertia = Basis.from_scale(Vector3(1.0 / 2000.0, 1.0 / 4000.0, 1.0 / 8000.0))
	prediction = ShipPrediction.new()


## Flies ticks [first, last] locally from [param start], recording thrust.
func _fly(start: FlightIntegrator.FlightState, first: int, last: int) -> FlightIntegrator.FlightState:
	var s := start
	for tick in range(first, last + 1):
		prediction.record(tick, PUSH, TWIST)
		var basis := s.transform.basis
		s = flight.step(s, basis * PUSH, basis * TWIST, DT)
	return s


func test_a_correct_prediction_needs_no_correction() -> void:
	# The server agrees with us up to tick 5; replaying 6..10 lands where we are.
	var start := FlightIntegrator.FlightState.new()
	var at_5 := _fly(start, 1, 5)
	var at_10 := _fly(at_5, 6, 10)
	var replayed := prediction.reconcile(at_5, 5, 10, flight, DT)
	assert_almost_eq(replayed.transform.origin, at_10.transform.origin, Vector3.ONE * 1e-9)
	assert_almost_eq(replayed.transform.basis.z, at_10.transform.basis.z, Vector3.ONE * 1e-9)
	assert_almost_eq(replayed.linear_velocity, at_10.linear_velocity, Vector3.ONE * 1e-9)


func test_a_server_correction_is_carried_forward() -> void:
	# The server says we were 3 m further right at tick 5 (we hit something).
	var start := FlightIntegrator.FlightState.new()
	var at_5 := _fly(start, 1, 5)
	var at_10 := _fly(at_5, 6, 10)
	var server := at_5.duplicate()
	server.transform.origin += Vector3(3, 0, 0)
	var replayed := prediction.reconcile(server, 5, 10, flight, DT)
	assert_almost_eq(replayed.transform.origin, at_10.transform.origin + Vector3(3, 0, 0), Vector3.ONE * 1e-6)


func test_confirmed_thrust_is_forgotten() -> void:
	_fly(FlightIntegrator.FlightState.new(), 1, 10)
	prediction.reconcile(FlightIntegrator.FlightState.new(), 5, 10, flight, DT)
	assert_eq(prediction.oldest_tick(), 6, "ticks up to the server's ack are dropped")


func test_a_missing_tick_replays_as_coasting() -> void:
	# A tick with no record (say the ship was frozen) adds no thrust.
	var server := FlightIntegrator.FlightState.new()
	server.linear_velocity = Vector3(0, 0, -10)
	var replayed := prediction.reconcile(server, 0, 3, flight, DT)
	assert_almost_eq(replayed.transform.origin, Vector3(0, 0, -10 * 3 * DT), Vector3.ONE * 1e-9)


func test_an_old_ack_is_ignored() -> void:
	# Unreliable, ordered packets can still arrive after a newer one was used.
	_fly(FlightIntegrator.FlightState.new(), 1, 10)
	prediction.reconcile(FlightIntegrator.FlightState.new(), 7, 10, flight, DT)
	assert_null(prediction.reconcile(FlightIntegrator.FlightState.new(), 6, 10, flight, DT))


func test_history_is_bounded() -> void:
	# If the server stops answering, history must not grow forever.
	_fly(FlightIntegrator.FlightState.new(), 1, ShipPrediction.MAX_HISTORY + 50)
	assert_eq(prediction.size(), ShipPrediction.MAX_HISTORY)


# The ship's shared sync must not drag a predicted ship back. -----------------

func _starfury() -> Ship:
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	add_child_autofree(ship)
	return ship


func test_synced_motion_moves_ships_nobody_here_predicts() -> void:
	var ship := _starfury()
	ship.sync_position = Vector3(1, 2, 3)
	ship.sync_linear_velocity = Vector3(0, 0, -5)
	assert_eq(ship.position, Vector3(1, 2, 3))
	assert_eq(ship.linear_velocity, Vector3(0, 0, -5))


func test_synced_motion_is_ignored_for_the_ship_we_predict() -> void:
	var ship := _starfury()
	ship.prediction_forced = true  # As on the pilot's own client.
	ship.sync_position = Vector3(1, 2, 3)
	ship.sync_rotation = Vector3(0, 1, 0)
	ship.sync_linear_velocity = Vector3(0, 0, -5)
	ship.sync_angular_velocity = Vector3(0, 1, 0)
	assert_eq(ship.position, Vector3.ZERO)
	assert_eq(ship.rotation, Vector3.ZERO)
	assert_eq(ship.linear_velocity, Vector3.ZERO)
	assert_eq(ship.angular_velocity, Vector3.ZERO)


func test_the_ship_syncs_motion_through_the_proxies() -> void:
	var config: SceneReplicationConfig = _starfury().get_node("MultiplayerSynchronizer").replication_config
	for prop in ["sync_position", "sync_rotation", "sync_linear_velocity", "sync_angular_velocity"]:
		assert_true(config.has_property(NodePath(".:" + prop)), prop)
	for prop in ["position", "rotation", "linear_velocity", "angular_velocity"]:
		assert_false(config.has_property(NodePath(".:" + prop)), prop + " directly")


# Who flies the ship from where. ---------------------------------------------

func _seated(ship: Ship, peer: int, player_id: int) -> Character:
	var c: Character = ship.get_node("CrewMultiplayerSpawner").spawn(
			Character.pilot_data("Pilot %d" % peer, 0, peer, player_id))  # NPC data: no RPCs.
	(ship.get_node("Consoles/Cockpit") as Console).occupy(c)
	c._player_pilot_id = player_id
	return c


func test_a_player_on_another_machine_is_the_remote_pilot() -> void:
	var ship := _starfury()
	var pilot := _seated(ship, 99, 5)
	assert_eq(ship.remote_pilot(), pilot, "the server sends them their state")
	assert_null(ship.local_pilot())


func test_the_hosts_own_ship_is_not_predicted() -> void:
	# Offline here, so this machine is the server: its own player is local, but
	# the host has no latency and never predicts.
	var ship := _starfury()
	_seated(ship, multiplayer.get_unique_id(), 5)
	assert_not_null(ship.local_pilot())
	assert_null(ship.remote_pilot())
	assert_false(ship.is_predicted_here())


func test_npcs_are_nobodys_pilot() -> void:
	var ship := _starfury()
	var npc := _seated(ship, 99, 5)
	npc._player_pilot_id = 0
	assert_null(ship.remote_pilot())
	assert_null(ship.local_pilot())


func test_no_state_is_sent_to_a_pilot_who_left() -> void:
	# A disconnected player's character can stay seated on the server; sending
	# to their peer would fail every tick ("unknown peer ID").
	var ship := _starfury()
	var pilot := _seated(ship, 99, 5)  # Peer 99 isn't connected.
	pilot.input_channel.receive([InputChannel.make_record(1, Vector3.ZERO, Vector3.ZERO),
			InputChannel.make_record(2, Vector3.ZERO, Vector3.ZERO)])
	pilot.input_channel.next()
	assert_false(ship._send_pilot_state(), "nothing sent")


# A replay must land where Jolt really flew the ship. -------------------------
# The client flies with Jolt but replays with FlightIntegrator.step; any
# difference is a correction on every state from the server while flying.

const Ticks := preload("res://tests/unit/ticks.gd")
const SystemScene := preload("res://systems/system_template.tscn")


func test_a_replay_lands_where_jolt_flew_the_ship() -> void:
	var stepper := ZoneStepper.new()
	add_child_autofree(stepper)
	var system: System = SystemScene.instantiate()
	add_child_autofree(system)
	stepper.add_zone(system)
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(ship)
	ship.prediction_forced = true  # So it records its thrust, as the pilot's client does.
	var helm: HelmCapability = (ship.get_node("Consoles/Cockpit") as Console).get_capability(HelmCapability)
	helm.throttle = Vector3(0.5, 0, -1)
	helm.input_rotation_throttle = Vector3(0.6, -0.4, 0.3)
	await Ticks.run(30)  # Get it moving and turning.
	var start := FlightIntegrator.FlightState.new()
	start.transform = ship.global_transform
	start.linear_velocity = ship.linear_velocity
	start.angular_velocity = ship.angular_velocity
	await Ticks.run(15, 30)
	var replayed := ship.prediction.reconcile(start, 29, 44, ship.flight, Ticks.DT)
	assert_gt(ship.angular_velocity.length(), 0.5, "it really is turning")
	assert_almost_eq(replayed.transform.origin, ship.global_position, Vector3.ONE * 1e-3, "position")
	assert_almost_eq(replayed.transform.basis.z, ship.global_basis.z, Vector3.ONE * 1e-5, "heading")
	assert_almost_eq(replayed.angular_velocity, ship.angular_velocity, Vector3.ONE * 1e-5, "spin")


# Flight assist (autospin) works out thrust from how fast the ship spins, so a
# replay must work it out again from the replayed spin, as the server does.

## Gives both helms the same input each tick, before the ships fly: some turning,
## then none (so autospin, when on, damps the spin).
class Pilot extends Node:
	var helms: Array[HelmCapability] = []

	func _enter_tree() -> void:
		NetworkTime.before_tick.connect(_steer)

	func _exit_tree() -> void:
		NetworkTime.before_tick.disconnect(_steer)

	func _steer(_dt: float, tick: int) -> void:
		for helm in helms:
			helm.throttle = Vector3(0, 0, -1)
			helm.input_rotation_throttle = Vector3(0.5, -0.3, 0) if tick % 40 < 15 else Vector3.ZERO


## Flies a predicted "client" ship and a "server" ship side by side with the
## same input, the server's state reaching the client [param latency] ticks
## late. The server's ship is knocked once (a collision). Returns the client's
## corrections after the first one the knock causes has had time to arrive.
func _corrections_after_a_knock(autospin: bool, latency := 6) -> int:
	var stepper := ZoneStepper.new()
	add_child_autofree(stepper)
	var ships: Array[Ship] = []
	var pilot := Pilot.new()
	for i in 2:
		var system: System = SystemScene.instantiate()  # One zone each: no collisions.
		add_child_autofree(system)
		stepper.add_zone(system)
		var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
		system.add_ship(ship)
		var helm: HelmCapability = (ship.get_node("Consoles/Cockpit") as Console).get_capability(HelmCapability)
		helm.autospin = autospin
		pilot.helms.append(helm)
		ships.append(ship)
	add_child_autofree(pilot)
	var client := ships[0]
	var server := ships[1]
	client.prediction_forced = true
	var sent: Dictionary[int, FlightIntegrator.FlightState] = {}
	var corrections := 0
	for tick in 160:
		await Ticks.run(1, tick)
		if tick == 30:
			server.angular_velocity += server.global_basis.y * 0.05
		var s := FlightIntegrator.FlightState.new()
		s.transform = server.global_transform
		s.linear_velocity = server.linear_velocity
		s.angular_velocity = server.angular_velocity
		sent[tick] = s
		if tick >= latency:
			client.reconcile_with(sent[tick - latency], tick - latency, tick)
			if tick > 30 + latency + 1 and client.smoother.last_correction > 1e-4:
				corrections += 1
	return corrections


func test_a_correction_moves_the_physics_body_too() -> void:
	# Godot sends a node's new transform to the physics engine only at the start
	# of the next physics frame; our ticks step the zone before that, and the
	# step then writes the old place back. A correction must reach Jolt at once.
	var stepper := ZoneStepper.new()
	add_child_autofree(stepper)
	var system: System = SystemScene.instantiate()
	add_child_autofree(system)
	stepper.add_zone(system)
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(ship)
	ship.prediction_forced = true
	await Ticks.run(5)
	var server := FlightIntegrator.FlightState.new()
	server.transform = ship.global_transform.translated(Vector3(CorrectionSmoother.SNAP_DISTANCE * 2, 0, 0))
	ship.reconcile_with(server, 4, 4)  # Nothing to replay; a big jump, so it snaps.
	await Ticks.run(1, 5)
	assert_almost_eq(ship.global_position.x, CorrectionSmoother.SNAP_DISTANCE * 2, 1.0)


func test_with_autospin_off_a_knock_is_corrected_once() -> void:
	assert_eq(await _corrections_after_a_knock(false), 0)


func test_with_autospin_on_a_knock_is_corrected_once() -> void:
	# Autospin works out thrust from the current spin, but the client records
	# thrust, so after a knock it replays thrust worked out from its own wrong
	# spin: about a round trip of small corrections (8 here). Fix: record input
	# and re-run flight assist in the replay.
	pending("replay records thrust, not input; flight assist needs input replay")
	return
	@warning_ignore("unreachable_code")
	assert_eq(await _corrections_after_a_knock(true), 0)


# Held on a launch arm, the ship is moved by the arm on the server, not by the
# pilot, so the client follows the server's state exactly instead of predicting.

func _predicted_starfury_in_a_zone() -> Ship:
	var stepper := ZoneStepper.new()
	add_child_autofree(stepper)
	var system: System = SystemScene.instantiate()
	add_child_autofree(system)
	stepper.add_zone(system)
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(ship)
	ship.prediction_forced = true
	return ship


func _state_at(origin: Vector3, velocity := Vector3.ZERO) -> FlightIntegrator.FlightState:
	var s := FlightIntegrator.FlightState.new()
	s.transform = Transform3D(Basis(), origin)
	s.linear_velocity = velocity
	return s


func test_a_frozen_ship_goes_exactly_where_the_server_has_it() -> void:
	var ship := _predicted_starfury_in_a_zone()
	await Ticks.run(5)
	ship.reconcile_with(_state_at(Vector3(3, 0, 0)), 2, 4, true)  # No easing, no replay.
	assert_eq(ship.global_position, Vector3(3, 0, 0))
	assert_true(ship.freeze, "frozen here too, so it doesn't fly off between states")
	await Ticks.run(1, 5)
	assert_eq(ship.global_position, Vector3(3, 0, 0))
	assert_eq(ship._corrections, 0, "following the arm isn't a correction")


func test_released_it_is_predicted_again() -> void:
	var ship := _predicted_starfury_in_a_zone()
	await Ticks.run(5)
	ship.reconcile_with(_state_at(Vector3(3, 0, 0)), 2, 4, true)
	ship.reconcile_with(_state_at(Vector3(3, 0, 0), Vector3(0, 0, -30)), 4, 4, false)
	assert_false(ship.freeze)
	await Ticks.run(1, 5)
	assert_lt(ship.global_position.z, 0.0, "flies off the arm")


func test_thrust_is_recorded_while_frozen() -> void:
	# So the replay after release includes what the pilot did as the arm let
	# go, which the server applied as soon as its ship was free.
	var ship := _predicted_starfury_in_a_zone()
	ship.freeze = true
	(ship.get_node("Consoles/Cockpit") as Console).get_capability(HelmCapability).throttle = Vector3(0, 0, -1)
	await Ticks.run(3)
	assert_eq(ship.prediction.size(), 3)
	assert_eq(ship.global_position, Vector3.ZERO, "but it doesn't fly")
