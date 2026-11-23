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
