extends Control

var loadpath
var parent_node: Node
var make_active := false

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
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			print("I dead")
		elif status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			print("I invalid dead")


func load_scene(path, node: Node, make_active_scene: bool, show_load_screen = false):
	print_debug("Loading screen: ", path, " ", "make_active: ", make_active_scene, " show_load_screen: ", show_load_screen)
	ResourceLoader.load_threaded_request(path)
	loadpath = path
	parent_node = node
	make_active = make_active_scene
	visible = show_load_screen
