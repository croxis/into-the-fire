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
## Ship scenes whose collision shapes are still to be built, one a frame:
## Jolt builds a concave hull shape the first time a body uses it (277 ms for
## Babylon 5's), a stall wherever the ship first appeared (a client's spawn,
## fog of war revealing it mid-flight). Built here, while the scenes are kept
## the shapes stay built, and adding the ship later costs next to nothing.
var _to_warm: Array[PackedScene] = []
var _warmed := false


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
	if _warmed:
		return
	if not _ships_logged:
		_ships.poll()
		if not _ships.is_done():
			return
		_ships_logged = true
		Log.log(["Content: ", _ships.paths.size() - _ships.failed.size(), " ship scenes preloaded"],
				Log.MessageType.INFO)
		for scene in _ships.scenes.values():
			if scene:
				_to_warm.append(scene)
		return
	if _to_warm.is_empty():
		_warmed = true
		Log.log(["Content: ship collision shapes built"], Log.MessageType.INFO)
		return
	_warm_shapes(_to_warm.pop_back())


## Has Jolt build every collision shape in [param scene]: each goes on a body in
## a space of its own, which is thrown away (the shapes stay built).
static func _warm_shapes(scene: PackedScene) -> void:
	var ship := scene.instantiate()
	var space := PhysicsServer3D.space_create()
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space)
	for holder in ship.find_children("*", "CollisionShape3D", true, false):
		var shape: Shape3D = (holder as CollisionShape3D).shape
		if shape:
			PhysicsServer3D.body_add_shape(body, shape.get_rid())
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)
	ship.free()


## True once every ship scene is loaded and kept (see _ships).
func ships_preloaded() -> bool:
	return _ships != null and _ships.is_done()


## True once every ship scene is loaded and its collision shapes built.
func ships_ready() -> bool:
	return _warmed


## Shorthands for the registry, so callers can write Content.instantiate(id).
func instantiate(id: StringName) -> Node:
	return registry.instantiate(id)


func path_of(id: StringName) -> String:
	return registry.path_of(id)


func has(id: StringName) -> bool:
	return registry.has(id)
