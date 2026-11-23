extends GutTest
## SceneBatchLoader: several scenes requested at once on worker threads, handed
## back together when every one has finished.

const SHIP := "res://ships/Ship.tscn"
const SYSTEM := "res://systems/system_template.tscn"


func _finish(batch: SceneBatchLoader) -> void:
	var frames := 0
	while not batch.is_done() and frames < 600:
		batch.poll()
		await get_tree().process_frame
		frames += 1


func test_loads_every_scene() -> void:
	var batch := SceneBatchLoader.new(PackedStringArray([SHIP, SYSTEM]))
	await _finish(batch)
	assert_true(batch.is_done())
	assert_true(batch.scenes[SHIP] is PackedScene)
	assert_true(batch.scenes[SYSTEM] is PackedScene)
	assert_eq(batch.failed, PackedStringArray())
	assert_eq(batch.poll(), 1.0, "progress when done")


func test_scenes_are_then_in_the_resource_cache() -> void:
	# What makes the later plain load() calls (ScenarioLoader.populate) cheap.
	var batch := SceneBatchLoader.new(PackedStringArray([SHIP]))
	await _finish(batch)
	assert_true(ResourceLoader.has_cached(SHIP))
	assert_eq(load(SHIP), batch.scenes[SHIP])


func test_each_path_is_loaded_once() -> void:
	var batch := SceneBatchLoader.new(PackedStringArray([SHIP, SHIP]))
	assert_eq(batch.paths, PackedStringArray([SHIP]))
	await _finish(batch)


func test_missing_scene_is_reported_not_fatal() -> void:
	var missing := "res://no/such/scene.tscn"
	var batch := SceneBatchLoader.new(PackedStringArray([missing, SHIP]))
	await _finish(batch)
	assert_true(batch.is_done())
	assert_eq(batch.failed, PackedStringArray([missing]))
	assert_null(batch.scenes[missing])
	assert_true(batch.scenes[SHIP] is PackedScene)


func test_uid_paths_work() -> void:
	var uid := ResourceUID.id_to_text(ResourceLoader.get_resource_uid(SHIP))
	var batch := SceneBatchLoader.new(PackedStringArray([uid]))
	await _finish(batch)
	assert_true(batch.scenes[uid] is PackedScene)


func test_empty_batch_is_done_at_once() -> void:
	var batch := SceneBatchLoader.new(PackedStringArray())
	assert_true(batch.is_done())
	assert_eq(batch.poll(), 1.0)
