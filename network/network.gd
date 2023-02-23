extends Node

# Stolen from Bomb demo
# Default game server port. Can be any number between 1024 and 49151.
# Not on the list of registered or common ports as of November 2020:
# https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers
const DEFAULT_PORT = 2258

# Max number of players.
const MAX_PEERS = 12

var peer = null

# Names for remote players in id:name format.
var players = {}
var player_name = ""

signal connection_succeeded()


# Callback from SceneTree, only for clients (not server).
func _connected_ok():
	# We just connected to a server
	connection_succeeded.emit()


func _player_connected(id):
	print("Player connected: ", id)
	rpc_id(id, StringName("register_player"), player_name)


func _player_disconnected(id):
	unregister_player(id)
	

@rpc("any_peer")
func register_player(new_player_name):
	var id = multiplayer.get_remote_sender_id()
	players[id] = new_player_name
	print("Current Players: ", players)
	var player = preload("res://network/player.tscn").instantiate()
	player.set_name(str(id))
	#player.set_network_master(id)
	$players.add_child(player)
	#player_list_changed.emit()


func unregister_player(id):
	players.erase(id)
	#player_list_changed.emit()


func host_server(port: int=DEFAULT_PORT):
	#player_name = new_player_name
	peer = ENetMultiplayerPeer.new()
	peer.create_server(port, MAX_PEERS)
	multiplayer.set_multiplayer_peer(peer)
	print_debug("Server hosted on port: ", port)


func join_game(ip, port, new_player_name):
	#Client Only
	print("Joining Game: ", ip, ":", port, " as " , new_player_name)
	player_name = new_player_name
	peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, port)
	multiplayer.set_multiplayer_peer(peer)


func _ready():
	get_tree().get_root().get_node("entry").get_node("MainMenu").join_game.connect(join_game)
	multiplayer.peer_connected.connect(_player_connected)
	multiplayer.peer_disconnected.connect(_player_disconnected)
	multiplayer.connected_to_server.connect(_connected_ok)
	#multiplayer.connection_failed.connect(_connected_fail)
	#multiplayer.server_disconnected.connect(_server_disconnected)
