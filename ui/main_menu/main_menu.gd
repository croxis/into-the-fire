extends Control

signal join_game(ip, port: int, player_name: String, server_password: String, player_password: String)
signal new_game(game_name: String, player_name: String, port: int, server_password: String, player_password: String)
signal set_resolution(resolution: Vector2i)
signal set_taa(status: bool)
signal set_msaa(status: int)
signal set_ssaa(status: bool)


func _ready():
	var player_name := ""
	if OS.has_environment("USERNAME"):
		player_name = OS.get_environment("USERNAME")
	else:
		var desktop_path = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).replace("\\", "/").split("/")
		player_name = desktop_path[desktop_path.size() - 2]

	$HBoxContainer/VBoxContainerOption/VBoxContainerNew/GridContainer/LineEditCallsign.text = PlayerConfig.get_config("player", "name", player_name)
	$HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditCallsign.text = PlayerConfig.get_config("player", "name", player_name)
	
	$HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditIP.text = PlayerConfig.get_config("player", "ip", "127.0.0.1")
	$HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditPort.text = str(PlayerConfig.get_config("player", "port", 2258))
	$HBoxContainer/VBoxContainerOption/VBoxContainerNew/GridContainer/LineEditPort.text = str(PlayerConfig.get_config("player", "port", 2258))
	
	var resolution := Vector2i(PlayerConfig.get_config("graphics", "resolution_x", 0), PlayerConfig.get_config("graphics", "resolution_y", 0))
	set_resolution.emit(resolution)
	for i in range(0, $HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButton.item_count):
		var text = $HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButton.get_item_text(i)
		if text.begins_with(str(resolution.x) + "x" + str(resolution.y)):
			$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButton.select(i)
			break
	
	#Disabled due to crashes when setting before everything is ready
	#DisplayServer.window_set_vsync_mode(config.get_value("graphics", "vsync"))
	$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButtonVSync.select(PlayerConfig.get_config("graphics", "vsync", 0))
	
	DisplayServer.window_set_mode(PlayerConfig.get_config("graphics", "windowed", 0))
	$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButtonWindowMode.select(PlayerConfig.get_config("graphics", "windowed", 0))
	
	set_taa.emit(PlayerConfig.get_config("graphics", "taa", 0))
	$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/CheckButtonTAA.button_pressed = PlayerConfig.get_config("graphics", "taa", 0)
	
	set_msaa.emit(PlayerConfig.get_config("graphics", "msaa", 0))
	$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButtonMSAA.select(PlayerConfig.get_config("graphics", "msaa", 0))


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
	var game_name = $HBoxContainer/VBoxContainerOption/VBoxContainerNew/GridContainer/LineEditGameName.text
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
		return
	var server_pass = $HBoxContainer/VBoxContainerOption/VBoxContainerNew/GridContainer/LineEditServerPass.text
	var player_pass = $HBoxContainer/VBoxContainerOption/VBoxContainerNew/GridContainer/LineEditPlayerPass.text
	PlayerConfig.set_config("player", "name", new_player_name)
	PlayerConfig.set_config("player", "port", port)
	new_game.emit(game_name, new_player_name, port, server_pass, player_pass)


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
	var server_pass = $HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditServerPass.text
	var player_pass = $HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditPlayerPass.text
	PlayerConfig.set_config("player", "name", new_player_name)
	PlayerConfig.set_config("player", "ip", ip)
	PlayerConfig.set_config("player", "port", port)
	join_game.emit(ip, port, new_player_name, server_pass, player_pass)


func _on_option_button_item_selected(index):
	print_debug($HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButton.get_item_text(index))
	var resolution := Vector2i(0, 0)
	if index == 0:
		resolution = Vector2i(0, 0)
	elif index == 1:
		resolution = Vector2i(1280, 800)
	elif index == 2:
		resolution = Vector2i(1920, 1080)
	elif index == 3:
		resolution = Vector2i(2560, 1440)
	
	PlayerConfig.set_config("graphics", "resolution_x", resolution.x)
	PlayerConfig.set_config("graphics", "resolution_y", resolution.y)
	set_resolution.emit(resolution)


func _on_option_button_v_sync_item_selected(index):
	print_debug("Setting vsync mode: ", index)
	PlayerConfig.set_config("graphics", "vsync", index)
	DisplayServer.window_set_vsync_mode(index)


func _on_option_button_window_mode_item_selected(index):
	print_debug("Setting window mode: ", index)
	PlayerConfig.set_config("graphics", "windowed", index)
	DisplayServer.window_set_mode(index)


func _on_check_button_taa_toggled(button_pressed):
	print_debug("Set tta: ", button_pressed)
	PlayerConfig.set_config("graphics", "taa", button_pressed)
	set_taa.emit(button_pressed)


func _on_option_button_msaa_item_selected(index):
	print_debug("Set msaa: ", index)
	PlayerConfig.set_config("graphics", "msaa", index)
	set_msaa.emit(index)
