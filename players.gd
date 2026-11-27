extends Node
class_name Players
## Who is online in this world: a Player node per player who has logged in this
## session, replicated to clients (player and peer IDs only, no passwords; do
## not add any to its synchronizer). Logins are checked against the world's
## PlayerRecords (Galaxy.state.players), which keep player IDs for good.


## Server: logs [param player_name] in from [param peer_id], registering a new
## name. False when the name is known and the password is wrong.
func check_player(player_name: String, player_password: String, peer_id: int) -> bool:
	var player_id := _records().log_in(player_name, player_password)
	if player_id == PlayerRecords.REFUSED:
		return false
	var player: Player = get_node_or_null(NodePath(player_name))
	if player == null:
		player = preload("res://player.tscn").instantiate()
		player.name = player_name
		player.player_id = player_id
		add_child(player)
		Log.log(["Registered player: " + player_name], Log.MessageType.INFO)
	player.network_id = peer_id
	return true


## Server: the host's own player (a host logs in without the network).
func register_player(player_name: String, player_password: String, peer_id: int) -> void:
	check_player(player_name, player_password, peer_id)


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
		if get_node(player_name).network_id >= 0:
			return true
	return false


func find_player_by_netid(id: int) -> Player:
	for player in get_children():
		if player.network_id == id:
			return player
	return null


func _records() -> PlayerRecords:
	return (get_parent() as Galaxy).state.players
