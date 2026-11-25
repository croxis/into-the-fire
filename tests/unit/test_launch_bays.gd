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
