extends Node
var playerid_counter := 1

# 0 is reserved for npc
# Do not use network syncronizers for this due to passwords!

func check_player(player_name: String, player_password: String, peer_id: int) -> bool:
	if has_node(player_name):
		#if get_node(player_name).password == player_password:
		if get_node(player_name).password_match(player_password):
			get_node(player_name).network_id = peer_id
			return true
		else:
			return false
	else:
		register_player(player_name, player_password, peer_id)
		return true


func register_player(player_name: String, player_password: String, peer_id: int):
	var player_scene := preload("res://player.tscn")
	var player := player_scene.instantiate()
	player.name = player_name
	player.password = player_password
	player.player_id = playerid_counter
	player.network_id = peer_id
	add_child(player)
	playerid_counter += 1
	Logger.log(["Registered player: " + player_name], Logger.MessageType.INFO)
	save_players()


func player_disconnect(peer_id: int):
	for child in get_children():
		if child.network_id == peer_id:
			child.network_id = -1
			return


func is_logged_in_id(peer_id: int) -> bool:
	for child in get_children():
		if child.network_id == peer_id:
			return true
	return false


func is_logged_in_name(player_name: String) -> bool:
	if has_node(player_name):
		if get_node(player_name).network_id > 0:
			return true
	return false


func save_players():
	pass


func find_player_by_netid(id: int) -> Player:
	for player in get_children():
		if player.network_id == id:
			return player
	return null
