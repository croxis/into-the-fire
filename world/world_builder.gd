class_name WorldBuilder
extends RefCounted
## Server: builds a world into a Galaxy from where it starts: a scenario today,
## a versioned save later (both are meant to feed this one path). In order:
## check it, create its factions and ID counters, load every scene it needs,
## add its systems, place its ships and crews, then emit built.

## The world is in place: systems, ships and crews.
signal built()

var _galaxy: Galaxy
var _scenario: Scenario
## Keeps the loaded scenes in Godot's cache until populate() has instanced the
## ships from them (a SceneBatchLoader, or a dictionary of scenes).
var _scenes: Variant


func _init(galaxy: Galaxy) -> void:
	_galaxy = galaxy


## Starts building from [param scenario]. [param load_scenes] loads paths and
## then calls back with an object holding them in [code]scenes[/code] (path ->
## PackedScene): the loading screen, or load_now. Returns false, building
## nothing, when the scenario is invalid.
func start_scenario(scenario: Scenario, load_scenes: Callable) -> bool:
	var errors := ScenarioLoader.validate(scenario, Content.registry)
	if not errors.is_empty():
		Log.log(["Scenario ", scenario.resource_path, " is invalid: ", "; ".join(errors)],
				Log.MessageType.ERROR)
		return false
	_scenario = scenario
	_galaxy.factions = ScenarioLoader.build_factions(scenario)
	_galaxy.ids = WorldIds.new()
	# Every system and ship scene at once, on worker threads, so populate()
	# later instantiates from the cache instead of reading files on this thread.
	load_scenes.call(ScenarioLoader.scene_paths(scenario, Content.registry), _on_scenes_loaded)
	return true


## Loads [param paths] now, on this thread, then calls [param done]: for when
## no loading screen is there to do it in the background (unit tests). Plain
## load(), not threaded requests waited on, which can deadlock this thread.
static func load_now(paths: PackedStringArray, done: Callable) -> void:
	var scenes := {}
	for path in paths:
		scenes[path] = load(path) as PackedScene
	done.call({"scenes": scenes})


func _on_scenes_loaded(batch: Variant) -> void:
	_scenes = batch
	var scenes: Dictionary = batch.scenes
	var systems := {}
	for id in _scenario.systems:
		var scene := scenes.get(Content.path_of(id)) as PackedScene
		if scene == null:
			Log.log(["Scenario system ", id, " failed to load"], Log.MessageType.ERROR)
			continue
		var system: System = scene.instantiate()
		_galaxy.zones.add_system(system)
		systems[id] = system
	ScenarioLoader.populate(_scenario, Content.registry, _galaxy.factions, systems, _galaxy.ids,
			_galaxy.multiplayer.get_unique_id())
	_scenes = null  # Placed ships hold their own references now.
	built.emit()
