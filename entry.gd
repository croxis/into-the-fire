extends Node

var _dedicated_server := false

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		$MainMenu.visible = not $MainMenu.visible


func _ready():
	var arguments = {}
	for argument in OS.get_cmdline_args():
		if argument.find("=") > -1:
			var key_value = argument.split("=")
			arguments[key_value[0].lstrip("--")] = key_value[1]
		else:
			arguments[argument.lstrip("--")] = 1
	print("Arguments: ", arguments)
	if ("server" in arguments || OS.has_feature("dedicated_server")):
		if "port" in arguments:
			$network.host_server(arguments["port"])
		else:
			$network.host_server()
		$network.player_name = "Server"
		_dedicated_server = true
	else:
		#Set window size here
		get_tree().get_root().size = DisplayServer.window_get_real_size()
		$loading.load_scene("res://title_screen.tscn")


func end_title_sequence() -> void:
	print("start end")
	if get_parent().has_node("title screen"):
		print("ending title")
		get_parent().get_node("title screen").queue_free()
	$MainMenu.visible = false
	# Hack until we figure out what we are doing
	$Galaxy.player_enter_system("test_system")


func _process(delta):
	if not _dedicated_server:
		Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'FPS', 'value': "FPS: " + str(Performance.get_monitor(Performance.TIME_FPS)) })
		Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Physics Time', 'value': str(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) / 1000.0) + " ms" })
		Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Objects', 'value': str(Performance.get_monitor(Performance.OBJECT_COUNT)) + " objects" })
		Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Objects Frame', 'value': str(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)) + " objects in frame" })
		Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Primatives Frame', 'value': str(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) + " primatives in frame" })
		Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Draws', 'value': str(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)) + " draws" })
		Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Video Mem', 'value': str(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0) + " MB" })
		Debug.update_widget('DebugBenchmark:TextListBenchmark.add_label', { 'name': 'Texture Mem', 'value': str(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0) + " MB texture" })


func _on_network_connection_succeeded():
	end_title_sequence()