class_name SceneBatchLoader
extends RefCounted
## Loads several scenes at once on worker threads (with sub-threads, so their
## meshes, textures and scripts load in parallel too). Call [method poll] once
## a frame until [method is_done]; [member scenes] then holds every result.
##
## The scenes are also left in Godot's resource cache for as long as they are
## referenced, so later plain [code]load()[/code] calls for them are instant.
## Keep this object (or [member scenes]) until those calls are made.

## The paths to load, each once, in the order given.
var paths := PackedStringArray()
## Path -> PackedScene, or null for a path that failed. Filled as they finish.
var scenes := {}
## Paths that could not be loaded.
var failed := PackedStringArray()

var _pending := {}  # path -> progress 0..1
var _sub_threads := true


## [param sub_threads]: let each scene's meshes, textures and scripts load in
## parallel too (fast, for a loading screen). Off for loads in the background
## of play: main-thread loads of the same files then wait on it safely.
func _init(p_paths: PackedStringArray, sub_threads := true) -> void:
	_sub_threads = sub_threads
	for path in p_paths:
		if path in paths:
			continue
		paths.append(path)
		# Checked first: requesting a missing file prints engine errors.
		if not ResourceLoader.exists(path, "PackedScene") \
				or ResourceLoader.load_threaded_request(path, "PackedScene", sub_threads) != OK:
			_fail(path)
		else:
			_pending[path] = 0.0


func is_done() -> bool:
	return _pending.is_empty()


## Collects what has finished and returns the overall progress, 0 to 1.
func poll() -> float:
	var progress := [0.0]
	for path: String in _pending.keys():
		match ResourceLoader.load_threaded_get_status(path, progress):
			ResourceLoader.THREAD_LOAD_LOADED:
				var scene := ResourceLoader.load_threaded_get(path) as PackedScene
				_pending.erase(path)
				if scene:
					scenes[path] = scene
				else:
					_fail(path)
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				_pending[path] = progress[0]
			_:
				# Someone else collected it (ContentRegistry waits on a load in
				# flight rather than load() it). Take it from the cache, or, if
				# nothing kept it, ask for it again.
				if ResourceLoader.has_cached(path):
					_pending.erase(path)
					scenes[path] = ResourceLoader.load(path) as PackedScene
				elif ResourceLoader.load_threaded_request(path, "PackedScene", _sub_threads) != OK:
					_pending.erase(path)
					_fail(path)
	if paths.is_empty():
		return 1.0
	var total := float(paths.size() - _pending.size())
	for p: float in _pending.values():
		total += p
	return total / paths.size()


func _fail(path: String) -> void:
	failed.append(path)
	scenes[path] = null
