extends GutTest
## StarCatalogCache: shipped catalogue first, then the user:// cache, else a
## fresh build; rebuilt when any source changes; old caches deleted.

const DIR := "user://test_star_catalog_cache"
const CACHE := DIR + "/cache"
const HEADER := "id,gaia,hyg,hip,bayer,flam,con,proper,x,y,z,absmag,ci,spect"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE)


func after_each() -> void:
	for dir in [CACHE, DIR]:
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


func _csv(file: String, x: float) -> String:
	var path := DIR.path_join(file)
	FileAccess.open(path, FileAccess.WRITE).store_string(
			"%s\n1,,0,,,,,Ran,%s,0,0,1,0.5,G2 V\n" % [HEADER, x])
	return path


func _cache(shipped := "") -> StarCatalogCache:
	return StarCatalogCache.new(CACHE, shipped)


func _cache_files() -> PackedStringArray:
	return DirAccess.get_files_at(CACHE)


func test_first_load_builds_and_writes_the_cache() -> void:
	var cache := _cache()
	var cat := cache.load_or_build(PackedStringArray([_csv("a.csv", 1)]))
	assert_true(cache.built)
	assert_eq(cat.get_star_position("Ran"), Vector3(1, 0, 0))
	assert_eq(_cache_files().size(), 1)


func test_second_load_reads_the_cache_without_building() -> void:
	var sources := PackedStringArray([_csv("a.csv", 1)])
	_cache().load_or_build(sources)
	var cache := _cache()
	var cat := cache.load_or_build(sources)
	assert_false(cache.built)
	assert_eq(cat.get_star_position("Ran"), Vector3(1, 0, 0))


func test_changed_csv_rebuilds_and_deletes_the_old_cache() -> void:
	var sources := PackedStringArray([_csv("a.csv", 1)])
	_cache().load_or_build(sources)
	var old := _cache_files()
	_csv("a.csv", 2)
	var cache := _cache()
	var cat := cache.load_or_build(sources)
	assert_true(cache.built)
	assert_eq(cat.get_star_position("Ran"), Vector3(2, 0, 0))
	assert_eq(_cache_files().size(), 1)
	assert_ne(_cache_files(), old)


func test_added_or_removed_source_changes_the_key() -> void:
	var a := _csv("a.csv", 1)
	var b := _csv("b.csv", 2)
	var one := StarCatalogCache.key_for(PackedStringArray([a]))
	assert_ne(one, StarCatalogCache.key_for(PackedStringArray([a, b])))
	assert_ne(StarCatalogCache.key_for(PackedStringArray([a, b])), StarCatalogCache.key_for(PackedStringArray([b, a])))
	assert_eq(one, StarCatalogCache.key_for(PackedStringArray([a])))


func test_damaged_cache_is_rebuilt() -> void:
	var sources := PackedStringArray([_csv("a.csv", 1)])
	_cache().load_or_build(sources)
	var path := CACHE.path_join(_cache_files()[0])
	FileAccess.open(path, FileAccess.WRITE).store_string("garbage")
	var cache := _cache()
	assert_eq(cache.load_or_build(sources).get_star_position("Ran"), Vector3(1, 0, 0))
	assert_true(cache.built)


func test_matching_shipped_catalogue_is_used_and_caches_are_cleared() -> void:
	var sources := PackedStringArray([_csv("a.csv", 1)])
	_cache().load_or_build(sources)  # Leaves a cache file behind.
	var shipped := DIR.path_join("shipped.stars")
	assert_eq(StarCatalogCache.build_shipped(sources, shipped), OK)
	var cache := _cache(shipped)
	var cat := cache.load_or_build(sources)
	assert_false(cache.built)
	assert_eq(cat.get_star_position("Ran"), Vector3(1, 0, 0))
	assert_eq(_cache_files().size(), 0, "a cache is not needed while the shipped one fits")


func test_shipped_catalogue_is_ignored_when_sources_differ() -> void:
	var a := _csv("a.csv", 1)
	var shipped := DIR.path_join("shipped.stars")
	StarCatalogCache.build_shipped(PackedStringArray([a]), shipped)
	var cache := _cache(shipped)
	var cat := cache.load_or_build(PackedStringArray([a, _csv("mod.csv", 5)]))
	assert_true(cache.built)
	assert_eq(cat.get_star_position("Ran"), Vector3(5, 0, 0))
