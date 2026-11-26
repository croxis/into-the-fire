extends GutTest
## ShipPrediction: the pilot's client flies its own ship at once, and when the
## server's state for an earlier tick arrives, starts again from it and replays
## its own input since (netcode slices N3b/N3c), working thrust out again from
## the replayed state, as the server did.

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


## The thrust for a recorded input [force, torque] (ship frame), in world space.
func _thrust(input: Variant, s: FlightIntegrator.FlightState) -> Array[Vector3]:
	return [s.transform.basis * input[0], s.transform.basis * input[1]]


func _replay(server: FlightIntegrator.FlightState, ack: int, last: int) -> FlightIntegrator.FlightState:
	return prediction.reconcile(server, ack, last, flight, DT, _thrust)


## Flies ticks [first, last] locally from [param start], recording input.
func _fly(start: FlightIntegrator.FlightState, first: int, last: int) -> FlightIntegrator.FlightState:
	var s := start
	for tick in range(first, last + 1):
		prediction.record(tick, [PUSH, TWIST])
		var push := _thrust([PUSH, TWIST], s)
		s = flight.step(s, push[0], push[1], DT)
	return s


func test_a_correct_prediction_needs_no_correction() -> void:
	# The server agrees with us up to tick 5; replaying 6..10 lands where we are.
	var start := FlightIntegrator.FlightState.new()
	var at_5 := _fly(start, 1, 5)
	var at_10 := _fly(at_5, 6, 10)
	var replayed := _replay(at_5, 5, 10)
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
	var replayed := _replay(server, 5, 10)
	assert_almost_eq(replayed.transform.origin, at_10.transform.origin + Vector3(3, 0, 0), Vector3.ONE * 1e-6)


func test_confirmed_thrust_is_forgotten() -> void:
	_fly(FlightIntegrator.FlightState.new(), 1, 10)
	_replay(FlightIntegrator.FlightState.new(), 5, 10)
	assert_eq(prediction.oldest_tick(), 6, "ticks up to the server's ack are dropped")


func test_a_missing_tick_replays_as_coasting() -> void:
	# A tick with no record (say the ship was frozen) adds no thrust.
	var server := FlightIntegrator.FlightState.new()
	server.linear_velocity = Vector3(0, 0, -10)
	var replayed := _replay(server, 0, 3)
	assert_almost_eq(replayed.transform.origin, Vector3(0, 0, -10 * 3 * DT), Vector3.ONE * 1e-9)


func test_an_old_ack_is_ignored() -> void:
	# Unreliable, ordered packets can still arrive after a newer one was used.
	_fly(FlightIntegrator.FlightState.new(), 1, 10)
	_replay(FlightIntegrator.FlightState.new(), 7, 10)
	assert_null(_replay(FlightIntegrator.FlightState.new(), 6, 10))


func test_thrust_that_depends_on_the_state_is_worked_out_again() -> void:
	# Flight assist: thrust that damps the spin, so it depends on the spin now.
	# The server's ship spun differently (knocked); replaying the client's
	# recorded thrust would be wrong, so the replay works it out again.
	var damp := func(_input: Variant, s: FlightIntegrator.FlightState) -> Array[Vector3]:
		return [Vector3.ZERO, -s.angular_velocity * 2000.0]
	var server := FlightIntegrator.FlightState.new()
	server.angular_velocity = Vector3(0, 0.5, 0)
	var truth := server
	for tick in range(1, 6):
		prediction.record(tick, null)
		var push: Array[Vector3] = damp.call(null, truth)
		truth = flight.step(truth, push[0], push[1], DT)
	var replayed := prediction.reconcile(server, 0, 5, flight, DT, damp)
	assert_almost_eq(replayed.angular_velocity, truth.angular_velocity, Vector3.ONE * 1e-12)


func test_history_is_bounded() -> void:
	# If the server stops answering, history must not grow forever.
	_fly(FlightIntegrator.FlightState.new(), 1, ShipPrediction.MAX_HISTORY + 50)
	assert_eq(prediction.size(), ShipPrediction.MAX_HISTORY)


# Snapshots: every other ship's state, tick-stamped (netcode slice N4b). ------

func _starfury() -> Ship:
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	add_child_autofree(ship)
	return ship


func _snapshot(origin: Vector3, velocity := Vector3.ZERO) -> FlightIntegrator.FlightState:
	var s := FlightIntegrator.FlightState.new()
	s.transform = Transform3D(Basis(Vector3.UP, 0.3), origin)
	s.linear_velocity = velocity
	s.angular_velocity = Vector3(0, 0.1, 0)
	return s


