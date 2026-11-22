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
		assert_true(registry.load_scene(id) != null, "%s is a scene" % id)
