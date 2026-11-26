class_name ContentRegistry
extends RefCounted
## Maps content IDs such as [code]b5:aurora_starfury[/code] to the resources that
## implement them.
##
## Game code asks for content by ID instead of by [code]res://[/code] path, so a
## mod can add or replace content without the code knowing where its files live.
## An ID is [code]namespace:name[/code], lowercase, using letters, digits and
## underscores. The namespace is the mod that owns it.
##
## Content is listed in manifests (ConfigFile, see [method load_manifest]).
## Registering an ID that already exists replaces it: later mods override earlier ones.

const _ID_PATTERN := "^[a-z0-9_]+:[a-z0-9_]+$"

## id (StringName) -> {"kind": StringName, "path": String, "source": String}
var _entries := {}
var _id_regex := RegEx.create_from_string(_ID_PATTERN)


static func is_valid_id(id: StringName) -> bool:
	return RegEx.create_from_string(_ID_PATTERN).search(id) != null


## Adds or replaces [param id]. Returns false (and registers nothing) for a
## malformed ID or an empty path.
func register(id: StringName, kind: StringName, path: String, source := "") -> bool:
	if _id_regex.search(id) == null:
		push_error("Content: malformed id '%s' (expected namespace:name)" % id)
		return false
	if path.is_empty():
		push_error("Content: '%s' has no path" % id)
		return false
	if _entries.has(id):
		Log.log(["Content: ", id, " overridden by ", source if source else path], Log.MessageType.INFO)
	_entries[id] = {"kind": kind, "path": path, "source": source}
	return true


## Loads a manifest file:
## [codeblock]
## [meta]
## namespace="b5"
##
## [ship]
## aurora_starfury="uid://..."
## [/codeblock]
## Every section except [code]meta[/code] is a kind; each key is a name in the
## manifest's namespace. Returns the number of entries registered.
func load_manifest(manifest_path: String) -> int:
	var config := ConfigFile.new()
	var err := config.load(manifest_path)
	if err != OK:
		push_error("Content: cannot read manifest %s (error %d)" % [manifest_path, err])
		return 0
	var namespace_name: String = config.get_value("meta", "namespace", "")
	if namespace_name.is_empty():
		push_error("Content: manifest %s has no [meta] namespace" % manifest_path)
		return 0
	var count := 0
	for kind in config.get_sections():
		if kind == "meta":
			continue
		for content_name in config.get_section_keys(kind):
			var id := StringName(namespace_name + ":" + content_name)
			if register(id, StringName(kind), str(config.get_value(kind, content_name)), manifest_path):
				count += 1
	return count


func has(id: StringName) -> bool:
	return _entries.has(id)


## The resource path for [param id], or "" if unknown.
func path_of(id: StringName) -> String:
	if not _entries.has(id):
		push_error("Content: unknown id '%s'" % id)
		return ""
	return _entries[id]["path"]


func get_kind(id: StringName) -> StringName:
	return _entries[id]["kind"] if _entries.has(id) else &""


## All registered IDs, optionally only those of one [param kind], sorted.
func ids(kind: StringName = &"") -> Array[StringName]:
	var result: Array[StringName] = []
	for id in _entries:
		if kind == &"" or _entries[id]["kind"] == kind:
			result.append(id)
	# StringName.sort() orders by internal pointer, so compare as Strings.
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result


## Loads the scene for [param id], or null if it is unknown or not a scene.
func load_scene(id: StringName) -> PackedScene:
	var path := path_of(id)
	if path.is_empty():
		return null
	var scene: PackedScene
	# Loading in the background already (Content preloads ships): wait for that
	# load the documented way. A plain load() of a file in flight on a worker
	# thread can deadlock the main thread.
	var real_path := ResourceUID.ensure_path(path)
	if ResourceLoader.load_threaded_get_status(real_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		scene = ResourceLoader.load_threaded_get(real_path) as PackedScene
	else:
		scene = load(path) as PackedScene
	if scene == null:
		push_error("Content: '%s' (%s) is not a scene" % [id, path])
	return scene


## Instantiates the scene for [param id], or null.
func instantiate(id: StringName) -> Node:
	var scene := load_scene(id)
	return scene.instantiate() if scene else null
