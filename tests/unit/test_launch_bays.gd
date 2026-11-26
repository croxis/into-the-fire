extends GutTest
## Launching fighters: every ship with launch bays answers find_free_spawner()
## the same way, so Ship.request_launch works from any of them.
##
## Contract: [launch_point, position] when a bay is free, where launch_point has
## spawn_ship(ship); [] when every bay is busy.

const SystemScene := preload("res://systems/system_template.tscn")


func _in_system(content_id: StringName) -> Ship:
	var system: System = SystemScene.instantiate()
	add_child_autofree(system)
	var ship: Ship = Content.instantiate(content_id)
	system.add_ship(ship)
	return ship


func _assert_launch_point(spawn: Array, label: String) -> void:
	assert_eq(spawn.size(), 2, label + ": [launch_point, position]")
	if spawn.size() == 2:
		assert_true(spawn[0].has_method("spawn_ship"), label + ": the launch point can launch")
		assert_true(spawn[1] is Vector3, label + ": a position")


func test_hyperion_has_a_free_bay() -> void:
	var hyperion := _in_system(&"b5:hyperion")
	_assert_launch_point(hyperion.find_free_spawner(), "Hyperion")


func test_babylon_5_has_a_free_bay() -> void:
	var b5 := _in_system(&"b5:babylon_5")
	_assert_launch_point(b5.find_free_spawner(), "Babylon 5")


func test_hyperion_launches_a_fighter_from_the_bay() -> void:
	var hyperion := _in_system(&"b5:hyperion")
	hyperion.linear_velocity = Vector3(0, 0, -50)
	var spawn := hyperion.find_free_spawner()
	var fighter: Ship = Content.instantiate(&"b5:aurora_starfury")
	hyperion.get_current_system().add_ship(fighter)
	fighter.global_position = spawn[1]
	spawn[0].spawn_ship(fighter)
	assert_almost_eq(fighter.global_position, spawn[1], Vector3.ONE * 0.01)
	assert_eq(fighter.linear_velocity, hyperion.linear_velocity,
			"leaves at the carrier's speed, so the carrier doesn't run it over")


func test_closed_hyperion_hangar_has_no_bay() -> void:
	var hyperion := _in_system(&"b5:hyperion")
	var spawner := hyperion.get_node("Spawner")
	spawner.bays_closed = true
	assert_eq(hyperion.find_free_spawner(), [], "and it must not loop forever")


func test_babylon_5_with_every_arm_busy_has_none() -> void:
	var b5 := _in_system(&"b5:babylon_5")
	for arm in b5.find_children("CobraBayArm*", "", true, false):
		arm.is_ready = false  # Busy launching.
	assert_eq(b5.find_free_spawner(), [], "and it must not loop forever")


func test_babylon_5_launches_a_fighter_at_its_own_size() -> void:
	# The bays' spawn points sit under scaled nodes (a global scale of 0.81).
	# The arm must place the fighter there without that scale, or it flies at
	# 81% size with its thrust scaled down too.
	var b5 := _in_system(&"b5:babylon_5")
	var spawn := b5.find_free_spawner()
	var fighter: Ship = Content.instantiate(&"b5:aurora_starfury")
	b5.get_current_system().add_ship(fighter)
	spawn[0].spawn_ship(fighter)
	spawn[0]._process(0.0)  # The arm holds the fighter at its spawn point.
	assert_almost_eq(fighter.global_transform.basis.get_scale(), Vector3.ONE, Vector3.ONE * 1e-6)
	assert_almost_eq(fighter.global_position, spawn[1], Vector3.ONE * 0.01)


## Babylon 5's arms run on the clock, not on timers and free-running animations:
## where an arm is depends only on the server tick, so a client (told when the
## deploy starts) shows its arm exactly where the server's is at the moment it
## draws the station. Then the pilot's own ship can ride its own arm.

func _two_arms() -> Array:
	var b5 := _in_system(&"b5:babylon_5")
	var arms := b5.find_children("CobraBayArm*", "", true, false)
	var spawn := b5.find_free_spawner()
	var fighter: Ship = Content.instantiate(&"b5:aurora_starfury")
	b5.get_current_system().add_ship(fighter)
	var server_arm = spawn[0]
	server_arm.spawn_ship(fighter)
	var client_arm = arms[0] if arms[0] != server_arm else arms[1]
	client_arm._deploy(server_arm.deploy_start_tick, String(fighter.name))  # What the RPC carries.
	return [server_arm, client_arm, fighter]


