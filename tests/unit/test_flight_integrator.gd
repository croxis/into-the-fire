extends GutTest
## FlightIntegrator: ship motion maths without nodes. Thrust and torque go in,
## velocity and position come out, the same way Jolt would compute them.

const DT := 1.0 / 60.0


## A 1000 kg body with inertia 2000, 4000, 8000 kg·m² about its own x, y, z.
func _integrator() -> FlightIntegrator:
	var f := FlightIntegrator.new()
	f.inverse_mass = 1.0 / 1000.0
	f.inverse_inertia = Basis.from_scale(Vector3(1.0 / 2000.0, 1.0 / 4000.0, 1.0 / 8000.0))
	f.max_linear_velocity = 500.0
	f.max_angular_velocity = 47.0
	return f


func _state(velocity := Vector3.ZERO, spin := Vector3.ZERO, at := Transform3D.IDENTITY) -> FlightIntegrator.FlightState:
	var s := FlightIntegrator.FlightState.new()
	s.transform = at
	s.linear_velocity = velocity
	s.angular_velocity = spin
	return s


func test_coasting_keeps_velocity_and_moves() -> void:
	var s := _integrator().step(_state(Vector3(10, 0, 0)), Vector3.ZERO, Vector3.ZERO, DT)
	assert_eq(s.linear_velocity, Vector3(10, 0, 0))
	assert_almost_eq(s.transform.origin, Vector3(10 * DT, 0, 0), Vector3.ONE * 1e-9)


func test_thrust_accelerates_then_moves_at_the_new_speed() -> void:
	# Semi-implicit Euler, like Jolt: velocity first, then position with it.
	var s := _integrator().step(_state(), Vector3(0, 0, -1000), Vector3.ZERO, DT)
	assert_almost_eq(s.linear_velocity, Vector3(0, 0, -DT), Vector3.ONE * 1e-9)
	assert_almost_eq(s.transform.origin, Vector3(0, 0, -DT * DT), Vector3.ONE * 1e-12)


func test_torque_spins_up_through_the_inertia() -> void:
	var s := _integrator().step(_state(), Vector3.ZERO, Vector3(0, 0, 8000), DT)
	assert_almost_eq(s.angular_velocity, Vector3(0, 0, DT), Vector3.ONE * 1e-9)


func test_inertia_turns_with_the_ship() -> void:
	# Yawed 90°, the ship's own z axis points along world x, so a world-x torque
	# meets the 8000 kg·m² axis, not the 2000 one.
	var yawed := Transform3D(Basis(Vector3.UP, PI / 2), Vector3.ZERO)
	var s := _integrator().step(_state(Vector3.ZERO, Vector3.ZERO, yawed), Vector3.ZERO, Vector3(8000, 0, 0), DT)
	assert_almost_eq(s.angular_velocity, Vector3(DT, 0, 0), Vector3.ONE * 1e-9)


func test_spin_turns_the_ship() -> void:
	var spin := Vector3(0, PI, 0)  # Half a turn per second about world up.
	var s := _integrator().step(_state(Vector3.ZERO, spin), Vector3.ZERO, Vector3.ZERO, 0.5)
	assert_almost_eq(s.transform.basis.z, Vector3(1, 0, 0), Vector3.ONE * 1e-6, "a quarter turn")
	assert_almost_eq(s.transform.basis.determinant(), 1.0, 1e-9, "still a rotation")


func test_speed_and_spin_are_capped_like_jolt() -> void:
	var f := _integrator()
	var s := f.step(_state(Vector3(0, 0, -499), Vector3(0, 46.9, 0)),
			Vector3(0, 0, -1e9), Vector3(0, 1e9, 0), DT)
	assert_almost_eq(s.linear_velocity.length(), 500.0, 1e-6)
	assert_almost_eq(s.angular_velocity.length(), 47.0, 1e-6)


func test_spin_turns_about_the_centre_of_mass() -> void:
	# The centre of mass sits 10 m ahead of the ship's origin, so turning in place
	# about it swings the origin round.
	var f := _integrator()
	f.center_of_mass_local = Vector3(0, 0, -10)
	var s := f.step(_state(Vector3.ZERO, Vector3(0, PI, 0)), Vector3.ZERO, Vector3.ZERO, 1.0)
	assert_almost_eq(s.transform.origin, Vector3(0, 0, -20), Vector3.ONE * 1e-6)


func test_step_velocity_leaves_the_position_alone() -> void:
	# Ships only need new velocities; Jolt moves them (and handles contacts).
	var s := _integrator().step_velocity(_state(Vector3(1, 0, 0)), Vector3(1000, 0, 0), Vector3.ZERO, DT)
	assert_eq(s.transform, Transform3D.IDENTITY)
	assert_almost_eq(s.linear_velocity, Vector3(1 + DT, 0, 0), Vector3.ONE * 1e-9)


