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
## Server: its key and certificate (DTLS); the certificate goes to clients.
var identity: ServerIdentity
## Client: the server being joined, and the certificate it showed before (null
## on a first join), for remembering it or explaining a failed join.
var _joining_address := ""
var _joining_port := 0
var _joining_pin: X509Certificate
## Logs this machine's traffic every 5 s, once hosting or joined.
var _traffic := TrafficReport.new()

signal connection_succeeded()
signal auth_failed(peer, reason)


## Quitting: go offline before the world is freed. Freeing it online sends
## each client a despawn for every spawned node, including nodes that client
## was never told about (fog of war), and it logs an error for each. This node
## comes after Galaxy in entry.tscn, so it leaves the tree first (Godot frees
## children last first). Only detached here, not closed: the spawners would
## still try to send through a closed peer, and closing the encrypted link
## cleanly (or saying goodbye first) makes the client log TLS errors as the
## link shuts while it sends. The peer closes as before, when it is freed.
func _exit_tree() -> void:
	if peer and multiplayer.multiplayer_peer == peer:
		multiplayer.multiplayer_peer = null  # Offline: the spawners send nothing more.


func _process(delta: float) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var line := _traffic.tick(enet, delta, multiplayer.get_peers())
	if line:
		Log.log([line], Log.MessageType.INFO)


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
	identity = ServerIdentity.new()
	if not identity.load_or_create() or secure_server(peer, identity) != OK:
		OS.alert("Failed to set up encryption for the multiplayer server.")
		peer.close()
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
		&'content' : Content.registry.signature(),  # The client checks it matches its own.
		&'certificate' : identity.certificate.save_to_string() if identity else "",  # KnownServers.
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
	if not (login as Dictionary).has("content"):
		return "Client too old: it sends no content list"
	var content := ContentRegistry.compare_signatures(Content.registry.signature(), login.content)
	if content:
		return content
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
	# The client usually hangs up first, on reading the refusal.
	if peer_id in multiplayer.get_authenticating_peers():
		multiplayer.disconnect_peer(peer_id)


func _auth_failed(client_peer):
	# Server doesn't need a popup. Logging and messaging done in respective functions.
	#auth_failed.emit(client_peer, "")
	pass


## Encrypts everything [param server_peer] sends and receives with DTLS, using
## [param identity]'s key. Logins carry passwords, so they must never cross the
## network in the clear. Call right after create_server.
static func secure_server(server_peer: ENetMultiplayerPeer, identity: ServerIdentity) -> Error:
	return server_peer.host.dtls_server_setup(identity.server_options())


## The client's side of secure_server: call right after create_client, before
## the connection is serviced. With [param pin] (the certificate this server
## showed before, KnownServers) the server must prove it holds that
## certificate's key, or the connection fails. Without one, on a first join,
## nothing is checked. The certificate is self-signed, so its name isn't
## checked either (client_unsafe with a trusted chain still checks the chain).
static func secure_client(client_peer: ENetMultiplayerPeer, server_address: String,
		pin: X509Certificate = null) -> Error:
	return client_peer.host.dtls_client_setup(server_address, TLSOptions.client_unsafe(pin))


## The certificate in a server's details [param info] (checked by
## check_server_info first), or "" when it sent none usable.
static func certificate_in(info: Dictionary) -> String:
	var pem: Variant = info.get("certificate", "")
	return pem if pem is String else ""


# Client
func join_game(ip, port, new_player_name, s_password, p_password):
	# Client Only
	Log.log(["Joining Game: ", ip, ":", port, " as " , new_player_name, " with id: ", multiplayer.get_unique_id()], Log.MessageType.INFO)
	player_name = new_player_name
	peer = ENetMultiplayerPeer.new()
	server_password = s_password
	player_password = p_password
	# A player may join again after a refusal; connect the signals only once.
	_connect_once(multiplayer.connected_to_server, on_connected)
	_connect_once(multiplayer.connection_failed, on_connection_failed)
	_connect_once(multiplayer.server_disconnected, on_server_disconnected)
	multiplayer.auth_callback = _client_auth_callback
	_joining_address = str(ip)
	_joining_port = int(port)
	_joining_pin = KnownServers.new().pinned(_joining_address, _joining_port)
	var err = peer.create_client(ip, port)
	if err == OK:
		err = secure_client(peer, ip, _joining_pin)
	if err != OK:
		print("Failed to join Game: ", ip, ":", port, " as " , new_player_name)
		return
	multiplayer.multiplayer_peer = peer


