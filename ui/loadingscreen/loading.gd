extends Control

var loadpath
var parent_node: Node
var make_active := false
var callback
var _batch: SceneBatchLoader
var _batch_callback: Callable

@onready
var progress = $CenterContainer/VBoxContainer/ProgressBar

func _process(_delta):
	if _batch:
		_poll_batch()
	if loadpath:
		var progressmeter = []
		var status = ResourceLoader.load_threaded_get_status(loadpath, progressmeter)
		Debug.update_widget('LoaderDebugContainer:TextListLoad.add_label', {'name': 'load_counter', 'value': str(progressmeter[0] * 100.0)})
		progress.value = progressmeter[0] * 100.0
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var resource:Resource = ResourceLoader.load_threaded_get(loadpath)
			var new_scene = resource.instantiate()
			parent_node.add_child(new_scene)
			if make_active:
				get_tree().current_scene = new_scene
			loadpath = null  
			visible = false
			Debug.update_widget('LoaderDebugContainer:TextListLoad.remove_label', {'name': 'load_counter'})
			Log.log(["Scene loaded"], Log.MessageType.INFO)
			if callback:
				# Clear first: the callback may start the next load, with its own callback.
				var finished = callback
				callback = null
				finished.call()
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			Log.log(["Scene load failed"], Log.MessageType.ERROR)
		elif status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			Log.log(["Scene invalid"], Log.MessageType.ERROR)
	

func load_scene(path, node: Node, make_active_scene: bool, show_load_screen = false, cback = null):
	Log.log(["Loading scene: ", path, " ", "make_active: ", make_active_scene, " show_load_screen: ", show_load_screen], Log.MessageType.INFO)
	ResourceLoader.load_threaded_request(path)
	loadpath = path
	parent_node = node
	make_active = make_active_scene
	if cback:
		callback = cback
	# This extra check is for the main menu showing the loading screen, but the galaxy is prepping in the background
	if show_load_screen:
		visible = show_load_screen


## Loads [param paths] together on worker threads and shows their combined
## progress; [param done] gets the finished SceneBatchLoader.
func load_scenes(paths: PackedStringArray, done: Callable) -> void:
	Log.log(["Loading ", paths.size(), " scenes"], Log.MessageType.INFO)
	_batch = SceneBatchLoader.new(paths)
	_batch_callback = done
	visible = true


func _poll_batch() -> void:
	progress.value = _batch.poll() * 100.0
	if not _batch.is_done():
		return
	var batch := _batch
	var done := _batch_callback
	_batch = null
	_batch_callback = Callable()
	visible = false
	for path in batch.failed:
		Log.log(["Scene load failed: ", path], Log.MessageType.ERROR)
	Log.log(["Scenes loaded"], Log.MessageType.INFO)
	done.call(batch)

