extends Node
## Autoload "Content": the game's ContentRegistry, filled from the manifests below
## at startup.
##
## Later, mod pcks will add their manifests here as they load (design doc:
## packaging). For now the Babylon 5 content is the only manifest.

const MANIFESTS: PackedStringArray = [
	"res://content/babylon5.cfg",
]

var registry := ContentRegistry.new()
## Every ship scene, loading on worker threads from startup and then kept (in
## Godot's resource cache, while this holds them): the first instantiate of a
## ship would otherwise read it from disk, about 300 ms for a Starfury, a stall
## that froze a client's ticks at its first launch and the server's at the
## first launch it built. Server and clients alike.
var _ships: SceneBatchLoader
var _ships_logged := false


func _enter_tree() -> void:
	for manifest in MANIFESTS:
		var count := registry.load_manifest(manifest)
		Log.log(["Content: ", count, " entries from ", manifest], Log.MessageType.INFO)
	var paths := PackedStringArray()
	for id in registry.ids(&"ship"):
		# Resolved paths: ContentRegistry.load_scene looks a load in flight up by it.
		paths.append(ResourceUID.ensure_path(registry.path_of(id)))
	_ships = SceneBatchLoader.new(paths, false)  # One worker: it is in no hurry.


func _process(_delta: float) -> void:
	if _ships_logged:
		return
	_ships.poll()
	if _ships.is_done():
		_ships_logged = true
		Log.log(["Content: ", _ships.paths.size() - _ships.failed.size(), " ship scenes preloaded"],
				Log.MessageType.INFO)


## True once every ship scene is loaded and kept (see _ships).
func ships_preloaded() -> bool:
	return _ships != null and _ships.is_done()


## Shorthands for the registry, so callers can write Content.instantiate(id).
func instantiate(id: StringName) -> Node:
	return registry.instantiate(id)


func path_of(id: StringName) -> String:
	return registry.path_of(id)


func has(id: StringName) -> bool:
	return registry.has(id)
