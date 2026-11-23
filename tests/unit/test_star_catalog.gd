extends GutTest
## StarCatalog (plain star data, its file format) and StarCatalogBuilder
## (CSV sources merged in order, later sources win).

const DIR := "user://test_star_catalog"
const HEADER := "id,gaia,hyg,hip,bayer,flam,con,proper,x,y,z,absmag,ci,spect"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


## Writes a CSV with the athyg columns. Each row: [gaia, hip, proper, x, y, z, absmag, ci].
func _csv(file: String, rows: Array) -> String:
	var path := DIR.path_join(file)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line(HEADER)
	for i in rows.size():
		var r: Array = rows[i]
		f.store_line("%d,%s,%d,%s,,,,%s,%s,%s,%s,%s,%s,G2 V" % [i + 1, r[0], i, r[1], r[2], r[3], r[4], r[5], r[6], r[7]])
	return path


func _build(sources: Array) -> StarCatalog:
	return StarCatalogBuilder.new().build(PackedStringArray(sources))


func test_sun_colour_matches_the_old_star_field() -> void:
	# Values the previous generate_stars produced for Sol (ci 0.656).
	var c := StarCatalogBuilder.temperature_color(0.656)
	assert_almost_eq(c.r, 1.0, 0.001)
	assert_almost_eq(c.g, 0.949132, 0.001)
	assert_almost_eq(c.b, 0.901673, 0.001)


func test_build_reads_positions_magnitudes_and_names() -> void:
	var path := _csv("a.csv", [["", "", "Sol", "0.000005", "0", "0", "4.85", "0.656"],
			["123", "7", "", "1.5", "-2", "3.25", "1.2", "0.1"]])
	var cat := _build([path])
	assert_eq(cat.get_star_count(), 2)
	assert_almost_eq(cat.get_position(1), Vector3(1.5, -2, 3.25), Vector3.ONE * 1e-5)
	assert_almost_eq(cat.get_absolute_magnitude(0), 4.85, 1e-5)
	assert_almost_eq(cat.get_color(0).g, 0.949132, 0.001)
	assert_eq(cat.find("Sol"), 0)
	assert_eq(cat.find("Nowhere"), -1)
	assert_almost_eq(cat.get_star_position("Sol") as Vector3, Vector3(0.000005, 0, 0), Vector3.ONE * 1e-7)
	assert_null(cat.get_star_position("Nowhere"))


func test_buffer_is_laid_out_for_a_multimesh() -> void:
	# MultiMesh.buffer with TRANSFORM_3D, colours and custom data: the basis and
	# origin as three rows of four, then colour, then custom data. (Checked on
	# the raw floats: the headless renderer keeps no per-instance data to read
	# back through get_instance_transform.)
	var path := _csv("a.csv", [["", "", "", "1", "2", "3", "4.85", "0.656"]])
	var b := _build([path]).buffer
	assert_eq(b.size(), 20)
	assert_eq(Array(b.slice(0, 12)), [1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 2.0, 0.0, 0.0, 1.0, 3.0])
	assert_almost_eq(b[13], 0.949132, 0.001, "colour green")
	assert_eq(b[15], 1.0, "colour alpha")
	assert_almost_eq(b[16], 4.85, 1e-5, "custom x: absolute magnitude")


func test_later_source_replaces_a_star_matched_by_any_id() -> void:
	var base := _csv("base.csv", [["111", "", "", "1", "0", "0", "1", "0"],
			["", "222", "", "2", "0", "0", "1", "0"],
			["", "", "Ran", "3", "0", "0", "1", "0"]])
	var mod := _csv("mod.csv", [["111", "", "", "10", "0", "0", "1", "0"],
			["", "222", "", "20", "0", "0", "1", "0"],
			["", "", "Ran", "30", "0", "0", "1", "0"],
			["", "", "Babylon", "40", "0", "0", "1", "0"]])
	var cat := _build([base, mod])
	assert_eq(cat.get_star_count(), 4, "three replaced, one added")
	assert_eq(cat.get_position(0).x, 10.0)
	assert_eq(cat.get_position(1).x, 20.0)
	assert_eq(cat.get_star_position("Ran"), Vector3(30, 0, 0))
	assert_eq(cat.get_star_position("Babylon"), Vector3(40, 0, 0))


func test_rows_in_one_source_are_never_merged() -> void:
	# p Eridani is a binary: two stars, one proper name, both in the same file.
	var path := _csv("a.csv", [["111", "", "p Eridani", "4.131", "0", "0", "6.2", "0"],
			["112", "", "p Eridani", "4.135", "0", "0", "6.2", "0"]])
	assert_eq(_build([path]).get_star_count(), 2)


func test_order_decides_which_source_wins() -> void:
	var a := _csv("a.csv", [["", "", "Ran", "1", "0", "0", "1", "0"]])
	var b := _csv("b.csv", [["", "", "Ran", "2", "0", "0", "1", "0"]])
	assert_eq(_build([a, b]).get_star_position("Ran"), Vector3(2, 0, 0))
	assert_eq(_build([b, a]).get_star_position("Ran"), Vector3(1, 0, 0))


func test_source_missing_columns_is_skipped_with_a_warning() -> void:
	var good := _csv("good.csv", [["", "", "Sol", "0", "0", "0", "4.85", "0.656"]])
	var bad := DIR.path_join("bad.csv")
	FileAccess.open(bad, FileAccess.WRITE).store_string("proper,x,y\nRan,1,2\n")
	var builder := StarCatalogBuilder.new()
	var cat := builder.build(PackedStringArray([good, bad, DIR.path_join("missing.csv")]))
	assert_eq(cat.get_star_count(), 1)
	assert_eq(builder.warnings.size(), 2, str(builder.warnings))


func test_write_then_read_round_trips() -> void:
	var cat := _build([_csv("a.csv", [["", "", "Sol", "1", "2", "3", "4.85", "0.656"]])])
	cat.key = "abc"
	var path := DIR.path_join("cat.stars")
	assert_eq(cat.write(path), OK)
	var back := StarCatalog.read(path, "abc")
	assert_not_null(back)
	assert_eq(back.buffer, cat.buffer)
	assert_eq(back.get_star_position("Sol"), cat.get_star_position("Sol"))
	assert_false(FileAccess.file_exists(path + ".tmp"), "temporary file renamed away")


func test_read_rejects_wrong_key_and_damaged_files() -> void:
	var cat := _build([_csv("a.csv", [["", "", "Sol", "1", "2", "3", "4.85", "0.656"]])])
	cat.key = "abc"
	var path := DIR.path_join("cat.stars")
	cat.write(path)
	assert_null(StarCatalog.read(path, "other"), "wrong key")
	assert_null(StarCatalog.read(DIR.path_join("none.stars"), "abc"), "missing file")
	var junk := DIR.path_join("junk.stars")
	FileAccess.open(junk, FileAccess.WRITE).store_string("not a catalogue")
	assert_null(StarCatalog.read(junk, "abc"), "not a catalogue")
	var bytes := FileAccess.get_file_as_bytes(path)
	var cut := DIR.path_join("cut.stars")
	FileAccess.open(cut, FileAccess.WRITE).store_buffer(bytes.slice(0, bytes.size() / 2))
	assert_null(StarCatalog.read(cut, "abc"), "truncated")