func test_a_snapshot_is_kept_and_sets_the_clock() -> void:
	var ship := _starfury()
	ship.snapshots.take(5, _snapshot(Vector3(1, 2, 3), Vector3(0, 0, -5)), 2.0)
	assert_eq(ship.snapshots.buffer.size(), 1)
	assert_almost_eq(ship.snapshots.clock.server_tick(2.0), 5.0, 1e-9, "server tick 5 arrived at our tick 2")
	assert_eq(ship.global_position, Vector3.ZERO, "drawn later, not moved on arrival")


func test_a_remote_ship_is_drawn_between_snapshots() -> void:
	# N4c: other ships are drawn a little in the past, between two snapshots,
	# not flown here: kinematic, so Jolt neither moves nor pushes them.
	var ship := _starfury()
	ship.snapshots.take(10, _snapshot(Vector3(0, 0, 0), Vector3(60, 0, 0)), 0.0)
	ship.snapshots.take(12, _snapshot(Vector3(2, 0, 0), Vector3(60, 0, 0)), 2.0)
	ship.snapshots.show(11.0)
	assert_almost_eq(ship.global_position, Vector3(1, 0, 0), Vector3.ONE * 1e-6)
	assert_true(ship.freeze)
	assert_eq(ship.freeze_mode, RigidBody3D.FREEZE_MODE_KINEMATIC, "still something to collide with")
	assert_eq(ship.linear_velocity, Vector3.ZERO, "on a kinematic body it would be a surface velocity")


