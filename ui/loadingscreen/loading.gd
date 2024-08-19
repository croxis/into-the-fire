extends Control

var loadpath
var parent_node: Node
var make_active := false
var callback

@onready
var progress = $CenterContainer/VBoxContainer/ProgressBar

func _process(_delta):
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
			Logger.log(["Scene loaded"], Logger.MessageType.INFO)
			if callback:
				callback.call()
				callback = null
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			Logger.log(["Scene load failed"], Logger.MessageType.ERROR)
		elif status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			Logger.log(["Scene invalid"], Logger.MessageType.ERROR)
	

func load_scene(path, node: Node, make_active_scene: bool, show_load_screen = false, cback = null):
	Logger.log(["Loading scene: ", path, " ", "make_active: ", make_active_scene, " show_load_screen: ", show_load_screen], Logger.MessageType.INFO)
	ResourceLoader.load_threaded_request(path)
	loadpath = path
	parent_node = node
	make_active = make_active_scene
	if cback:
		callback = cback
	# This extra check is for the main menu showing the loading screen, but the galaxy is prepping in the background
	if show_load_screen:
		visible = show_load_screen


func _on_galaxy_load_scene(path, node, make_active_scene, show_load_screen, cback):
	load_scene(path, node, make_active_scene, show_load_screen, cback)
