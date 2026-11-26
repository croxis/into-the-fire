extends GutTest
## Content IDs map to resources; manifests fill the registry.

const MANIFEST_DIR := "user://test_content/"

var registry: ContentRegistry


func before_each() -> void:
	registry = ContentRegistry.new()


func _write_manifest(file_name: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(MANIFEST_DIR)
	var path := MANIFEST_DIR + file_name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


func after_all() -> void:
	for f in DirAccess.get_files_at(MANIFEST_DIR):
		DirAccess.remove_absolute(MANIFEST_DIR + f)
	DirAccess.remove_absolute(MANIFEST_DIR)


func test_id_format() -> void:
	assert_true(ContentRegistry.is_valid_id(&"b5:aurora_starfury"))
	assert_false(ContentRegistry.is_valid_id(&"aurora_starfury"), "needs a namespace")
	assert_false(ContentRegistry.is_valid_id(&"B5:Starfury"), "lowercase only")
	assert_false(ContentRegistry.is_valid_id(&"b5:star fury"))


func test_register_and_look_up() -> void:
	assert_true(registry.register(&"t:ship", &"ship", "res://some/ship.tscn"))
	assert_true(registry.has(&"t:ship"))
	assert_eq(registry.path_of(&"t:ship"), "res://some/ship.tscn")
	assert_eq(registry.get_kind(&"t:ship"), &"ship")


func test_malformed_id_is_refused() -> void:
	assert_false(registry.register(&"no_namespace", &"ship", "res://x.tscn"))
	assert_push_error_count(1)
	assert_false(registry.has(&"no_namespace"))


func test_later_registration_overrides() -> void:
	registry.register(&"b5:starfury", &"ship", "res://base.tscn")
	registry.register(&"b5:starfury", &"ship", "res://mod.tscn", "mod")
	assert_eq(registry.path_of(&"b5:starfury"), "res://mod.tscn")


func test_unknown_id_reports_error() -> void:
	assert_eq(registry.path_of(&"t:missing"), "")
	assert_null(registry.instantiate(&"t:missing"))
	assert_push_error_count(2)


func test_ids_filter_by_kind_and_sort() -> void:
	registry.register(&"t:b", &"ship", "res://b.tscn")
	registry.register(&"t:a", &"ship", "res://a.tscn")
	registry.register(&"t:sys", &"system", "res://s.tscn")
	assert_eq(registry.ids(&"ship"), [&"t:a", &"t:b"] as Array[StringName])
	assert_eq(registry.ids().size(), 3)


func test_load_manifest() -> void:
	var path := _write_manifest("ok.cfg", "[meta]\nnamespace=\"t\"\n\n[ship]\nfury=\"res://fury.tscn\"\n\n[system]\nhome=\"res://home.tscn\"\n")
	assert_eq(registry.load_manifest(path), 2)
	assert_eq(registry.path_of(&"t:fury"), "res://fury.tscn")
	assert_eq(registry.get_kind(&"t:home"), &"system")


func test_manifest_without_namespace_registers_nothing() -> void:
	var path := _write_manifest("bad.cfg", "[ship]\nfury=\"res://fury.tscn\"\n")
	assert_eq(registry.load_manifest(path), 0)
	assert_push_error_count(1)


## The shipped Babylon 5 manifest must resolve to real scenes.
func test_babylon5_manifest_resolves() -> void:
	assert_gt(registry.load_manifest("res://content/babylon5.cfg"), 0)
	for id in registry.ids():
		assert_true(ResourceLoader.exists(registry.path_of(id)), "%s exists" % id)
	for kind in [&"ship", &"system"]:
		for id in registry.ids(kind):
			assert_true(registry.load_scene(id) != null, "%s is a scene" % id)
	for id in registry.ids(&"scenario"):
		assert_true(load(registry.path_of(id)) is Scenario, "%s is a Scenario" % id)


## Content loads every ship scene in the first frames after startup, one a
## frame: loading the Starfury from disk the first time took about 300 ms, a
## stall that froze a client's ticks at its first launch (its inputs then
## reached the server in a clump) and the server's at the first launch it built.

func test_ship_scenes_are_loaded_at_startup_and_kept() -> void:
	var waited := 0.0
	while not Content.ships_preloaded() and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	assert_true(Content.ships_preloaded(), "done within 20 s")
	for id in Content.registry.ids(&"ship"):
		assert_true(ResourceLoader.has_cached(ResourceUID.ensure_path(Content.path_of(id))),
				"%s is in memory: instantiating it reads nothing from disk" % id)


func test_a_big_ship_is_quick_to_add_once_its_shapes_are_warmed() -> void:
	# Jolt builds a concave hull shape the first time a body uses it: 277 ms for
	# Babylon 5's, a stall wherever the station first appeared (a client's
	# spawn, or fog of war revealing it mid-flight). Content builds them in the
	# background of startup, so adding the ship later costs next to nothing.
	var waited := 0.0
	while not Content.ships_ready() and waited < 30.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	assert_true(Content.ships_ready(), "warmed within 30 s")
	var station: Node = Content.instantiate(&"b5:babylon_5")
	var t0 := Time.get_ticks_usec()
	add_child_autofree(station)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_lt(ms, 60.0, "added in %.1f ms" % ms)
