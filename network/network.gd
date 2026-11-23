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

var players: Players
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


## Fields a client's login must carry, all strings.
const LOGIN_FIELDS: Array[String] = ["client_token", "server_password", "player_name", "player_password"]
const MAX_PLAYER_NAME := 32


## Why [param login] (decoded from a client, so anything at all) is not a usable
## login, or "" when it is. Checks its shape only; passwords are checked later.
static func check_login(login: Variant) -> String:
	if not login is Dictionary:
		return "Malformed login"
	for field in LOGIN_FIELDS:
		if not login.get(field) is String:
			return "Malformed login"
	if not valid_player_name(login.player_name):
		return "Player names are 1 to %d characters, without . : @ / \" %% or spaces at either end" \
				% MAX_PLAYER_NAME
	return ""


## Player names become node names under Players and are looked up with
## has_node, so they must not be node paths ("..", "a/b") or contain characters
## Godot strips from node names (. : @ / " %).
static func valid_player_name(player_name: String) -> bool:
	if player_name.is_empty() or player_name.length() > MAX_PLAYER_NAME:
		return false
	if player_name != player_name.strip_edges():
		return false
	return player_name.validate_node_name() == player_name


func _authenticate_callback(peer_id: int, data: PackedByteArray):
	# bytes_to_var never builds objects, but the data can still be any Variant.
	var login: Variant = bytes_to_var(data)
	var message := check_login(login)
	if message:
		_refuse_login(peer_id, message)
		return
	var dict: Dictionary = login
	# Never log the dictionary: it holds passwords.
	Log.log(["Login from peer ", peer_id, " as ", dict.player_name], Log.MessageType.QUESTION)
	if dict.client_token != "me2":
		message = "Client untrustworthy"
	elif dict.server_password != server_password:
		message = "Wrong server password"
	elif players.is_logged_in_id(peer_id):
		message = "Player is logged in"
	elif players.is_logged_in_name(dict.player_name):
		message = "Player is logged in with this name"
	elif !players.check_player(dict.player_name, dict.player_password, peer_id):
		message = "Wrong player password"
	if message.length() > 0:
		_refuse_login(peer_id, message)
		return
	var client := peer.get_peer(peer_id)
	if not client:
		Log.log(["There is an error with getting peer", peer_id, peer], Log.MessageType.ERROR)
		return
	client.set_timeout(1000, 4000, 6000)
	Log.log(["Client ", dict.player_name, "authenticated"], Log.MessageType.SUCCESS)
	multiplayer.complete_auth(peer_id)


func _refuse_login(peer_id: int, message: String) -> void:
	multiplayer.send_auth(peer_id, var_to_bytes({'error': message}))
	Log.log(["Login refused for peer ", peer_id, ": ", message], Log.MessageType.ERROR)
	await get_tree().create_timer(0.1).timeout
	multiplayer.disconnect_peer(peer_id)


func _auth_failed(client_peer):
	# Server doesn't need a popup. Logging and messaging done in respective functions.
	#auth_failed.emit(client_peer, "")
	pass


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
	Log.log(["Emit connection_succeeded"], Log.MessageType.INFO)
	connection_succeeded.emit()


func on_connection_failed():
	print("Failed to connect to server")


func on_server_disconnected():
	print("Disconnected from server")


## CLIENT GETS SERVER's QUERY and SENDS REPLY
func _client_auth_callback(client_id: int, buf : PackedByteArray):
	var dict:Dictionary = bytes_to_var(buf)
	Log.log(["_auth_callback recieved data ", str(dict), "from PID", client_id, "or", multiplayer.get_remote_sender_id()], Log.MessageType.QUESTION)
	var error_msg:= ""
	if dict.has('error'):
		error_msg = dict['error']
	elif dict.protocol != PROTOCOL:
		error_msg = "Server protocol mismatch"
	elif dict.protocol_version > SUPPORTED_PROTOCOL_VERSION:
		error_msg = "Server protocol version too new"
	elif dict.protocol_version < SUPPORTED_PROTOCOL_VERSION:
		error_msg = "Server protocol version too old"
	elif dict.host_token != 'bruh im legit':
		error_msg = "Server untrustworthy"
	
	if error_msg.length() > 0:
		Log.log(error_msg, Log.MessageType.PANIC)
		peer.disconnect_peer(1)
		auth_failed.emit(1, error_msg)
		return

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
