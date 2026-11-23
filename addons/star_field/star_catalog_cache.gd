class_name StarCatalogCache
extends RefCounted
## Finds the StarCatalog for a list of sources without parsing CSVs when it can:
##
## 1. the shipped catalogue, if it was built from exactly these sources;
## 2. otherwise a catalogue cached in [member cache_dir] by an earlier run;
## 3. otherwise it builds one and caches it.
##
## Other cache files are then deleted, so only the one in use is kept.
## A cache is identified by [method key_for]: the format version plus each
## source's path and content hash. Editing a CSV, or a mod adding, removing or
## reordering sources, gives a new key. Content is hashed rather than file times
## compared, because times are not reliable inside exported packs.
##
## Safe to run on a worker thread.

const CACHE_PREFIX := "stars_"
const EXTENSION := ".stars"

var cache_dir: String
## Pre-built catalogue shipped with the game, or "" for none.
var shipped_path: String
## Whether the last [method load_or_build] had to build from the CSVs.
var built := false
## Problems from the last [method load_or_build].
var warnings := PackedStringArray()


func _init(p_cache_dir := "user://star_field", p_shipped_path := "") -> void:
	cache_dir = p_cache_dir
	shipped_path = p_shipped_path


static func key_for(sources: PackedStringArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("star_field/%d\n" % StarCatalog.FORMAT_VERSION).to_utf8_buffer())
	for path in sources:
		# A missing file hashes as "", so it still has its place in the key.
		ctx.update(("%s\n%s\n" % [path, FileAccess.get_sha256(path)]).to_utf8_buffer())
	return ctx.finish().hex_encode()


## Builds the catalogue for [param sources] and writes it to [param path], for
## shipping with the game.
static func build_shipped(sources: PackedStringArray, path: String) -> Error:
	var builder := StarCatalogBuilder.new()
	var cat := builder.build(sources)
	for w in builder.warnings:
		push_warning("Star catalogue: " + w)
	cat.key = key_for(sources)
	return cat.write(path)


func cache_path(key: String) -> String:
	return cache_dir.path_join(CACHE_PREFIX + key.left(16) + EXTENSION)


func load_or_build(sources: PackedStringArray) -> StarCatalog:
	built = false
	warnings.clear()
	var key := key_for(sources)
	if not shipped_path.is_empty():
		var shipped := StarCatalog.read(shipped_path, key)
		if shipped:
			_delete_caches_except("")
			return shipped
	var path := cache_path(key)
	var cached := StarCatalog.read(path, key)
	if cached:
		_delete_caches_except(path.get_file())
		return cached
	var builder := StarCatalogBuilder.new()
	var cat := builder.build(sources)
	built = true
	warnings = builder.warnings
	cat.key = key
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var err := cat.write(path)
	if err != OK:
		warnings.append("%s: cannot write cache (%s)" % [path, error_string(err)])
	_delete_caches_except(path.get_file())
	return cat


## Deletes cached catalogues other than [param keep]. Temporary files are left
## alone: one may belong to another process (a server and a client started
## together) that is writing it right now.
func _delete_caches_except(keep: String) -> void:
	if not DirAccess.dir_exists_absolute(cache_dir):
		return
	for file in DirAccess.get_files_at(cache_dir):
		if file != keep and file.begins_with(CACHE_PREFIX) and file.ends_with(EXTENSION):
			DirAccess.remove_absolute(cache_dir.path_join(file))
