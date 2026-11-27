extends GutTest
## WorldBuilder: the one path a world starts by (a scenario today, a save
## later): check it, create its factions, load its scenes, add its systems,
## place its ships and crews. Only the machine that runs the world builds one;
## offline counts as that. With no loading screen connected (tests), the
## scenes load at once.

var galaxy: Galaxy


func before_each() -> void:
	galaxy = preload("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)


func test_a_new_world_is_built_from_its_scenario() -> void:
	watch_signals(galaxy)
	assert_true(galaxy.start_new_world())
	assert_signal_emitted(galaxy, "world_built")
	assert_gt(galaxy.zones.systems().size(), 0, "the scenario's systems")
	var ships := 0
	for system in galaxy.zones.systems():
		ships += system.get_ships().size()
	assert_gt(ships, 0, "and its ships")
	assert_not_null(galaxy.factions.find_by_name("Earth Alliance"), "its factions")
	assert_true(galaxy.active_galaxy)


func test_a_world_is_built_once() -> void:
	galaxy.start_new_world()
	var systems := galaxy.zones.systems().size()
	assert_false(galaxy.start_new_world())
	assert_eq(galaxy.zones.systems().size(), systems)


func test_a_host_may_spawn_once_its_world_is_built() -> void:
	var systems_then := []
	galaxy.ready_to_spawn.connect(func() -> void: systems_then.append(galaxy.zones.systems().size()))
	galaxy.start_new_world(true)
	assert_eq(systems_then.size(), 1)
	assert_gt(systems_then[0], 0, "spawn points exist by then")


func test_a_dedicated_server_does_not_spawn_itself() -> void:
	watch_signals(galaxy)
	galaxy.start_new_world(false)
	assert_signal_not_emitted(galaxy, "ready_to_spawn")


func test_a_world_still_builds_when_its_scenes_arrive_later() -> void:
	# The loading screen calls back frames later. Nothing but the Galaxy held
	# the builder then, so it was freed and the callback hit a null instance.
	var later := []
	galaxy.scene_loader = func(paths: PackedStringArray, done: Callable) -> void:
		later.append(func() -> void: WorldBuilder.load_now(paths, done))
	watch_signals(galaxy)
	assert_true(galaxy.start_new_world())
	assert_signal_not_emitted(galaxy, "world_built", "still loading")
	await wait_process_frames(2)
	later[0].call()
	assert_signal_emitted(galaxy, "world_built")
