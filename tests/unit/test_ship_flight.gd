extends GutTest
## Ships fly through FlightIntegrator (Jolt only moves them and handles
## contacts), and fly exactly as they did when Jolt integrated thruster forces.

const SystemScene := preload("res://systems/system_template.tscn")
const TICKS := 40
## Forward, a little right, and pitch and yaw: main, lateral and turning
## thrusters all fire, so both force and torque are tested.
const THROTTLE := Vector3(0.5, 0, -1)
const TURN := Vector3(0.6, -0.4, 0)


func _ship(content_id: StringName, at: Vector3) -> Ship:
	var system: System = SystemScene.instantiate()  # One zone each: no collisions.
	add_child_autofree(system)
	var ship: Ship = Content.instantiate(content_id)
	system.add_ship(ship)
	ship.global_position = at
	return ship


func _helm(ship: Ship) -> HelmCapability:
	return (ship.get_node("Consoles/Cockpit") as Console).get_capability(HelmCapability)


## The old way: Jolt integrates, pushed by each thruster with apply_force.
## It ran in Ship._physics_process, before the Helm (a child) set this tick's
## thruster power, so this runs early too.
class OldThrusters extends Node:
	var ship: Ship

	func _init() -> void:
		process_physics_priority = -1

	func _physics_process(_dt: float) -> void:
		for thruster in ship.get_node("Engines").thrusters:
			ship.apply_force(ship.global_transform.basis * thruster.force_vector,
					ship.global_transform.basis * thruster.position)


func test_ships_use_the_integrator_and_stations_do_not() -> void:
	assert_true(_ship(&"b5:aurora_starfury", Vector3.ZERO).custom_integrator)
	assert_true(_ship(&"b5:hyperion", Vector3.ZERO).custom_integrator)
	assert_false(_ship(&"b5:babylon_5", Vector3.ZERO).custom_integrator)


func test_starfury_flies_as_before() -> void:
	var new_way := _ship(&"b5:aurora_starfury", Vector3.ZERO)
	var old_way := _ship(&"b5:aurora_starfury", Vector3.ZERO)
	old_way.custom_integrator = false  # Ship skips its integrator; Jolt takes over again.
	var pusher := OldThrusters.new()
	pusher.ship = old_way
	old_way.add_child(pusher)
	for ship in [new_way, old_way]:
		_helm(ship).throttle = THROTTLE
		_helm(ship).input_rotation_throttle = TURN

	await wait_physics_frames(TICKS)

	assert_gt(old_way.linear_velocity.length(), 0.1, "the thrusters really fired")
	assert_gt(old_way.angular_velocity.length(), 0.01, "and really turned the ship")
	assert_almost_eq(new_way.global_position, old_way.global_position, Vector3.ONE * 1e-3)
	assert_almost_eq(new_way.global_basis.z, old_way.global_basis.z, Vector3.ONE * 1e-4)
	assert_almost_eq(new_way.linear_velocity, old_way.linear_velocity, Vector3.ONE * 1e-3)
	assert_almost_eq(new_way.angular_velocity, old_way.angular_velocity, Vector3.ONE * 1e-4)


func test_frozen_ship_is_left_alone() -> void:
	# Ships held on a launch arm are frozen; the integrator must not push them.
	var ship := _ship(&"b5:aurora_starfury", Vector3.ZERO)
	ship.freeze = true
	_helm(ship).throttle = THROTTLE
	await wait_physics_frames(10)
	assert_eq(ship.global_position, Vector3.ZERO)

