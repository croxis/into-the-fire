class_name SpawnService
extends Node
## Where a world's players come in, and where crews go when their ship is
## destroyed. The server decides everything (spawn points, refusals, respawns
## by its RespawnRules); clients only ask, with request_spawn and
## request_spawn_points. A child of Galaxy on server and clients alike, since an
## RPC needs the same node path on both.

## The spawn points request_spawn_points asked for, {system name: [ship name, ...]}.
signal spawn_points_received(faction_name: String, points: Dictionary)
## Client: the server put this player back in their character (they never left
## the world), so they pick no spawn point.
signal resumed()

## Server: what happens to a destroyed ship's crew.
var rules := RespawnRules.new()

var _galaxy: Galaxy


func _init(galaxy: Galaxy) -> void:
	_galaxy = galaxy
	name = "SpawnService"


# Checks ---------------------------------------------------------------------

## Why a spawn request is refused, or "" if it is acceptable. Everything here
## comes from a client, so nothing is trusted: the faction must exist and take
## players, and the system must be one of ours. A plain name check isn't enough
## for the system, since a path such as "../.." would also resolve to a node.
## No system named is acceptable: the server picks (resolve_spawn_point).
static func check_spawn_request(registry: FactionRegistry, systems: Node,
		faction_id: int, system_name: String) -> String:
	var faction := registry.get_by_id(faction_id)
	if faction == null:
		return "unknown faction %d" % faction_id
	if not faction.accept_players:
		return "faction %s does not accept players" % faction.resource_name
	if system_name.is_empty():
		return ""
	var system := systems.get_node_or_null(NodePath(system_name))
	if system == null or system.get_parent() != systems:
		return "unknown system %s" % system_name
	return ""


## Why a client's pick of spawn point [param spawner_name] in [param system_name]
## is refused, or "": it must be one of [param points] (spawn_points). No
## name means the first one there.
static func check_spawn_point(points: Dictionary, system_name: String, spawner_name: String) -> String:
	var there: Array = points.get(system_name, [])
	if there.is_empty():
		return "nowhere to spawn in %s" % system_name
	if spawner_name and not spawner_name in there:
		return "no spawn point %s in %s" % [spawner_name, system_name]
	return ""


## [system name, ship name] for a pick among [param points], or [] when it is
## refused. No system named means the first system with any; no ship named, the
## first ship there.
static func resolve_spawn_point(points: Dictionary, system_name: String, spawner_name: String) -> Array:
	if system_name.is_empty():
		if points.is_empty():
			return []
		system_name = points.keys()[0]
	if check_spawn_point(points, system_name, spawner_name):
		return []
	return [system_name, spawner_name if spawner_name else points[system_name][0]]


## The living character of player [param player_id] anywhere under
## [param systems], or null. A player has at most one.
static func find_player_character(systems: Node, player_id: int) -> Character:
	for node in systems.find_children("*", "", true, false):
		var c := node as Character
		if c and c._player_pilot_id == player_id and not c.is_queued_for_deletion():
			return c
	return null


## Server: where [param faction]'s players can spawn, as names a client can be
## sent: {system name: [ship name, ...]} (System.spawn_points_for).
func spawn_points(faction: Faction) -> Dictionary:
	var points := {}
	for system in _galaxy.zones.systems():
		var here := system.spawn_points_for(faction)
		if not here.is_empty():
			points[String(system.name)] = here
	return points


# Client requests ------------------------------------------------------------

## Asks the server to spawn this machine's player for [param faction_name] at
## [param spawner_name] in [param system_name] (no names: the server picks).
func request_spawn(faction_name: String, system_name: String, spawner_name: String) -> void:
	var faction := _galaxy.factions.find_by_name(faction_name)
	if faction == null:
		return
	_request_spawn.rpc_id(1, faction.faction_id, system_name, spawner_name)  # The server only (the host: itself).


## Asks the server where [param faction_name]'s players can spawn (a client may
## not know of those ships at all, netcode N5b2); spawn_points_received answers.
func request_spawn_points(faction_name: String) -> void:
	var faction := _galaxy.factions.find_by_name(faction_name)
	if faction == null:
		return
	if multiplayer.is_server():
		spawn_points_received.emit(faction_name, spawn_points(faction))
	else:
		_request_spawn_points.rpc_id(1, faction.faction_id)


