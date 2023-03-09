extends Control

signal join_game(ip, port: int, player_name)
signal new_game(player_name, port: int)
signal set_resolution(resolution: Vector2i)

func _ready():
	if OS.has_environment("USERNAME"):
		$HBoxContainer/VBoxContainerOption/VBoxContainerNew/GridContainer/LineEditCallsign.text = OS.get_environment("USERNAME")
		$HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditCallsign.text = OS.get_environment("USERNAME")
	else:
		var desktop_path = OS.get_system_dir(0).replace("\\", "/").split("/")
		$HBoxContainer/VBoxContainerOption/VBoxContainerNew/GridContainer/LineEditCallsign.text = desktop_path[desktop_path.size() - 2]
		$HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditCallsign.text = desktop_path[desktop_path.size() - 2]
		

func close_all() -> void:
	for child in get_node("HBoxContainer/VBoxContainerOption").get_children():
		child.visible = false


func _on_button_new_game_pressed():
	close_all()
	$HBoxContainer/VBoxContainerOption/VBoxContainerNew.visible = true


func _on_button_join_game_pressed():
	close_all()
	$HBoxContainer/VBoxContainerOption/VBoxContainerJoin.visible = true


func _on_button_options_pressed():
	close_all()
	$HBoxContainer/VBoxContainerOption/VBoxContainerOption.visible = true


func _on_button_exit_desktop_pressed():
	get_tree().quit()


func _on_button_new_server_pressed():
	var port_string = $HBoxContainer/VBoxContainerOption/VBoxContainerNew/GridContainer/LineEditPort.text
	if not port_string.is_valid_int():
		print_debug(port_string, " is not a valid port")
		return
	var port = port_string.to_int()
	if not (port >= 1 and port <= 65535):
		print_debug("Error: ", port_string, " Not Valid Port")
		return
	var new_player_name = $HBoxContainer/VBoxContainerOption/VBoxContainerNew/GridContainer/LineEditCallsign.text
	if new_player_name == "":
		print_debug("Error: Not valid player name")
	new_game.emit(new_player_name, port)


func _on_button_join_server_pressed():
	var ip = $HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditIP.text
	var port_string = $HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditPort.text
	if not port_string.is_valid_int():
		print(port_string, " is not a valid port")
		return
	var port = port_string.to_int()
	if not (port >= 1 and port <= 65535):
		print("Error: ", port_string, " Not Valid Port")
		return
	var new_player_name = $HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditCallsign.text
	if new_player_name == "":
		print("Error: Not valid player name")
		return
	join_game.emit(ip, port, new_player_name)



func _on_option_button_item_selected(index):
	if index == 0:
		set_resolution.emit(Vector2i(0, 0))
	elif index == 1:
		set_resolution.emit(Vector2i(1280, 800))
	elif index == 2:
		set_resolution.emit(Vector2i(1920, 1080))
	elif index == 3:
		set_resolution.emit(Vector2i(2560, 1440))


func _on_option_button_v_sync_item_selected(index):
	print_debug("Setting vsync mode: ", index)
	DisplayServer.window_set_vsync_mode(index)


func _on_option_button_window_mode_item_selected(index):
	print_debug("Setting window mode: ", index)
	DisplayServer.window_set_mode(index)
