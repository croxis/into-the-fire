extends GutTest
## SnapshotBuffer: a remote ship's recent tick-stamped states from the server
## (netcode slice N4b), and where the ship was at any moment between them.

const DT := 1.0 / 60.0

var buffer: SnapshotBuffer


func before_each() -> void:
	buffer = SnapshotBuffer.new(DT)


func _at(origin: Vector3, velocity := Vector3.ZERO, turn := 0.0, spin := Vector3.ZERO) -> FlightIntegrator.FlightState:
	var s := FlightIntegrator.FlightState.new()
	s.transform = Transform3D(Basis(Vector3.UP, turn), origin)
	s.linear_velocity = velocity
	s.angular_velocity = spin
	return s


func test_with_one_snapshot_that_is_where_it_is() -> void:
	buffer.push(10, _at(Vector3(1, 2, 3)))
	assert_eq(buffer.sample(10.0).transform.origin, Vector3(1, 2, 3))
	assert_eq(buffer.sample(4.0).transform.origin, Vector3(1, 2, 3), "before the first: the first")


func test_empty_has_nothing_to_show() -> void:
	assert_null(buffer.sample(10.0))
	assert_eq(buffer.newest_tick(), -1)


func test_straight_flight_is_followed_exactly() -> void:
	# 60 m/s along x: 1 m a tick. Halfway between two snapshots is halfway.
	buffer.push(10, _at(Vector3(0, 0, 0), Vector3(60, 0, 0)))
	buffer.push(12, _at(Vector3(2, 0, 0), Vector3(60, 0, 0)))
	assert_almost_eq(buffer.sample(11.0).transform.origin, Vector3(1, 0, 0), Vector3.ONE * 1e-9)
	assert_almost_eq(buffer.sample(11.5).transform.origin, Vector3(1.5, 0, 0), Vector3.ONE * 1e-9)


func test_a_curve_follows_the_velocities_not_a_straight_line() -> void:
	# A quarter circle of radius 1: from (1,0,0) heading +z to (0,0,1) heading -x.
	# A straight line would cut the corner; the curve stays near the circle.
	var ticks := 30
	var speed := (PI / 2.0) / (ticks * DT)
	buffer.push(0, _at(Vector3(1, 0, 0), Vector3(0, 0, speed)))
	buffer.push(ticks, _at(Vector3(0, 0, 1), Vector3(-speed, 0, 0)))
	var mid := buffer.sample(ticks / 2.0).transform.origin
	assert_almost_eq(mid.length(), 1.0, 0.02, "on the circle, near enough")
	assert_gt(mid.length(), Vector3(0.5, 0, 0.5).length() + 0.2, "well outside the straight line")


func test_rotation_turns_smoothly_between_snapshots() -> void:
	buffer.push(10, _at(Vector3.ZERO, Vector3.ZERO, 0.0))
	buffer.push(12, _at(Vector3.ZERO, Vector3.ZERO, 0.4))
	var angle := buffer.sample(11.0).transform.basis.get_rotation_quaternion().get_angle()
	assert_almost_eq(angle, 0.2, 1e-6)


func test_past_the_newest_it_carries_on_briefly() -> void:
	# A late packet: keep moving at the last velocity for a little while, then stop.
	buffer.push(10, _at(Vector3.ZERO, Vector3(60, 0, 0), 0.0, Vector3(0, 6, 0)))
	var later := buffer.sample(13.0)
	assert_almost_eq(later.transform.origin, Vector3(3, 0, 0), Vector3.ONE * 1e-9)
	assert_almost_eq(later.transform.basis.get_rotation_quaternion().get_angle(), 6.0 * 3 * DT, 1e-6)
	var much_later := buffer.sample(10.0 + SnapshotBuffer.MAX_EXTRAPOLATION_TICKS + 100)
	assert_almost_eq(much_later.transform.origin.x, float(SnapshotBuffer.MAX_EXTRAPOLATION_TICKS), 1e-9,
			"no further than the limit")


func test_snapshots_out_of_order_are_put_in_order() -> void:
	# Unreliable packets can arrive late; a late one still fills its gap.
	buffer.push(10, _at(Vector3(0, 0, 0), Vector3(60, 0, 0)))
	buffer.push(14, _at(Vector3(4, 0, 0), Vector3(60, 0, 0)))
	assert_true(buffer.push(12, _at(Vector3(2, 0, 0), Vector3(60, 0, 0))))
	assert_eq(buffer.newest_tick(), 14)
	assert_almost_eq(buffer.sample(12.0).transform.origin, Vector3(2, 0, 0), Vector3.ONE * 1e-9)


func test_repeats_and_very_old_snapshots_are_ignored() -> void:
	for tick in SnapshotBuffer.MAX_SNAPSHOTS:
		buffer.push(100 + tick, _at(Vector3(tick, 0, 0)))
	assert_false(buffer.push(105, _at(Vector3(99, 0, 0))), "already have tick 105")
	assert_false(buffer.push(50, _at(Vector3.ZERO)), "older than everything kept")
	assert_eq(buffer.size(), SnapshotBuffer.MAX_SNAPSHOTS)


func test_the_buffer_is_bounded() -> void:
	for tick in SnapshotBuffer.MAX_SNAPSHOTS + 20:
		buffer.push(tick, _at(Vector3.ZERO))
	assert_eq(buffer.size(), SnapshotBuffer.MAX_SNAPSHOTS, "oldest dropped")
	assert_eq(buffer.newest_tick(), SnapshotBuffer.MAX_SNAPSHOTS + 19)
