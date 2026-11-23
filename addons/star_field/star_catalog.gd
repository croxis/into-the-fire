class_name StarCatalog
extends RefCounted
## Every star's position, colour and absolute magnitude, already laid out as a
## MultiMesh buffer, plus a proper-name index. Plain data: no rendering is
## needed, so servers can use it for navigation as well.
##
## Positions are in parsecs. They are stored as 32-bit floats, as precise as
## the catalogue data itself (about 1e-4 pc for most stars).
##
## Files are written by [method write] and read by [method read]. They hold
## numbers and strings only, never objects, so a damaged or tampered file in
## user:// can only fail to load, not run code (unlike a .res file).

## Bump when the buffer layout or what the builder computes changes, so cached
## and shipped files built by older code are rebuilt.
const FORMAT_VERSION := 1
## MultiMesh TRANSFORM_3D (12 floats), colour (4) and custom data (4).
const FLOATS_PER_STAR := 20
const _MAGIC := "STRC"
const _COLOR := 12
const _CUSTOM := 16

## Identifies the sources this catalogue was built from (see StarCatalogCache.key_for).
var key := ""
var buffer := PackedFloat32Array()
## Proper name -> star index.
var names := {}

var _multimeshes := {}  # Mesh -> MultiMesh, shared by every star field showing this catalogue.


func get_star_count() -> int:
	return buffer.size() / FLOATS_PER_STAR


func get_position(index: int) -> Vector3:
	var i := index * FLOATS_PER_STAR
	return Vector3(buffer[i + 3], buffer[i + 7], buffer[i + 11])


func get_color(index: int) -> Color:
	var i := index * FLOATS_PER_STAR + _COLOR
	return Color(buffer[i], buffer[i + 1], buffer[i + 2], buffer[i + 3])


func get_absolute_magnitude(index: int) -> float:
	return buffer[index * FLOATS_PER_STAR + _CUSTOM]


## Index of the star with this proper name, or -1.
func find(proper_name: String) -> int:
	return names.get(proper_name, -1)


## Position of the star with this proper name, or null if there is none.
func get_star_position(proper_name: String) -> Variant:
	var index := find(proper_name)
	return null if index < 0 else get_position(index)


## A MultiMesh of every star drawn with [param mesh]. Made once and shared, so
## many star fields cost one buffer. Call from the main thread.
func get_multimesh(mesh: Mesh) -> MultiMesh:
	if not _multimeshes.has(mesh):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = get_star_count()
		mm.buffer = buffer
		_multimeshes[mesh] = mm
	return _multimeshes[mesh]


## Saves to [param path] by writing a temporary file and renaming it, so a
## reader in another process sees either no file or a complete one.
func write(path: String) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var data := buffer.to_byte_array()
	var packed := data.compress(FileAccess.COMPRESSION_ZSTD)
	f.store_buffer(_MAGIC.to_ascii_buffer())
	f.store_32(FORMAT_VERSION)
	f.store_pascal_string(key)
	f.store_32(data.size())
	f.store_32(packed.size())
	f.store_buffer(packed)
	f.store_32(names.size())
	for proper_name: String in names:
		f.store_pascal_string(proper_name)
		f.store_32(names[proper_name])
	var err := f.get_error()
	f.close()
	if err != OK:
		DirAccess.remove_absolute(tmp)
		return err
	return DirAccess.rename_absolute(tmp, path)


## Loads a file written by [method write], or returns null if it is missing,
## damaged, from another format version or built from other sources than
## [param expected_key]. Lengths are checked before anything is decoded, so a
## bad file is turned down without engine errors.
static func read(path: String, expected_key: String) -> StarCatalog:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 16:
		return null
	if f.get_buffer(4).get_string_from_ascii() != _MAGIC or f.get_32() != FORMAT_VERSION:
		return null
	if f.get_pascal_string() != expected_key:
		return null
	var raw_size := f.get_32()
	var packed_size := f.get_32()
	if raw_size % (FLOATS_PER_STAR * 4) != 0 or packed_size > f.get_length() - f.get_position():
		return null
	var packed := f.get_buffer(packed_size)
	var data := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if data.size() != raw_size:
		return null
	var cat := StarCatalog.new()
	cat.key = expected_key
	cat.buffer = data.to_float32_array()
	var count := cat.get_star_count()
	var name_count := f.get_32()
	for i in name_count:
		if f.eof_reached():
			return null
		var proper_name := f.get_pascal_string()
		var index := f.get_32()
		if index >= count:
			return null
		cat.names[proper_name] = index
	if f.eof_reached() or f.get_error() not in [OK, ERR_FILE_EOF]:
		return null
	return cat