func test_step_does_not_change_its_input() -> void:
	var before := _state(Vector3(5, 0, 0))
	_integrator().step(before, Vector3(1000, 0, 0), Vector3.ZERO, DT)
	assert_eq(before.linear_velocity, Vector3(5, 0, 0), "replays reuse saved states")


# Against Jolt itself: two identical bodies, one pushed with apply_force and
# integrated by Jolt, one flown by the integrator with custom_integrator on.

const TICKS := 60
const FORCE := Vector3(200, -50, -3000)  ## World space, every tick.
const PUSH_POINT := Vector3(1.5, 0.5, 4)  ## In the body's frame. Off-centre, so it turns too.


func _body() -> RigidBody3D:
	var zone := SubViewport.new()
	zone.own_world_3d = true
	add_child_autofree(zone)
	var body := RigidBody3D.new()
	body.mass = 1000.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 2, 12)  # Uneven, so the inertia differs per axis.
	shape.shape = box
	body.add_child(shape)
	zone.add_child(body)
	return body


## Pushes both bodies every physics tick, before the step (like a ship's thrusters).
class Pusher extends Node:
	var by_jolt: RigidBody3D
	var by_us: RigidBody3D
	var flight: FlightIntegrator
	var ticks := 0

	## What apply_force(FORCE, basis * PUSH_POINT) turns into about the centre of mass.
	static func torque(f: FlightIntegrator, basis: Basis) -> Vector3:
		return (basis * PUSH_POINT - basis * f.center_of_mass_local).cross(FORCE)

	func _physics_process(dt: float) -> void:
		ticks += 1
		by_jolt.apply_force(FORCE, by_jolt.global_basis * PUSH_POINT)
		var now := FlightIntegrator.FlightState.new()
		now.transform = by_us.global_transform
		now.linear_velocity = by_us.linear_velocity
		now.angular_velocity = by_us.angular_velocity
		var next := flight.step_velocity(now, FORCE, torque(flight, now.transform.basis), dt)
		by_us.linear_velocity = next.linear_velocity
		by_us.angular_velocity = next.angular_velocity


func test_flies_like_jolt() -> void:
	var by_jolt := _body()
	var by_us := _body()
	by_us.custom_integrator = true
	await wait_physics_frames(1)  # Let Jolt work out mass and inertia.
	var flight := FlightIntegrator.from_body(PhysicsServer3D.body_get_direct_state(by_us.get_rid()))
	var dt := 1.0 / Engine.physics_ticks_per_second

	var pusher := Pusher.new()
	pusher.by_jolt = by_jolt
	pusher.by_us = by_us
	pusher.flight = flight
	add_child(pusher)
	await wait_physics_frames(TICKS)
	var pushes := pusher.ticks
	pusher.free()

	assert_gt(by_jolt.angular_velocity.length(), 0.01, "the test push really turns the body")
	assert_almost_eq(by_us.global_position, by_jolt.global_position, Vector3.ONE * 1e-3, "same place")
	assert_almost_eq(by_us.global_basis.z, by_jolt.global_basis.z, Vector3.ONE * 1e-4, "same heading")
	assert_almost_eq(by_us.linear_velocity, by_jolt.linear_velocity, Vector3.ONE * 1e-3)
	assert_almost_eq(by_us.angular_velocity, by_jolt.angular_velocity, Vector3.ONE * 1e-4)

	# Prediction: replay the same ticks with no physics at all.
	var replay := FlightIntegrator.FlightState.new()
	for _i in pushes:
		replay = flight.step(replay, FORCE, Pusher.torque(flight, replay.transform.basis), dt)
	assert_almost_eq(replay.transform.origin, by_jolt.global_position, Vector3.ONE * 1e-3, "replay lands there too")
	assert_almost_eq(replay.transform.basis.z, by_jolt.global_basis.z, Vector3.ONE * 1e-4)


func test_a_turn_keeps_the_ships_scale() -> void:
	# A scaled ship stays scaled as it turns, as Jolt keeps it; otherwise a
	# replay and the live flight would disagree (thrust uses the basis).
	var f := _integrator()
	var scaled := Transform3D(Basis.from_scale(Vector3.ONE * 0.81), Vector3.ZERO)
	var s := f.step(_state(Vector3.ZERO, Vector3(0, 1, 0), scaled), Vector3.ZERO, Vector3.ZERO, DT)
	assert_almost_eq(s.transform.basis.get_scale(), Vector3.ONE * 0.81, Vector3.ONE * 1e-9)
	assert_almost_eq(s.transform.basis.get_rotation_quaternion().get_angle(), 1.0 * DT, 1e-9)
