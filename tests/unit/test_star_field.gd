extends GutTest
## StarCatalogService (sources, background loading) and the StarField node
## (sky placed on its anchor star, magnitudes as shader parameters).

const DIR := "user://test_star_field"
const CACHE := DIR + "/cache"
const HEADER := "id,gaia,hyg,hip,bayer,flam,con,proper,x,y,z,absmag,ci,spect"
const StarFieldScript := preload("res://addons/star_field/star_field_manager.gd")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE)


func after_each() -> void:
	for dir in [CACHE, DIR]:
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


func _csv(file: String, rows: String) -> String:
	var path := DIR.path_join(file)
	FileAccess.open(path, FileAccess.WRITE).store_string(HEADER + "\n" + rows)
	return path


## A service with its own sources and cache, so tests never touch the game's.
func _service(sources: Array) -> StarCatalogService:
	var service := StarCatalogService.new()
	service.cache_dir = CACHE
	service.shipped_path = ""
	service.set_sources(PackedStringArray(sources))
	add_child_autofree(service)
	return service


func _ready_catalog(service: StarCatalogService) -> StarCatalog:
	if service.catalog == null:
		service.request()
		await wait_for_signal(service.catalog_ready, 10)
	return service.catalog


func test_default_sources_are_the_shipped_database() -> void:
	var service := StarCatalogService.new()
	assert_eq(service.get_sources(), PackedStringArray([StarCatalogService.DEFAULT_SOURCE]))
	service.free()


func test_shipped_catalogue_matches_the_default_csv() -> void:
	# Fails when the CSV or the format changes without rebuilding the shipped
	# file (Project > Tools > Rebuild star catalogue, or the tools script).
	var shipped := StarCatalog.read(StarCatalogService.SHIPPED_CATALOG,
			StarCatalogCache.key_for(PackedStringArray([StarCatalogService.DEFAULT_SOURCE])))
	assert_not_null(shipped)
	if shipped:
		assert_gt(shipped.get_star_count(), 100000)
		assert_ne(shipped.find("Ran"), -1)
		assert_almost_eq((shipped.get_star_position("Sol") as Vector3).length(), 0.0, 0.001)


func test_request_loads_in_the_background() -> void:
	var service := _service([_csv("a.csv", "1,,0,,,,,Ran,1,0,0,1,0.5,G2 V\n")])
	assert_null(service.catalog)
	service.request()
	assert_true(service.is_loading())
	await wait_for_signal(service.catalog_ready, 10)
	assert_false(service.is_loading())
	assert_eq(service.catalog.get_star_position("Ran"), Vector3(1, 0, 0))


func test_mod_can_add_remove_or_replace_sources() -> void:
	var base := _csv("base.csv", "1,,0,,,,,Ran,1,0,0,1,0.5,G2 V\n")
	var mod := _csv("mod.csv", "1,,0,,,,,Ran,2,0,0,1,0.5,G2 V\n2,,1,,,,,Babylon,3,0,0,1,0.5,G2 V\n")
	var service := _service([base])
	service.add_source(mod)
	assert_eq(service.get_sources(), PackedStringArray([base, mod]))
	var cat: StarCatalog = await _ready_catalog(service)
	assert_eq(cat.get_star_position("Ran"), Vector3(2, 0, 0), "the later source wins")
	service.remove_source(base)
	assert_eq(service.get_sources(), PackedStringArray([mod]))
	service.set_sources(PackedStringArray([base]))
	await wait_for_signal(service.catalog_ready, 10)
	assert_eq(service.catalog.get_star_position("Ran"), Vector3(1, 0, 0))
	assert_eq(service.catalog.find("Babylon"), -1)


func test_changing_sources_after_loading_reloads() -> void:
	var service := _service([_csv("a.csv", "1,,0,,,,,Ran,1,0,0,1,0.5,G2 V\n")])
	await _ready_catalog(service)
	service.add_source(_csv("b.csv", "1,,0,,,,,Ran,9,0,0,1,0.5,G2 V\n"))
	assert_true(service.is_loading())
	await wait_for_signal(service.catalog_ready, 10)
	assert_eq(service.catalog.get_star_position("Ran"), Vector3(9, 0, 0))


func _field(service: StarCatalogService) -> Node:
	var field: Node = StarFieldScript.new()
	field.catalog_service = service
	add_child_autofree(field)
	return field


func test_star_field_places_the_sky_on_its_anchor_star() -> void:
	var service := _service([_csv("a.csv", "1,,0,,,,,Ran,1,2,3,1,0.5,G2 V\n")])
	var field := _field(service)
	field.anchor_star = "Ran"
	field.anchor_offset_au = Vector3(0, 0, 1.058)
	await wait_for_signal(field.catalog_applied, 10)
	assert_almost_eq(field.celestial_coords,
			Vector3(1, 2, 3 + 1.058 * StarFieldScript.AU_IN_PARSEC), Vector3.ONE * 1e-9)
	assert_eq(field.get_star_position("Ran"), Vector3(1, 2, 3))


func test_star_field_shows_the_catalogue_stars() -> void:
	var service := _service([_csv("a.csv", "1,,0,,,,,Ran,1,2,3,1,0.5,G2 V\n2,,1,,,,,,4,5,6,1,0.5,G2 V\n")])
	var field := _field(service)
	await wait_for_signal(field.catalog_applied, 10)
	var render: MultiMeshInstance3D = field.star_render
	assert_eq(render.multimesh.instance_count, 2)
	assert_eq(render.multimesh.buffer, service.catalog.buffer)
	assert_eq(render.multimesh.transform_format, MultiMesh.TRANSFORM_3D)
	assert_true(render.multimesh.use_colors and render.multimesh.use_custom_data)
	assert_not_null(render.multimesh.mesh, "keeps the star point mesh")


func test_magnitudes_are_shader_parameters_of_the_node() -> void:
	var service := _service([_csv("a.csv", "1,,0,,,,,Ran,1,2,3,1,0.5,G2 V\n")])
	var field := _field(service)
	field.mag_ref = 5.0
	field.mag_limit = 6.5
	var render: GeometryInstance3D = field.star_render
	assert_eq(render.get_instance_shader_parameter("mag_ref"), 5.0)
	assert_eq(render.get_instance_shader_parameter("mag_limit"), 6.5)


func test_labels_are_made_only_for_named_stars_when_shown() -> void:
	var service := _service([_csv("a.csv", "1,,0,,,,,Ran,1,2,3,1,0.5,G2 V\n2,,1,,,,,,4,5,6,1,0.5,G2 V\n")])
	var field := _field(service)
	field.star_labels_visible = false
	await wait_for_signal(field.catalog_applied, 10)
	var labels: Node = field.star_render.get_node("star_labels")
	assert_eq(labels.get_child_count(), 0)
	field.star_labels_visible = true
	assert_eq(labels.get_child_count(), 1)
	assert_eq((labels.get_child(0) as Label3D).text, "Ran")


func test_two_star_fields_share_one_catalogue_load() -> void:
	var service := _service([_csv("a.csv", "1,,0,,,,,Ran,1,2,3,1,0.5,G2 V\n")])
	var a := _field(service)
	var b := _field(service)
	await wait_for_signal(b.catalog_applied, 10)
	assert_eq(a.star_render.multimesh, b.star_render.multimesh, "one MultiMesh for both")
