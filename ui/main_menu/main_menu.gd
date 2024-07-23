extends Control

signal join_game(ip, port: int, player_name: String, server_password: String, player_password: String)
signal new_game(game_name: String, player_name: String, port: int, server_password: String, player_password: String)
signal set_resolution(resolution: Vector2i)
signal set_taa(status: bool)
signal set_msaa(status: int)
signal set_ssaa(status: bool)


func _ready():	
	$HBoxContainer/VBoxContainerOption/VBoxContainerNew/GridContainer/LineEditCallsign.text = AppConfig.get_value("player", "name")
	$HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditCallsign.text = AppConfig.get_value("player", "name")
	
	$HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditIP.text = AppConfig.get_value("player", "ip")
	$HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditPort.text = str(AppConfig.get_value("player", "port"))
	$HBoxContainer/VBoxContainerOption/VBoxContainerNew/GridContainer/LineEditPort.text = str(AppConfig.get_value("player", "port"))
	
	var resolution := Vector2i(AppConfig.get_value("graphics", "resolution_x"), AppConfig.get_value("graphics", "resolution_y"))
	set_resolution.emit(resolution)
	for i in range(0, $HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButton.item_count):
		var text = $HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButton.get_item_text(i)
		if text.begins_with(str(resolution.x) + "x" + str(resolution.y)):
			$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButton.select(i)
			break
	
	#Disabled due to crashes when setting before everything is ready
	#DisplayServer.window_set_vsync_mode(config.get_value("graphics", "vsync"))
	$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButtonVSync.select(AppConfig.get_value("graphics", "vsync"))
	
	DisplayServer.window_set_mode(AppConfig.get_value("graphics", "windowed"))
	$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButtonWindowMode.select(AppConfig.get_value("graphics", "windowed"))
	
	set_taa.emit(AppConfig.get_value("graphics", "taa"))
	$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/CheckButtonTAA.button_pressed = AppConfig.get_value("graphics", "taa")
	
	set_msaa.emit(AppConfig.get_value("graphics", "msaa"))
	$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButtonMSAA.select(AppConfig.get_value("graphics", "msaa"))


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
	AppConfig.set_value("player", "name", new_player_name)
	AppConfig.set_value("player", "port", port)
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
	AppConfig.set_value("player", "name", new_player_name)
	AppConfig.set_value("player", "ip", ip)
	AppConfig.set_value("player", "port", port)
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
	
	AppConfig.set_value("graphics", "resolution_x", resolution.x)
	AppConfig.set_value("graphics", "resolution_y", resolution.y)
	set_resolution.emit(resolution)


func _on_option_button_v_sync_item_selected(index):
	print_debug("Setting vsync mode: ", index)
	AppConfig.set_value("graphics", "vsync", index)
	DisplayServer.window_set_vsync_mode(index)


func _on_option_button_window_mode_item_selected(index):
	print_debug("Setting window mode: ", index)
	AppConfig.set_value("graphics", "windowed", index)
	DisplayServer.window_set_mode(index)


func _on_check_button_taa_toggled(button_pressed):
	print_debug("Set tta: ", button_pressed)
	AppConfig.set_value("graphics", "taa", button_pressed)
	set_taa.emit(button_pressed)


func _on_option_button_msaa_item_selected(index):
	print_debug("Set msaa: ", index)
	AppConfig.set_value("graphics", "msaa", index)
	set_msaa.emit(index)

