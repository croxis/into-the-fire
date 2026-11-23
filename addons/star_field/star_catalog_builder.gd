class_name StarCatalogBuilder
extends RefCounted
## Builds a StarCatalog from CSV star lists (the athyg / HYG column names).
##
## Sources are read in order. A star in a later source replaces a star from an
## earlier source that shares any of its ids (Gaia, Hipparcos or HYG number, or
## proper name); otherwise it is added. Rows within one source are never merged. A mod can therefore add stars, correct them, or name
## a catalogue star by listing it again.
##
## Safe to run on a worker thread: it only reads files and fills arrays.

## Columns a source must have; [constant ID_COLUMNS] are optional.
const REQUIRED_COLUMNS: Array[String] = ["x", "y", "z", "absmag", "ci"]
const ID_COLUMNS: Array[String] = ["gaia", "hip", "hyg", "proper"]

## Problems found during the last [method build], one line each.
var warnings := PackedStringArray()

var _buffer := PackedFloat32Array()
var _count := 0
var _ids := {}  # "column:value" -> star index


func build(sources: PackedStringArray) -> StarCatalog:
	warnings.clear()
	_buffer = PackedFloat32Array()
	_count = 0
	_ids.clear()
	for path in sources:
		_read_source(path)
	_buffer.resize(_count * StarCatalog.FLOATS_PER_STAR)
	var cat := StarCatalog.new()
	cat.buffer = _buffer
	for id: String in _ids:
		if id.begins_with("proper:"):
			cat.names[id.substr(7)] = _ids[id]
	return cat


func _read_source(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		warnings.append("%s: cannot open (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	var header := f.get_csv_line()
	var col := {}
	for i in header.size():
		col[header[i].strip_edges()] = i
	var missing := REQUIRED_COLUMNS.filter(func(c: String) -> bool: return not col.has(c))
	if not missing.is_empty():
		warnings.append("%s: missing columns %s, skipped" % [path, ", ".join(PackedStringArray(missing))])
		return
	var id_cols := ID_COLUMNS.filter(func(c: String) -> bool: return col.has(c))
	var x: int = col.x
	var y: int = col.y
	var z: int = col.z
	var absmag: int = col.absmag
	var ci: int = col.ci
	var width := header.size()
	var line := 1
	# Ids from this file join the lookup only once it is read: rows only replace
	# stars of earlier files, and rows in one file are always separate stars
	# (a binary such as p Eridani has one proper name for two stars).
	var file_ids := {}
	while not f.eof_reached():
		var row := f.get_csv_line()
		line += 1
		if row.size() <= 1:
			continue  # Blank line (usually the last).
		if row.size() < width:
			warnings.append("%s:%d: %d of %d columns, skipped" % [path, line, row.size(), width])
			continue
		var index := _find(row, id_cols, col)
		if index < 0:
			index = _count
			_count += 1
			if _buffer.size() < _count * StarCatalog.FLOATS_PER_STAR:
				_buffer.resize(maxi(_buffer.size() * 2, 1024 * StarCatalog.FLOATS_PER_STAR))
		for c: String in id_cols:
			var value := row[col[c]]
			if not value.is_empty():
				file_ids[c + ":" + value] = index
		_set_star(index, Vector3(row[x].to_float(), row[y].to_float(), row[z].to_float()),
				temperature_color(row[ci].to_float()), row[absmag].to_float())
	_ids.merge(file_ids, true)


## The earlier star this row describes, or -1.
func _find(row: PackedStringArray, id_cols: Array, col: Dictionary) -> int:
	for c: String in id_cols:
		var value := row[col[c]]
		if not value.is_empty() and _ids.has(c + ":" + value):
			return _ids[c + ":" + value]
	return -1


func _set_star(index: int, position: Vector3, color: Color, absolute_magnitude: float) -> void:
	var i := index * StarCatalog.FLOATS_PER_STAR
	# Identity basis; the transform's rows each end with one origin component.
	var t := [1.0, 0.0, 0.0, position.x, 0.0, 1.0, 0.0, position.y, 0.0, 0.0, 1.0, position.z,
			color.r, color.g, color.b, color.a, absolute_magnitude, 0.0, 0.0, 0.0]
	for k in StarCatalog.FLOATS_PER_STAR:
		_buffer[i + k] = t[k]


## Star colour from its B-V colour index.
## Colour index to temperature: https://en.wikipedia.org/wiki/Color_index (Ballesteros);
## temperature to RGB: https://tannerhelland.com/2012/09/18/convert-temperature-rgb-algorithm-code.html
static func temperature_color(color_index: float) -> Color:
	var temperature := 4600.0 * ((1.0 / (0.92 * color_index + 1.7)) + (1.0 / (0.92 * color_index + 0.62)))
	var t := clampf(temperature, 1000.0, 40000.0) / 100.0
	var red := 255.0
	var green: float
	var blue: float
	if t > 66.0:
		red = clampf(329.698727446 * pow(t - 60.0, -0.1332047592), 0.0, 255.0)
		green = clampf(288.1221695283 * pow(t - 60.0, -0.0755148492), 0.0, 255.0)
	else:
		green = clampf(99.4708025861 * log(t) - 161.1195681661, 0.0, 255.0)
	if t >= 66.0:
		blue = 255.0
	elif t <= 19.0:
		blue = 0.0
	else:
		blue = clampf(138.5177312231 * log(t - 10.0) - 305.0447927307, 0.0, 255.0)
	return Color(red / 255.0, green / 255.0, blue / 255.0)
