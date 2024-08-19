extends Node

var config: ConfigFile
var CONFIG_PATH := "user://config.cfg"
const chars = "abcdefghijklmnopqrstuvwxyz0123456789"


# Called when the node enters the scene tree for the first time.
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
		config.set_value("player", "password", gen_random_password(6))
		var error := config.save(CONFIG_PATH)
		if error:
			print("An error happened while saving data: ", error)


func set_value(section: String, key: String, value: Variant):
	config.set_value(section, key, value)
	var error := config.save(CONFIG_PATH)
	if error:
		print("An error happened while saving data: ", error)


func get_value(section: String, key: String, default: Variant = null):
	return config.get_value(section, key, default)


func gen_random_password(length: int) -> String:
	var output_string := ""
	for i in range(length):
		output_string += chars[randi() % chars.length()]
	return output_string
	