func _connect_once(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)


func on_connected():
	# We just connected to a server
	Log.log(["Emit connection_succeeded"], Log.MessageType.INFO)
	connection_succeeded.emit()


func on_connection_failed():
	print("Failed to connect to server")
	_go_offline()
	auth_failed.emit(1, connection_failed_reason(_joining_address, _joining_port, _joining_pin != null,
			KnownServers.new().path))


## What a player is told when joining [param address] fails before any reply.
## A server whose certificate is pinned ([param pinned]) and that can't prove
## it holds it fails the same way as one that isn't there, so both are named.
static func connection_failed_reason(address: String, port: int, pinned: bool, known_path: String) -> String:
	var reason := "Could not reach the server at %s." % KnownServers.key_for(address, port)
	if pinned:
		reason += (" If it is running, it may not be the server you joined before: its certificate"
				+ " changed, so someone could be pretending to be it. If its owner set it up again, remove"
				+ " the line for %s from %s and join again.") % [KnownServers.key_for(address, port),
				ProjectSettings.globalize_path(known_path)]
	return reason


func on_server_disconnected():
	print("Disconnected from server")
	_go_offline()


## A closed ENet peer left in place still counts as a peer, and asking it
## anything (is_server, get_unique_id) logs an error. Back to how the game
## boots: offline, where this machine is its own server (ID 1).
func _go_offline() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


## Client: why the server's details [param info] (from the network, so
## anything at all) rule out joining, or "": a refusal it sent, another
## protocol or version, or other content than [param our_content]
## (ContentRegistry.signature).
static func check_server_info(info: Variant, our_content: Array) -> String:
	if not info is Dictionary:
		return "Malformed server details"
	var dict: Dictionary = info
	if dict.has("error"):
		return str(dict["error"])
	if dict.get("protocol") != PROTOCOL:
		return "Server protocol mismatch"
	if not dict.get("protocol_version") is int:
		return "Malformed server details"
	if dict["protocol_version"] > SUPPORTED_PROTOCOL_VERSION:
		return "Server protocol version too new"
	if dict["protocol_version"] < SUPPORTED_PROTOCOL_VERSION:
		return "Server protocol version too old"
	if dict.get("host_token") != "bruh im legit":
		return "Server untrustworthy"
	return ContentRegistry.compare_signatures(our_content, dict.get("content"))


## CLIENT GETS SERVER's QUERY and SENDS REPLY
func _client_auth_callback(client_id: int, buf : PackedByteArray):
	var info: Variant = bytes_to_var(buf)  # From the network: anything at all, checked below.
	Log.log(["_auth_callback recieved data from PID ", client_id], Log.MessageType.QUESTION)
	var error_msg := check_server_info(info, Content.registry.signature())
	if error_msg.length() > 0:
		Log.log(error_msg, Log.MessageType.PANIC)
		peer.disconnect_peer(1)
		auth_failed.emit(1, error_msg)
		return
	# First join: remember the certificate, so later joins check it. A pinned
	# one was already checked by the DTLS handshake.
	if _joining_pin == null and _joining_address:
		if KnownServers.new().remember(_joining_address, _joining_port, certificate_in(info)):
			Log.log(["Remembered the certificate of ", KnownServers.key_for(_joining_address, _joining_port)],
					Log.MessageType.INFO)
		else:
			Log.log(["The server sent no usable certificate; it won't be checked next time"],
					Log.MessageType.WARNING)

	var dict := {
			'client_token' : "me2",
			'server_password': server_password,
			'player_name' : player_name,
			'player_password': player_password,
			'content': Content.registry.signature(),  # The server checks it matches its own.
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
