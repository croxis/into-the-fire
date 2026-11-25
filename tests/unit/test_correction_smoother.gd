extends GutTest
## CorrectionSmoother: when the server corrects the pilot's own ship, the ship
## doesn't jump there at once; it eases over a few ticks (netcode slice N4a).
## The ship's velocity snaps to the truth; only where it's shown lags behind.

var smoother: CorrectionSmoother


func before_each() -> void:
	smoother = CorrectionSmoother.new()


func _at(x: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, 0, 0))


func test_with_nothing_to_correct_the_ship_stays_on_the_truth() -> void:
	var placed := smoother.apply(_at(5), _at(5))
	assert_eq(placed, _at(5))
	assert_eq(smoother.last_correction, 0.0)


func test_a_correction_is_shown_only_partly_at_first() -> void:
	# We showed x=0; the server's truth is x=1.
	var placed := smoother.apply(_at(0), _at(1))
	assert_almost_eq(placed.origin.x, 1.0 - CorrectionSmoother.KEEP, 1e-9)
	assert_almost_eq(smoother.last_correction, 1.0, 1e-9)


func test_the_rest_eases_out_within_about_a_tenth_of_a_second() -> void:
	var shown := smoother.apply(_at(0), _at(1))
	var corrections := 0.0
	for tick in 6:  # The ship moves 2 m a tick; so does the truth, with no new error.
		var truth := _at(1 + 2 * (tick + 1))
		shown = smoother.apply(shown.translated(Vector3(2, 0, 0)), truth)
		corrections += smoother.last_correction
	assert_almost_eq(shown.origin.x, 13.0, 0.15, "nearly on the truth after 6 ticks")
	assert_almost_eq(corrections, 0.0, 1e-9, "easing out isn't counted as new corrections")


func test_a_big_jump_snaps_at_once() -> void:
	# The launch, a teleport: easing kilometres over 100 ms would look worse.
	var far := CorrectionSmoother.SNAP_DISTANCE + 1.0
	assert_eq(smoother.apply(_at(0), _at(far)), _at(far))


func test_rotation_is_the_truth_at_once() -> void:
	# Thrust follows the way the ship points; see the flying test below.
	var truth := Transform3D(Basis(Vector3.UP, 0.1), Vector3(1, 0, 0))
	var placed := smoother.apply(Transform3D(), truth)
	assert_eq(placed.basis, truth.basis)
	assert_ne(placed.origin, truth.origin, "position still eases")


func test_reset_forgets_what_was_left() -> void:
	smoother.apply(_at(0), _at(1))
	smoother.reset()
	assert_eq(smoother.apply(_at(1), _at(1)), _at(1))


# On the ship ---------------------------------------------------------------

func test_the_predicted_ship_eases_to_the_servers_state() -> void:
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	add_child_autofree(ship)
	ship.prediction_forced = true
	ship._receive_state(-1, _at(1), Vector3(0, 0, -5), Vector3.ZERO)
	assert_almost_eq(ship.global_position.x, 1.0 - CorrectionSmoother.KEEP, 1e-6)
	assert_eq(ship.linear_velocity, Vector3(0, 0, -5), "velocity is the truth at once")


func test_an_eased_ship_flies_like_the_truth() -> void:
	# The client flies with thrust and a turn; the server knocks its ship off
	# course once. After easing, the client must fly exactly as the server does,
	# or every tick brings a new small correction. Thrust follows the way the
	# ship points, so the client's rotation must not lag the truth.
	const DT := 1.0 / 60.0
	const PUSH := Vector3(0, 0, -2000)  # Ship frame.
	const TWIST := Vector3(0, 300, 0)
	var flight := FlightIntegrator.new()
	flight.inverse_mass = 1.0 / 1000.0
	flight.inverse_inertia = Basis.from_scale(Vector3(1.0 / 2000.0, 1.0 / 4000.0, 1.0 / 8000.0))
	var client := FlightIntegrator.FlightState.new()
	var server := FlightIntegrator.FlightState.new()
	var late := 0.0
	for tick in 60:
		client = flight.step(client, client.transform.basis * PUSH, client.transform.basis * TWIST, DT)
		server = flight.step(server, server.transform.basis * PUSH, server.transform.basis * TWIST, DT)
		if tick == 10:  # Knocked: 2 m and a few degrees.
			server.transform = Transform3D(server.transform.basis.rotated(Vector3.UP, 0.05),
					server.transform.origin + Vector3(2, 0, 0))
		client.transform = smoother.apply(client.transform, server.transform)  # No latency here.
		client.linear_velocity = server.linear_velocity
		client.angular_velocity = server.angular_velocity
		if tick > 10:
			late = maxf(late, smoother.last_correction)
	assert_almost_eq(late, 0.0, 1e-6, "no new corrections after the knock")