func _pose(arm: Node) -> float:
	return (arm.get_node("loading/loadingexternder/extender-rotating") as Node3D).rotation.x


func test_the_deploy_starts_a_second_after_the_ship_arrives() -> void:
	var parts := _two_arms()
	assert_eq(parts[0].deploy_start_tick, NetworkTime.tick + parts[0].WAIT_TICKS)


func test_an_arm_is_where_the_clock_says_on_every_machine() -> void:
	var parts := _two_arms()
	var start: int = parts[0].deploy_start_tick
	for t in [start - 10, start + 15.5, start + 40, start + 75]:
		parts[0].update_to(float(t))
		parts[1].update_to(float(t))
		assert_almost_eq(_pose(parts[1]), _pose(parts[0]), 1e-6, "at tick %s" % t)


func test_the_ship_is_held_through_the_deploy_then_let_go() -> void:
	var parts := _two_arms()
	var arm = parts[0]
	var fighter: Ship = parts[2]
	var start: int = arm.deploy_start_tick
	arm.update_to(float(start + 30))
	assert_true(fighter.freeze, "still on the arm, halfway out")
	arm.update_to(float(start + arm.deploy_ticks() + 1))
	assert_false(fighter.freeze, "let go at the end of the deploy")
	assert_almost_eq(fighter.linear_velocity.length(), 30.0, 1e-6, "pushed off at 30 m/s")
	arm.update_to(float(start + arm.deploy_ticks() + arm.return_ticks() + 1))
	assert_true(arm.is_ready, "back and ready for the next")


func _client_arm_with_own_ship() -> Array:
	var b5 := _in_system(&"b5:babylon_5")
	var arm = b5.find_free_spawner()[0]
	var fighter: Ship = Content.instantiate(&"b5:aurora_starfury")
	b5.get_current_system().add_ship(fighter)
	fighter.prediction_forced = true  # The pilot's own client.
	fighter.freeze = true  # As the server's first frozen state left it.
	arm._deploy(1000, String(fighter.name))
	return [arm, fighter]


func test_the_pilots_own_ship_rides_their_own_arm() -> void:
	# The arm and the station are drawn at the same moment, so the ship stays on
	# the arm, instead of following server states that arrive unevenly.
	var parts := _client_arm_with_own_ship()
	var arm = parts[0]
	var fighter: Ship = parts[1]
	arm.update_to(1030.0)
	var at: Transform3D = arm.get_node("loading/loadingexternder/extender-rotating/spawn_point").global_transform
	assert_almost_eq(fighter.global_position, at.origin, Vector3.ONE * 1e-6)
	assert_true(fighter.held_by_local_arm)


func test_server_states_dont_pull_it_off_the_arm() -> void:
	var parts := _client_arm_with_own_ship()
	var arm = parts[0]
	var fighter: Ship = parts[1]
	arm.update_to(1030.0)
	var on_arm := fighter.global_position
	var server := FlightIntegrator.FlightState.new()
	server.transform = Transform3D(Basis(), on_arm + Vector3(40, 0, 0))  # The server's arm, an instant apart.
	fighter.reconciler.reconcile(server, 5, 10, true)
	assert_eq(fighter.global_position, on_arm, "still on its arm here")
	assert_true(fighter.freeze)


func test_after_the_deploy_the_arm_lets_go_of_it() -> void:
	var parts := _client_arm_with_own_ship()
	var arm = parts[0]
	var fighter: Ship = parts[1]
	arm.update_to(1000.0 + arm.deploy_ticks() + 1.0)
	assert_false(fighter.held_by_local_arm, "the server's release state takes over")


func test_once_released_by_the_server_the_arm_stops_holding_it() -> void:
	# The server's release arrives before this client's arm (drawn about 100 ms
	# in the past) finishes its swing: holding on would drag the now-flying
	# ship back to the arm each frame.
	var parts := _client_arm_with_own_ship()
	var arm = parts[0]
	var fighter: Ship = parts[1]
	arm.update_to(1030.0)
	fighter.freeze = false  # The server's first unfrozen state.
	fighter.held_by_local_arm = false
	fighter.global_position = Vector3(0, 0, 9999)  # Flying, predicted.
	arm.update_to(1040.0)
	assert_eq(fighter.global_position, Vector3(0, 0, 9999), "left where prediction put it")
	assert_false(fighter.held_by_local_arm)
