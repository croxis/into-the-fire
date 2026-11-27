extends GutTest
## ZoneStepper: each zone's physics space is stepped by the game, not the engine
## (zone slice 3, using the engine's physics stepping patch), once per netfox
## tick (netcode slice N2).

const Ticks := preload("res://tests/unit/ticks.gd")

var stepper: ZoneStepper
var zone: SubViewport
var body: RigidBody3D


func before_each() -> void:
	zone = SubViewport.new()
	zone.own_world_3d = true
	add_child_autofree(zone)
	body = RigidBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	body.add_child(shape)
	zone.add_child(body)
	body.linear_velocity = Vector3(10, 0, 0)  # No gravity or damping in this project.
	stepper = ZoneStepper.new()
	add_child_autofree(stepper)


func _space(z: SubViewport) -> RID:
	return z.find_world_3d().space


func test_added_zone_is_no_longer_stepped_by_the_engine() -> void:
	assert_true(PhysicsServer3D.space_is_active(_space(zone)))
	stepper.add_zone(zone)
	assert_false(PhysicsServer3D.space_is_active(_space(zone)))


func test_full_zone_moves_once_per_tick() -> void:
	stepper.add_zone(zone)
	await Ticks.run(6)
	assert_almost_eq(body.position.x, 10.0 * 6 * Ticks.DT, 1e-6,
			"six ticks of 10 m/s, and the body node is synced")


func test_physics_frames_alone_do_not_step_a_zone() -> void:
	# The engine's physics frames no longer drive zones; netfox ticks do.
	stepper.add_zone(zone)
	await wait_physics_frames(5)
	assert_eq(body.position, Vector3.ZERO)


func test_paused_zone_stands_still() -> void:
	stepper.add_zone(zone, ZoneStepper.Mode.PAUSED)
	await Ticks.run(5)
	assert_eq(body.position, Vector3.ZERO)
	assert_eq(zone.process_mode, Node.PROCESS_MODE_DISABLED,
			"nodes stop too, so thrusters don't pile up force while paused")


func test_resumed_zone_moves_again() -> void:
	stepper.add_zone(zone, ZoneStepper.Mode.PAUSED)
	await Ticks.run(2)
	stepper.set_mode(zone, ZoneStepper.Mode.FULL)
	assert_eq(zone.process_mode, Node.PROCESS_MODE_INHERIT)
	# Re-enabled bodies rejoin their physics space at the next frame; in the
	# game ticks only run inside physics frames anyway.
	await wait_physics_frames(1)
	await Ticks.run(5)
	assert_gt(body.position.x, 0.0)


func test_removed_zone_goes_back_to_the_engine() -> void:
	stepper.add_zone(zone, ZoneStepper.Mode.PAUSED)
	stepper.remove_zone(zone)
	assert_true(PhysicsServer3D.space_is_active(_space(zone)))
	assert_eq(zone.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_false(stepper.has_zone(zone))


func test_zone_leaving_the_tree_is_dropped() -> void:
	stepper.add_zone(zone)
	remove_child(zone)
	assert_false(stepper.has_zone(zone))
	assert_true(PhysicsServer3D.space_is_active(_space(zone)), "handed back to the engine")
	await Ticks.run(2)  # Must not step a space that is gone.
	zone.free()


func test_galaxy_steps_every_system_it_gets() -> void:
	var galaxy: Galaxy = load("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)
	var system: System = load("res://systems/system_template.tscn").instantiate()
	galaxy.zones.add_system(system)
	assert_true(galaxy.zone_stepper.has_zone(system))
	assert_false(PhysicsServer3D.space_is_active(system.find_world_3d().space))


func test_simulation_runs_at_60_ticks_a_second_in_the_physics_frame() -> void:
	assert_eq(ProjectSettings.get_setting("netfox/time/tickrate"), 60, "today's physics rate")
	assert_true(ProjectSettings.get_setting("netfox/time/sync_to_physics"))
