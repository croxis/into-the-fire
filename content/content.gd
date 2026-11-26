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
## Every ship scene, loaded and then kept, on the server and on clients: the
## first instantiate of a ship would otherwise read it from disk, about 300 ms
## for a Starfury, a stall that froze a client's ticks at its first launch and
## the server's at the first launch it built. Then each one's collision shapes
## are built: Jolt builds a concave hull shape the first time a body uses it
## (277 ms for Babylon 5's), a stall wherever the ship first appeared (a
## client's spawn, fog of war revealing it mid-flight). While the scenes are
## kept their shapes stay built, and adding the ship later costs next to nothing.
##
## One ship a frame, on the main thread, from the first frames after startup
## (the title screen, or a dedicated server starting). Not on worker threads:
## those raced the main thread for the same scripts as the game and the test
## runner started, and deadlocked or failed to parse a scene.
var _ships: Dictionary[StringName, PackedScene] = {}
var _to_load: Array[StringName] = []
var _to_warm: Array[PackedScene] = []
var _started := false
var _ready_logged := false


func _enter_tree() -> void:
	for manifest in MANIFESTS:
		var count := registry.load_manifest(manifest)
		Log.log(["Content: ", count, " entries from ", manifest], Log.MessageType.INFO)


func _process(_delta: float) -> void:
	if _ready_logged:
		return
	if not _started:
		_started = true
		_to_load = registry.ids(&"ship")
		return
	if not _to_load.is_empty():
		var id: StringName = _to_load.pop_back()
		var scene := registry.load_scene(id)
		if scene:
			_ships[id] = scene
			_to_warm.append(scene)
		return
	if not _to_warm.is_empty():
		_warm_shapes(_to_warm.pop_back())
		return
	_ready_logged = true
	Log.log(["Content: ", _ships.size(), " ship scenes loaded, collision shapes built"],
			Log.MessageType.INFO)


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
	return _started and _to_load.is_empty()


## True once every ship scene is loaded and its collision shapes built.
func ships_ready() -> bool:
	return _ready_logged


## Shorthands for the registry, so callers can write Content.instantiate(id).
func instantiate(id: StringName) -> Node:
	return registry.instantiate(id)


func path_of(id: StringName) -> String:
	return registry.path_of(id)


func has(id: StringName) -> bool:
	return registry.has(id)
