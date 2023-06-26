extends Control

signal join_game(ip, port: int, player_name)
signal new_game(player_name, port: int)
signal set_resolution(resolution: Vector2i)
signal set_taa(status: bool)
signal set_msaa(status: int)
signal set_ssaa(status: bool)

var config: ConfigFile
var CONFIG_PATH := "user://config.cfg"

func _ready():
	var player_name := ""
	if OS.has_environment("USERNAME"):
		player_name = OS.get_environment("USERNAME")
	else:
		var desktop_path = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).replace("\\", "/").split("/")
		player_name = desktop_path[desktop_path.size() - 2]
	
	config = ConfigFile.new()
	
	# Load data from a file.
	var err = config.load(CONFIG_PATH)
	# If the file didn't load, ignore it.
	if err != OK:
		config.set_value("player", "name", player_name)
		config.set_value("player", "ip", "127.0.0.1")
		config.set_value("player", "port", 2258)
		config.set_value("graphics", "resolution_x", 0)
		config.set_value("graphics", "resolution_y", 0)
		config.set_value("graphics", "vsync", 0)
		config.set_value("graphics", "windowed", 0)
		config.set_value("graphics", "taa", 0)
		config.set_value("graphics", "msaa", 0)
		config.save(CONFIG_PATH)
	
	$HBoxContainer/VBoxContainerOption/VBoxContainerNew/GridContainer/LineEditCallsign.text = config.get_value("player", "name")
	$HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditCallsign.text = config.get_value("player", "name")
	
	$HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditIP.text = config.get_value("player", "ip")
	$HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditPort.text = str(config.get_value("player", "port"))
	$HBoxContainer/VBoxContainerOption/VBoxContainerNew/GridContainer/LineEditPort.text = str(config.get_value("player", "port"))
	
	var resolution := Vector2i(config.get_value("graphics", "resolution_x"), config.get_value("graphics", "resolution_y"))
	set_resolution.emit(resolution)
	for i in range(0, $HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButton.item_count):
		var text = $HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButton.get_item_text(i)
		if text.begins_with(str(resolution.x) + "x" + str(resolution.y)):
			$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButton.select(i)
			break
	
	#Disabled due to crashes when setting before everything is ready
	#DisplayServer.window_set_vsync_mode(config.get_value("graphics", "vsync"))
	$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButtonVSync.select(config.get_value("graphics", "vsync"))
	
	DisplayServer.window_set_mode(config.get_value("graphics", "windowed"))
	$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButtonWindowMode.select(config.get_value("graphics", "windowed"))
	
	set_taa.emit(config.get_value("graphics", "taa"))
	$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/CheckButtonTAA.button_pressed = config.get_value("graphics", "taa")
	
	set_msaa.emit(config.get_value("graphics", "msaa"))
	$HBoxContainer/VBoxContainerOption/VBoxContainerOption/GridContainer/OptionButtonMSAA.select(config.get_value("graphics", "msaa"))


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
		return
	config.set_value("player", "name", new_player_name)
	config.set_value("player", "port", port)
	config.save(CONFIG_PATH)
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
	config.set_value("player", "name", new_player_name)
	config.set_value("player", "ip", ip)
	config.set_value("player", "port", port)
	config.save(CONFIG_PATH)
	join_game.emit(ip, port, new_player_name)


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
	
	config.set_value("graphics", "resolution_x", resolution.x)
	config.set_value("graphics", "resolution_y", resolution.y)
	config.save(CONFIG_PATH)
	set_resolution.emit(resolution)


func _on_option_button_v_sync_item_selected(index):
	print_debug("Setting vsync mode: ", index)
	config.set_value("graphics", "vsync", index)
	config.save(CONFIG_PATH)
	DisplayServer.window_set_vsync_mode(index)


func _on_option_button_window_mode_item_selected(index):
	print_debug("Setting window mode: ", index)
	config.set_value("graphics", "windowed", index)
	config.save(CONFIG_PATH)
	DisplayServer.window_set_mode(index)


func _on_check_button_taa_toggled(button_pressed):
	print_debug("Set tta: ", button_pressed)
	config.set_value("graphics", "taa", button_pressed)
	config.save(CONFIG_PATH)
	set_taa.emit(button_pressed)


func _on_option_button_msaa_item_selected(index):
	print_debug("Set msaa: ", index)
	config.set_value("graphics", "msaa", index)
	config.save(CONFIG_PATH)
	set_msaa.emit(index)