func test_jolt_moves_a_drawn_ship_to_where_it_is_drawn() -> void:
	# A kinematic body's new transform is where Jolt moves it in the next step
	# (with the velocity that takes, so contacts see it moving), not a jump.
	var ship := _predicted_starfury_in_a_zone()
	ship.prediction_forced = false
	ship.snapshots.take(2, _state_at(Vector3(3, 0, 0)), 0.0)
	ship.snapshots.show(2.0)
	await Ticks.run(1)
	var in_jolt: Transform3D = PhysicsServer3D.body_get_state(ship.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	assert_almost_eq(in_jolt.origin, Vector3(3, 0, 0), Vector3.ONE * 1e-6)
	assert_almost_eq(ship.global_position, Vector3(3, 0, 0), Vector3.ONE * 1e-6)


func test_drawing_uses_the_clock() -> void:
	var ship := _starfury()
	ship.snapshots.take(20, _snapshot(Vector3(0, 0, 0), Vector3(60, 0, 0)), 0.0)
	ship.snapshots.take(30, _snapshot(Vector3(10, 0, 0), Vector3(60, 0, 0)), 10.0)
	ship.snapshots.drawing_forced = true  # As on a client.
	ship.snapshots.draw(10.0)  # Server tick 30 here, drawn DELAY_TICKS behind it.
	var drawn := 30.0 - SnapshotClock.DELAY_TICKS
	assert_almost_eq(ship.global_position.x, drawn - 20.0, 0.05)


func test_a_drawn_ship_we_start_piloting_is_released_by_its_first_state() -> void:
	var ship := _predicted_starfury_in_a_zone()
	ship.prediction_forced = false
	ship.snapshots.take(2, _state_at(Vector3(3, 0, 0)), 0.0)
	ship.snapshots.show(2.0)
	assert_true(ship.freeze)
	ship.prediction_forced = true  # Our player sat at the helm.
	await Ticks.run(5)
	ship.reconcile_with(_state_at(Vector3(3, 0, 0), Vector3(0, 0, -30)), 4, 4, false)
	assert_false(ship.freeze)
	await Ticks.run(1, 5)
	assert_lt(ship.global_position.z, 0.0, "flies")


func test_snapshots_are_ignored_for_the_ship_we_predict() -> void:
	var ship := _starfury()
	ship.prediction_forced = true  # As on the pilot's own client: it gets its own state.
	ship.snapshots.take(5, _snapshot(Vector3(1, 2, 3), Vector3(0, 0, -5)), 2.0)
	assert_eq(ship.global_position, Vector3.ZERO)
	assert_eq(ship.linear_velocity, Vector3.ZERO)
	assert_eq(ship.snapshots.buffer.size(), 0)


func test_snapshots_are_not_ordered_by_enet() -> void:
	# "unreliable_ordered" drops any packet overtaken by a later one on its
	# channel, which all ships' snapshots share: under jitter that lost half of
	# them. SnapshotBuffer orders them itself.
	var ship := _starfury()
	var config: Dictionary = (ship.get_script() as Script).get_rpc_config()[&"_receive_snapshot"]
	assert_eq(config["transfer_mode"], MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)


func test_snapshots_go_out_every_other_tick() -> void:
	# 30 a second at 60 Hz. Loops can run two ticks at once, so it counts ticks
	# since the last snapshot rather than looking at even ticks.
	var ship := _starfury()
	assert_true(ship.snapshots.is_due(10), "the first")
	ship.snapshots.last_sent_tick = 10
	assert_false(ship.snapshots.is_due(11))
	assert_true(ship.snapshots.is_due(12))
	assert_true(ship.snapshots.is_due(15), "after a skipped loop too")


func test_snapshots_go_only_to_peers_that_have_the_ship() -> void:
	# A joining client gets ships after it connects; a snapshot sent before the
	# ship exists there is an error ("node not found"). Each client asks for a
	# ship's snapshots once it has the ship. The pilot predicting it gets its own
	# state instead, and peers that left are forgotten.
	var ship := _starfury()
	assert_eq(ship.snapshots.recipients([7, 8, 9], 0), [] as Array[int], "nobody asked yet")
	ship.interest.confirm(7)
	ship.interest.confirm(8)
	ship.interest.confirm(9)
	assert_eq(ship.snapshots.recipients([7, 8, 9], 8), [7, 9] as Array[int], "not the pilot")
	assert_eq(ship.snapshots.recipients([9], 0), [9] as Array[int], "7 and 8 left")
	assert_eq(ship.snapshots.recipients([7, 8, 9], 0), [9] as Array[int], "and are forgotten")


func test_snapshots_go_only_to_peers_told_about_the_ship() -> void:
	# Interest management (N5): a client that isn't told about a ship gets none
	# of its snapshots.
	var ship := _starfury()
	ship.interest.confirm(7)
	ship.interest.confirm(9)
	var knows := func(peer: int) -> bool: return peer == 9
	assert_eq(ship.snapshots.recipients([7, 9], 0, knows), [9] as Array[int])


func test_motion_is_synchronised_only_when_a_ship_appears() -> void:
	# Snapshots carry motion from then on. Position and velocity still come with
	# the spawn, so a new ship is in the right place before its first snapshot.
	var config: SceneReplicationConfig = _starfury().get_node("MultiplayerSynchronizer").replication_config
	for prop in ["transform", "linear_velocity", "angular_velocity"]:
		var path := NodePath(".:" + prop)
		assert_true(config.has_property(path), prop)
		if config.has_property(path):
			assert_true(config.property_get_spawn(path), prop + " at spawn")
			assert_eq(config.property_get_replication_mode(path), SceneReplicationConfig.REPLICATION_MODE_NEVER,
					prop + " not after")
	for prop in ["sync_position", "sync_rotation", "sync_linear_velocity", "sync_angular_velocity"]:
		assert_false(config.has_property(NodePath(".:" + prop)), prop + " is gone")


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
	var replayed := ship.prediction.reconcile(start, 29, 44, ship.flight, Ticks.DT, ship._replay_thrust)
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
	# Autospin works out thrust from the current spin. Replaying the thrust the
	# client worked out from its own (wrong) spin gave about a round trip of
	# small corrections after a knock; the replay works it out again instead.
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


func test_the_pilots_client_steers_its_lead_from_the_servers_queue() -> void:
	# Time dilation: each state says how many of our inputs the server has
	# queued, and its cushion; a short queue means run further ahead.
	var ship := _predicted_starfury_in_a_zone()
	var lead := InputLead.new(1.0 / 60.0)
	ship.input_lead_override = lead
	await Ticks.run(3)
	for i in 30:
		ship._receive_state(2, Transform3D(), Vector3.ZERO, Vector3.ZERO, false, 0, 4)
	assert_gt(lead.lead_seconds, 0.0)
	assert_eq(NetworkTime.lead_seconds, lead.lead_seconds, "netfox runs that far ahead")
	NetworkTime.lead_seconds = 0.0


func test_thrust_is_recorded_while_frozen() -> void:
	# So the replay after release includes what the pilot did as the arm let
	# go, which the server applied as soon as its ship was free.
	var ship := _predicted_starfury_in_a_zone()
	ship.freeze = true
	(ship.get_node("Consoles/Cockpit") as Console).get_capability(HelmCapability).throttle = Vector3(0, 0, -1)
	await Ticks.run(3)
	assert_eq(ship.prediction.size(), 3)
	assert_eq(ship.global_position, Vector3.ZERO, "but it doesn't fly")
