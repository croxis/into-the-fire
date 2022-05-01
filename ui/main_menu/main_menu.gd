extends Control

signal join_game(ip, port: int, player_name)

func _ready():
	if OS.has_environment("USERNAME"):
		$HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditCallsign.text = OS.get_environment("USERNAME")
	else:
		var desktop_path = OS.get_system_dir(0).replace("\\", "/").split("/")
		$HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditCallsign.text = desktop_path[desktop_path.size() - 2]
		

func close_all() -> void:
	for child in get_node("HBoxContainer/VBoxContainerOption").get_children():
		child.visible = false


func _on_button_join_game_pressed():
	close_all()
	$HBoxContainer/VBoxContainerOption/VBoxContainerJoin.visible = true


func _on_button_exit_desktop_pressed():
	get_tree().quit()


func _on_button_join_server_pressed():
	var ip = $HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditIP.text
	var port_string = $HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditPort.text
	if not port_string.is_valid_int():
		print(port_string, " is not a valid port")
	var port = port_string.to_int()
	if not (port >= 1 and port <= 65535):
		print("Error: ", port_string, " Not Valid Port")
	var new_player_name = $HBoxContainer/VBoxContainerOption/VBoxContainerJoin/GridContainer/LineEditCallsign.text
	if new_player_name == "":
		print("Error: Not valid player name")
	join_game.emit(ip, port, new_player_name)
