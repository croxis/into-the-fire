extends GutTest
## AiPilot: how an NPC flies (server only). It works out helm throttles itself,
## as a pilot's controls would set them: fly to a point and hold there, or
## follow a route. NPC helms take their input from it, never from the server
## machine's own keyboard.

const Ticks := preload("res://tests/unit/ticks.gd")
const SystemScene := preload("res://systems/system_template.tscn")

var stepper: ZoneStepper

## Ticks per physics frame: flights take tens of seconds.
const FAST := 4


func before_each() -> void:
	stepper = ZoneStepper.new()
	add_child_autofree(stepper)


func _npc_fighter(at := Vector3.ZERO) -> Character:
	var system: System = SystemScene.instantiate()  # One zone each: no collisions.
	add_child_autofree(system)
	stepper.add_zone(system)
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(ship)
	ship.global_position = at
	var pilot: Character = ship.get_node("CrewMultiplayerSpawner").spawn(Character.pilot_data("Alpha 1", 0, 1, 1))
	(ship.get_node("Consoles/Cockpit") as Console).occupy(pilot)
	return pilot


func _speed(pilot: Character) -> float:
	return pilot.current_ship.linear_velocity.length()


func test_thrust_capability_comes_from_the_ships_thrusters() -> void:
	var pilot := _npc_fighter()
	var a := AiPilot.accelerations(pilot.current_ship)
	assert_almost_eq(a.forward, 37.5, 0.5, "the Starfury's main engines")
	assert_almost_eq(a.reverse, 14.2, 0.5)
	assert_almost_eq(a.lateral, 4.2, 0.2)
	assert_almost_eq(a.vertical, 4.2, 0.2)


func test_an_npc_never_flies_from_the_servers_keyboard() -> void:
	# NPCs carry the server's peer ID, so their controls were the server
	# machine's own: on a host, the host's keys flew every NPC.
	var pilot := _npc_fighter()
	Input.action_press("forward_full_thrust")
	await Ticks.run(30, 0, FAST)
	Input.action_release("forward_full_thrust")
	assert_lt(_speed(pilot), 0.5, "no AI orders: hands off, not the keyboard's")


func test_flies_to_a_point_and_holds_there() -> void:
	var pilot := _npc_fighter()
	var target := Vector3(300, 100, 700)  # Behind it (it faces -Z) and off to the side.
	pilot.ai_pilot.fly_to(target)
	await Ticks.run(1500, 0, FAST)  # 25 s.
	var ship := pilot.current_ship
	assert_lt(ship.global_position.distance_to(target), AiPilot.HOLD_RADIUS * 2.0, "arrived")
	assert_lt(_speed(pilot), 3.0, "and stopped")
	await Ticks.run(300, 0, FAST)
	assert_lt(ship.global_position.distance_to(target), AiPilot.HOLD_RADIUS * 2.0, "holds there")
	Ticks.excuse_jolt_job_pool(get_errors())  # Known issue, zones/CLAUDE.md.


func test_follows_a_route_in_order() -> void:
	var pilot := _npc_fighter()
	var route: Array[Vector3] = [Vector3(0, 0, -700), Vector3(700, 0, -700), Vector3(700, 0, 0)]
	pilot.ai_pilot.follow(route, false)
	var reached: Array[int] = []
	for i in 120:  # Up to 60 s.
		await Ticks.run(30, 0, FAST)
		if reached.is_empty() or reached.back() != pilot.ai_pilot.waypoint_index:
			reached.append(pilot.ai_pilot.waypoint_index)
		if pilot.ai_pilot.is_done():
			break
	assert_eq(reached, [0, 1, 2], "each waypoint in turn")
	assert_true(pilot.ai_pilot.is_done(), "the route is flown")
	await Ticks.run(600, 0, FAST)
	assert_lt(pilot.current_ship.global_position.distance_to(route[2]), AiPilot.HOLD_RADIUS * 2.0,
			"and it holds at the end of a route that doesn't loop")
	Ticks.excuse_jolt_job_pool(get_errors())  # Known issue, zones/CLAUDE.md.


func test_a_looping_route_goes_round_again() -> void:
	var pilot := _npc_fighter()
	var route: Array[Vector3] = [Vector3(0, 0, -600), Vector3(0, 0, 0)]
	pilot.ai_pilot.follow(route, true)
	var laps := 0
	var last := 0
	for i in 160:
		await Ticks.run(30, 0, FAST)
		if pilot.ai_pilot.waypoint_index < last:
			laps += 1
		last = pilot.ai_pilot.waypoint_index
		if laps >= 1:
			break
	assert_eq(laps, 1, "back to the first waypoint")
	assert_false(pilot.ai_pilot.is_done(), "a loop is never done")
	Ticks.excuse_jolt_job_pool(get_errors())  # Known issue, zones/CLAUDE.md.


func test_route_points_can_follow_a_moving_anchor() -> void:
	# A patrol round a carrier is relative to it (PatrolRoute.from_anchor).
	var pilot := _npc_fighter()
	var anchor := Node3D.new()
	pilot.current_ship.get_parent().add_child(anchor)
	var route: Array[Vector3] = [Vector3(0, 0, -500)]
	pilot.ai_pilot.follow(route, false, anchor)
	anchor.global_position = Vector3(1000, 0, 0)
	assert_almost_eq(pilot.ai_pilot.current_target(), Vector3(1000, 0, -500), Vector3.ONE * 0.01)
	anchor.queue_free()
	await get_tree().process_frame
	assert_almost_eq(pilot.ai_pilot.current_target(), Vector3(1000, 0, -500), Vector3.ONE * 0.01,
			"where it last was, once the anchor is gone")