# Server: first spawn --------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _request_spawn(faction_id: int, system_name: String, spawner_name: String) -> void:
	if not multiplayer.is_server():
		return
	var remote_id := multiplayer.get_remote_sender_id()
	# If the host is calling this function, remote id is 0, change to its actual id
	if remote_id == 0:
		remote_id = multiplayer.get_unique_id()
	Log.log(["Spawn request from peer ", remote_id, ": faction ", faction_id, " at ",
			spawner_name if spawner_name else "(first)", " in ",
			system_name if system_name else "(first)"], Log.MessageType.QUESTION)
	var player: Player = _galaxy.get_node("Players").find_player_by_netid(remote_id)
	if player == null:
		Log.log(["Spawn refused for peer ", remote_id, ": not logged in"], Log.MessageType.WARNING)
		return
	var zones := _galaxy.zones
	var refusal := check_spawn_request(_galaxy.factions, zones, faction_id, system_name)
	if not refusal and zones.player_character(player.player_id):
		refusal = "already in the world"
	var faction: Faction = _galaxy.factions.get_by_id(faction_id)
	var at := [] if refusal else resolve_spawn_point(spawn_points(faction), system_name, spawner_name)
	if not refusal and at.is_empty():
		refusal = "no spawn point %s in %s" % [spawner_name if spawner_name else "at all",
				system_name if system_name else "any system"]
	if refusal:
		Log.log(["Spawn refused for ", player.name, ": ", refusal], Log.MessageType.WARNING)
		return
	# Both names are among the points offered, so this path stays inside the zone.
	var spawn_ship: Ship = zones.get_system(at[0]).get_node("ships").get_node(at[1])
	_enter_system.rpc_id(remote_id, at[0])
	var player_pilot := spawn_ship.spawn_crew(
			Character.pilot_data(player.name, faction_id, remote_id, _galaxy.ids.next_pilot(),
				player.player_id))
	if player_pilot == null:
		return
	faction.add_member(player_pilot)
	Log.log(["Created pilot: ", player_pilot, " in faction ", faction.resource_name, " with mpid: ", player_pilot.multiplayer_id], Log.MessageType.SUCCESS)


## Server: a client's join menu wants [param faction_id]'s spawn points. Only for
## a faction that takes players; the answer goes to the sender.
@rpc("any_peer", "call_remote", "reliable")
func _request_spawn_points(faction_id: int) -> void:
	if not multiplayer.is_server():
		return
	var faction := _galaxy.factions.get_by_id(faction_id)
	if faction == null or not faction.accept_players:
		return
	_receive_spawn_points.rpc_id(multiplayer.get_remote_sender_id(), faction.resource_name,
			spawn_points(faction))


## Client: the server's answer to _request_spawn_points.
@rpc("authority", "call_remote", "reliable")
func _receive_spawn_points(faction_name: String, points: Dictionary) -> void:
	spawn_points_received.emit(faction_name, points)


## Sent by the server to the player who is (again) in [param system_name].
## "authority": only the server may move a player's view to a system.
@rpc("authority", "call_local", "reliable")
func _enter_system(system_name: String) -> void:
	_galaxy.view_system(system_name)


# Server: rejoin -------------------------------------------------------------

## Server: a player whose character is still in the world logged back in from
## [param peer]: they take it over again, where it is, with its camera and HUD.
func resume(character: Character, peer: int) -> void:
	character.pilot_rejoined(peer)
	_galaxy.fog.refresh()  # Their ship and its system spawn there before the RPCs below.
	var system := System.find_for(character)
	_resumed.rpc_id(peer)
	_enter_system.rpc_id(peer, String(system.name))
	var console := character.current_console
	if console:
		console.set_camera.rpc_id(peer)
		console._show_hud.rpc_id(peer)
	elif character.current_ship:
		character.current_ship.set_camera.rpc_id(peer)
		character.current_ship.set_capital_ui.rpc_id(peer)
	Log.log(["Resumed ", character.name, " for peer ", peer], Log.MessageType.SUCCESS)


## Client: the server put us back in our character: no join menu.
@rpc("authority", "call_remote", "reliable")
func _resumed() -> void:
	resumed.emit()


# Server: respawn ------------------------------------------------------------

## Server: [param ship] is being destroyed (Ship.destroyed); its crew go where
## the rules say. The ship itself is handled elsewhere.
func on_ship_destroyed(ship: Ship) -> void:
	var system: System = ship.get_current_system()
	if system == null:
		return
	for old_pilot: Character in ship.get_crew():
		if not rules.respawns(old_pilot):
			continue
		var carrier := system.nearest_carrier_for(old_pilot, ship)
		if carrier:
			#TODO: Generalize this to a multicrew craft
			carrier.spawn_crew(old_pilot.serialize())
