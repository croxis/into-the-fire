class_name StarCatalogService
extends Node
## Owns the star sources and the one StarCatalog loaded from them, shared by
## every StarField and by game code (for example navigation on a server).
## The plugin registers it as the [code]StarCatalogs[/code] autoload.
##
## Loading runs on a worker thread; [signal catalog_ready] is emitted on the
## main thread when it is done, and again whenever the sources change.
##
## Mods change the sources before or after loading:
## [codeblock]
## StarCatalogs.add_source("res://mods/my_mod/stars.csv")      # Add or correct stars.
## StarCatalogs.remove_source(StarCatalogService.DEFAULT_SOURCE) # Drop the real sky.
## StarCatalogs.set_sources(["res://mods/my_mod/galaxy.csv"])   # Replace everything.
## [/codeblock]
## A later source wins over an earlier one (see StarCatalogBuilder).

signal catalog_ready(catalog: StarCatalog)

const DEFAULT_SOURCE := "res://addons/star_field/databases/athyg_33_hyg_ids.reduced.csv"
## Built from [constant DEFAULT_SOURCE] (Project > Tools > Rebuild star catalogue).
const SHIPPED_CATALOG := "res://addons/star_field/databases/default.stars"

var cache_dir := "user://star_field"
var shipped_path := SHIPPED_CATALOG
## The loaded catalogue, or null until the first load finishes.
var catalog: StarCatalog

var _sources := PackedStringArray([DEFAULT_SOURCE])
var _requested := false
var _generation := 0
var _tasks := {}  # generation -> WorkerThreadPool task id


func get_sources() -> PackedStringArray:
	return _sources.duplicate()


func set_sources(sources: PackedStringArray) -> void:
	_sources = sources.duplicate()
	_sources_changed()


func add_source(path: String) -> void:
	_sources.append(path)
	_sources_changed()


func remove_source(path: String) -> void:
	var i := _sources.find(path)
	if i >= 0:
		_sources.remove_at(i)
		_sources_changed()


## Starts loading unless a catalogue is loaded or on its way. Cheap to call often.
func request() -> void:
	if _requested:
		return
	_requested = true
	_start()


func is_loading() -> bool:
	return _tasks.has(_generation)


func _sources_changed() -> void:
	if _requested:
		_start()  # Keep the current catalogue until the new one is ready.


func _start() -> void:
	_generation += 1
	var generation := _generation
	var sources := _sources.duplicate()
	var cache := StarCatalogCache.new(cache_dir, shipped_path)
	_tasks[generation] = WorkerThreadPool.add_task(func() -> void:
		var start := Time.get_ticks_msec()
		var result := cache.load_or_build(sources)
		_finished.call_deferred(generation, result, cache, Time.get_ticks_msec() - start),
		false, "Load star catalogue")


func _finished(generation: int, result: StarCatalog, cache: StarCatalogCache, msec: int) -> void:
	if not _tasks.has(generation):
		return  # Already waited for in _exit_tree.
	WorkerThreadPool.wait_for_task_completion(_tasks[generation])
	_tasks.erase(generation)
	for w in cache.warnings:
		push_warning("Star catalogue: " + w)
	if generation != _generation:
		return  # The sources changed while this one loaded.
	print_verbose("Star catalogue: %d stars %s in %d ms" % [result.get_star_count(),
			"built" if cache.built else "loaded", msec])
	catalog = result
	catalog_ready.emit(catalog)


func _exit_tree() -> void:
	# A task must be waited for; its result is no longer wanted.
	for generation in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[generation])
	_tasks.clear()
