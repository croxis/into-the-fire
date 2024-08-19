extends Node

var game_name: String
var save_path := "user://"
var save_version = 1


func save_players(data):
	var error := ResourceSaver.save(data, save_path + "players")
	if error:
		print("An error happened while saving data: ", error)


func _on_main_menu_new_game(gname, _player_name, _port, _server_password):
	game_name = gname
	save_path = "user://" + game_name + "/"
