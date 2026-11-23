extends GutTest
## Ships fly through FlightIntegrator (Jolt only moves them and handles
## contacts), and fly exactly as they did when Jolt integrated thruster forces.
## They fly on netfox ticks (netcode slice N2): this test runs them by hand.

const Ticks := preload("res://tests/unit/ticks.gd")
const SystemScene := preload("res://systems/system_template.tscn")
const TICKS := 40
## Forward, a little right, and pitch and yaw: main, lateral and turning
## thrusters all fire, so both force and torque are tested.
const THROTTLE := Vector3(0.5, 0, -1)
const TURN := Vector3(0.6, -0.4, 0)

var stepper: ZoneStepper


func before_each() -> void:
	stepper = ZoneStepper.new()
	add_child_autofree(stepper)


func _ship(content_id: StringName, at: Vector3) -> Ship:
	var system: System = SystemScene.instantiate()  # One zone each: no collisions.
	add_child_autofree(system)
	stepper.add_zone(system)
	var ship: Ship = Content.instantiate(content_id)
	system.add_ship(ship)
	ship.global_position = at
	return ship


func _helm(ship: Ship) -> HelmCapability:
	return (ship.get_node("Consoles/Cockpit") as Console).get_capability(HelmCapability)


## The old way: Jolt integrates, pushed by each thruster with apply_force. It
## pushes after the ship's own tick (which sets this tick's thruster power) and
## before the zone steps, as Ship did before the integrator.
class OldThrusters extends RefCounted:
	var ship: Ship

	func push(_dt: float, _tick: int) -> void:
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
	NetworkTime.on_tick.connect(pusher.push)  # After the ships, which connected first.
	for ship in [new_way, old_way]:
		_helm(ship).throttle = THROTTLE
		_helm(ship).input_rotation_throttle = TURN

	await Ticks.run(TICKS)
	NetworkTime.on_tick.disconnect(pusher.push)

	assert_gt(old_way.linear_velocity.length(), 0.1, "the thrusters really fired")
	assert_gt(old_way.angular_velocity.length(), 0.01, "and really turned the ship")
	assert_almost_eq(new_way.global_position, old_way.global_position, Vector3.ONE * 1e-3)
	assert_almost_eq(new_way.global_basis.z, old_way.global_basis.z, Vector3.ONE * 1e-4)
	assert_almost_eq(new_way.linear_velocity, old_way.linear_velocity, Vector3.ONE * 1e-3)
	assert_almost_eq(new_way.angular_velocity, old_way.angular_velocity, Vector3.ONE * 1e-4)


func test_thrust_takes_effect_on_the_same_tick() -> void:
	# The helm sets thruster power before the ship flies, within one tick.
	var ship := _ship(&"b5:aurora_starfury", Vector3.ZERO)
	_helm(ship).throttle = Vector3(0, 0, -1)
	await Ticks.run(1)
	assert_lt((ship.global_basis.inverse() * ship.linear_velocity).z, 0.0, "moving forward after one tick")


func test_physics_frames_alone_do_not_fly_ships() -> void:
	var ship := _ship(&"b5:aurora_starfury", Vector3.ZERO)
	_helm(ship).throttle = THROTTLE
	await wait_physics_frames(5)
	assert_eq(ship.linear_velocity, Vector3.ZERO)
	assert_eq(ship.global_position, Vector3.ZERO)


func test_frozen_ship_is_left_alone() -> void:
	# Ships held on a launch arm are frozen; the integrator must not push them.
	var ship := _ship(&"b5:aurora_starfury", Vector3.ZERO)
	ship.freeze = true
	_helm(ship).throttle = THROTTLE
	await Ticks.run(10)
	assert_eq(ship.global_position, Vector3.ZERO)


func test_ships_can_go_faster_than_jolts_default_cap() -> void:
	# Jolt's default is 500 m/s; the project raises it (project.godot).
	assert_gt(ProjectSettings.get_setting(FlightIntegrator.MAX_LINEAR_SETTING), 5000.0)
	var ship := _ship(&"b5:aurora_starfury", Vector3.ZERO)
	ship.linear_velocity = Vector3(0, 0, -3000)
	await Ticks.run(3)
	assert_almost_eq(ship.linear_velocity.length(), 3000.0, 1.0, "not clamped to 500 m/s")


func test_spin_is_capped_at_1350_degrees_a_second() -> void:
	# Half Jolt's default of 2700°/s (project.godot stores radians).
	var cap := deg_to_rad(1350.0)
	assert_almost_eq(float(ProjectSettings.get_setting(FlightIntegrator.MAX_ANGULAR_SETTING)), cap, 1e-4)
	var ship := _ship(&"b5:aurora_starfury", Vector3.ZERO)
	ship.angular_velocity = Vector3(0, 40, 0)  # About 2300°/s.
	await Ticks.run(3)
	assert_almost_eq(ship.angular_velocity.length(), cap, 1e-3)


func test_pilot_input_moves_the_ship_on_the_same_tick() -> void:
	# before_tick: the character hands its input to the helm; on_tick: the ship
	# flies with it. (Peer 99 isn't this machine, so the input isn't re-read
	# from the keyboard; an NPC, so no camera RPC to a missing peer.)
	var ship := _ship(&"b5:aurora_starfury", Vector3.ZERO)
	var pilot: Character = ship.get_node("CrewMultiplayerSpawner").spawn(
			Character.pilot_data("Pilot", 0, 99, 1))
	(ship.get_node("Consoles/Cockpit") as Console).occupy(pilot)
	pilot.inputs.throttle = Vector3(0, 0, -1)
	await Ticks.run(1)
	assert_eq(_helm(ship).throttle, Vector3(0, 0, -1), "the helm got the input")
	assert_lt((ship.global_basis.inverse() * ship.linear_velocity).z, 0.0, "and the ship moved with it")


# Remote pilots fly from their tick-stamped input (netcode slice N3a).

func _remote_player_at_cockpit(ship: Ship) -> Character:
	# Peer 99 is another machine. Seated through the spawner and occupy() needs
	# no RPC to it here: occupy() only messages players, so set the player id after.
	var pilot: Character = ship.get_node("CrewMultiplayerSpawner").spawn(
			Character.pilot_data("Remote", 0, 99, 1))
	(ship.get_node("Consoles/Cockpit") as Console).occupy(pilot)
	pilot._player_pilot_id = 5
	return pilot


func test_the_server_flies_a_remote_pilot_from_their_input_channel() -> void:
	var ship := _ship(&"b5:aurora_starfury", Vector3.ZERO)
	var pilot := _remote_player_at_cockpit(ship)
	pilot.inputs.throttle = Vector3(0, 0, 1)  # The old synced value: must not be used.
	assert_eq(pilot.receive_inputs_from(99, [InputChannel.make_record(7, Vector3(0, 0, -1), Vector3.ZERO)]), "")
	await Ticks.run(1)
	assert_eq(_helm(ship).throttle, Vector3(0, 0, -1), "from the channel")
	assert_eq(pilot.input_channel.last_applied_tick, 7)


func test_input_packets_only_from_that_characters_player() -> void:
	var ship := _ship(&"b5:aurora_starfury", Vector3.ZERO)
	var pilot := _remote_player_at_cockpit(ship)
	var packet := [InputChannel.make_record(7, Vector3(0, 0, -1), Vector3.ZERO)]
	assert_ne(pilot.receive_inputs_from(42, packet), "", "another peer can't steer my ship")
	assert_eq(pilot.input_channel.queued(), 0)
