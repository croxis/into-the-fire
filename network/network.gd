extends Node

const PROTOCOL := "ITF"
const SUPPORTED_PROTOCOL_VERSION : int = 1


# Stolen from Bomb demo
# Default game server port. Can be any number between 1024 and 49151.
# Not on the list of registered or common ports as of November 2020:
# https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers
const DEFAULT_PORT = 2258

# Max number of players.
const MAX_PEERS = 12

var peer: ENetMultiplayerPeer = null

var players: Node
var player_name := ""
var player_password := ""
var pending := {}
var server_password := ""
var server_name := ""

signal connection_succeeded()
signal auth_failed(peer, reason)


# Server
func host_server(new_game_name, new_player_name, port: int=DEFAULT_PORT, s_password:="", p_password:="") -> bool:
	var success := start_server(new_game_name, s_password, port)
	if success:
		player_name = new_player_name
		players.register_player(new_player_name, p_password, multiplayer.get_unique_id())
	return success


func start_server(new_game_name, s_password:="", port: int=DEFAULT_PORT) -> bool:
	server_name = new_game_name
	peer = ENetMultiplayerPeer.new()
	peer.create_server(port, MAX_PEERS)
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		OS.alert("Failed to start multiplayer server.")
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_authenticating.connect(_authenticating)
	multiplayer.peer_authentication_failed.connect(_auth_failed)
	multiplayer.set_auth_callback(_authenticate_callback)
	multiplayer.peer_connected.connect(on_client_connected)
	multiplayer.peer_disconnected.connect(_player_disconnected)
	Log.log(["Server hosted on port: " + str(port)], Log.MessageType.INFO)
	Log.log(["Server MP ID: ", multiplayer.get_unique_id()], Log.MessageType.INFO)
	server_password = s_password
	get_tree().root.get_node("entry").is_server = true
	return true


func _player_disconnected(client_id):
	Log.log(["Client %d disconnected!" % [client_id]], Log.MessageType.INFO)
	players.player_disconnect(client_id)


func on_client_connected(client_id : int):
	Log.log(["Client %d connected!" % [client_id]], Log.MessageType.SUCCESS)


func _authenticating(peer_id):
	Log.log(["Client %d authenticating!" % [peer_id]], Log.MessageType.QUESTION)

	var dict : Dictionary = {
		&'protocol' : PROTOCOL,
		&'protocol_version' : SUPPORTED_PROTOCOL_VERSION,
		&'hostname' : server_name,
		&'host_token' : "bruh im legit",
		}

	var buf:PackedByteArray = var_to_bytes(dict)
	multiplayer.send_auth(peer_id, buf)	


func _authenticate_callback(peer_id: int, data: PackedByteArray):
	var dict:Dictionary = bytes_to_var(data)
	Log.log(["_auth_callback recieved data ", str(dict), "from PID", peer_id, "or", multiplayer.get_remote_sender_id()], Log.MessageType.QUESTION)
	if dict.client_token != "me2":
		Log.log(["Client untrustworthy"], Log.MessageType.ERROR)
		peer.disconnect_peer(peer_id)
		return
	if dict.server_password != server_password:
		Log.log(["Wrong server password"], Log.MessageType.ERROR)
		peer.disconnect_peer(peer_id)
		return
	if players.is_logged_in_id(peer_id):
		Log.log(["Player is logged in"], Log.MessageType.ERROR)
		#print(players.get_children())
		peer.disconnect_peer(peer_id)
		return
	if !players.check_player(dict.player_name, dict.player_password, peer_id):
		Log.log(["Wrong player password"], Log.MessageType.ERROR)
		peer.disconnect_peer(peer_id)
		return
	var client := peer.get_peer(peer_id)
	client.set_timeout(1000, 4000, 6000)
	Log.log(["Client ", dict.player_name, "authenticated"], Log.MessageType.SUCCESS)
	multiplayer.complete_auth(peer_id)


func _auth_failed(client_peer):
	auth_failed.emit(client_peer, "")


# Client
func join_game(ip, port, new_player_name, s_password, p_password):
	# Client Only
	Log.log(["Joining Game: ", ip, ":", port, " as " , new_player_name, " with id: ", multiplayer.get_unique_id()], Log.MessageType.INFO)
	player_name = new_player_name
	peer = ENetMultiplayerPeer.new()
	server_password = s_password
	player_password = p_password
	multiplayer.connected_to_server.connect(on_connected)
	multiplayer.connection_failed.connect(on_connection_failed)
	multiplayer.server_disconnected.connect(on_server_disconnected)
	multiplayer.auth_callback = _client_auth_callback
	var err = peer.create_client(ip, port)
	if err != OK:
		print("Failed to join Game: ", ip, ":", port, " as " , new_player_name)
		return
	multiplayer.multiplayer_peer = peer


func on_connected():
	# We just connected to a server
	connection_succeeded.emit()


func on_connection_failed():
	print("Failed to connect to server")


func on_server_disconnected():
	print("Disconnected from server")


## CLIENT GETS SERVER's QUERY and SENDS REPLY
func _client_auth_callback(client_id: int, buf : PackedByteArray):
	var dict:Dictionary = bytes_to_var(buf)
	Log.log(["_auth_callback recieved data ", str(dict), "from PID", client_id, "or", multiplayer.get_remote_sender_id()], Log.MessageType.QUESTION)

	if dict.protocol != PROTOCOL:
		Log.log(["Server protocol mismatch"], Log.MessageType.ERROR)
		peer.disconnect_peer(1)

	if dict.protocol_version > SUPPORTED_PROTOCOL_VERSION:
		Log.log(["Server protocol version too new"], Log.MessageType.ERROR)
		peer.disconnect_peer(1)

	if dict.protocol_version < SUPPORTED_PROTOCOL_VERSION:
		Log.log(["Server protocol version too old"], Log.MessageType.ERROR)
		peer.disconnect_peer(1)

	if dict.host_token != 'bruh im legit':
		Log.log(["Server untrustworthy"], Log.MessageType.PANIC)
		peer.disconnect_peer(1)

	dict = {
			'client_token' : "me2",
			'server_password': server_password,
			'player_name' : player_name,
			'player_password': player_password
		}

	buf = var_to_bytes(dict)
	multiplayer.send_auth(1, buf)
	multiplayer.complete_auth(1)


func _refuse(server_peer, p_msg:=""):
	multiplayer.disconnect_peer(server_peer)
	pending.erase(server_peer)
	_auth_failed(server_peer)
	auth_failed.emit(server_peer, p_msg)


func _on_main_menu_join_game(ip, port, p_name, s_password, p_password):
	join_game(ip, port, p_name, s_password, p_password)
