class_name Galaxy
extends Node

var game_name := "default"
var render_resolution := Vector2i(0, 0)
@onready var msaa = PlayerConfig.get_config("graphics", "msaa", 0)
@onready var taa = PlayerConfig.get_config("graphics", "taa", 0)
var active_galaxy := false

## The scenario a new game starts from (content ID, kind "scenario").
@export var scenario_id: StringName = &"b5:playtest"
var _scenario: Scenario
var _scenario_scenes: SceneBatchLoader  # Held from loading until populate() runs.

## Ship and pilot IDs for this world.
var ids := WorldIds.new()

## Draws the zone the local player is in. Unused on a dedicated server.
var zone_view := ZoneView.new()
## The local player's HUD (passenger HUD for now). Empty on a dedicated server.
var hud := HudLayer.new()
## Steps every system's physics space (zones), on server and clients.
var zone_stepper := ZoneStepper.new()
## Client: when ships' snapshots arrive, so when to draw them (netcode N4c).
var snapshot_clock := SnapshotClock.new()
## Client: ships this player's side lost contact with, and their ghosts (N5c).
var contacts := ContactLog.new(1.0 / 60.0)
## Server: which ships each client is told about (netcode N5). Kept up to date
## every INTEREST_SECONDS and when a ship appears (refresh_interest).
var interest := Interest.new()
const INTEREST_SECONDS := 0.5
var _interest_timer := 0.0
## Server: refresh_interest has just run.
signal interest_refreshed()

## Every faction in this world. The server creates them; clients receive a copy
## when they join (see _rpc_receive_factions). Replaced as a whole, never patched
## from client data.
var factions := FactionRegistry.new()
var _factions_synced := false  # Client: a faction copy has arrived from the server.
var _join_menu_wanted := false  # Client: show the join menu once factions arrive.

var _play_time: float = 0
var _sync_interval: float = 10
var _sync_timer: float = _sync_interval  # Countown in seconds for syncing network time

signal enter_system(system_name)
## Emitted on clients when a faction copy arrives from the server.
signal factions_synced()
## Asks the loading screen to load [param paths] in the background; it calls
## [param callback] with the finished SceneBatchLoader.
signal load_scenes(paths: PackedStringArray, callback: Callable)


## Server: where [param faction]'s players can spawn, as names a client can be
## sent: {system name: [ship name, ...]}. Ships with launch bays on its own side
## (the faction or one above it, as for respawns): a client is told of no others
## (netcode N5b2). [param ships_by_system]: {system name: [Ship, ...]}.
## TODO: inventory, hyperspace, generated deep-space systems.
static func spawn_points_for(faction: Faction, ships_by_system: Dictionary) -> Dictionary:
	var points := {}
	for system_name in ships_by_system:
		for ship: Ship in ships_by_system[system_name]:
			var side := ship.faction
			if ship.has_spawn_points and side and (side == faction or faction.is_a_parent(side)):
				if not points.has(system_name):
					points[system_name] = []
				points[system_name].append(String(ship.name))
	return points


## Why a client's pick of spawn point [param spawner_name] in [param system_name]
## is refused, or "": it must be one of [param points] (spawn_points_for). No
## name means the first one there.
static func check_spawn_point(points: Dictionary, system_name: String, spawner_name: String) -> String:
	var there: Array = points.get(system_name, [])
	if there.is_empty():
		return "nowhere to spawn in %s" % system_name
	if spawner_name and not spawner_name in there:
		return "no spawn point %s in %s" % [spawner_name, system_name]
	return ""


## Server: spawn_points_for this galaxy's systems.
func _spawn_points(faction: Faction) -> Dictionary:
	var ships_by_system := {}
	for system in $Systems.get_children():
		if system is System:
			ships_by_system[String(system.name)] = system.get_ships()
	return spawn_points_for(faction, ships_by_system)


func player_died(player_id: int) -> void:
	print_debug("Player died: ", player_id, " ", multiplayer.get_unique_id())
	rpc_id(player_id, "show_spawn")


## Sent by the server to the player who just spawned. "authority": only the
## server may move a player's view to a system.
@rpc("authority", "call_local")
func player_enter_system(system_name) -> void:
	var system: System = get_node("Systems/" + system_name)
	zone_view.view(system)
	#Music Hack
	system.get_node("AudioStreamPlayer").playing = true
	# This runs on the spawning player's own machine, so look up the local peer
	# (the sender is always the server).
	var player: Player = $Players.find_player_by_netid(multiplayer.get_unique_id())
	if player == null:
		Log.log(["No Player for this peer yet; local player id not set"], Log.MessageType.WARNING)
		return
	LocalGameManager.player_id = player.player_id


func find_pilot_by_network_id(id: int) -> Character:
	for pilot in $Systems.find_children("*", "Pilot", true, false):
		if pilot.multiplayer_id == id:
			return pilot
	return null


func set_render_resolution(resolution: Vector2i) -> void:
	print_debug("Galaxy: Setting render resolution: ", resolution)
	render_resolution = resolution
	update_graphics()


func set_msaa(status):
	msaa = status
	update_graphics()


func set_taa(status):
	taa = status
	update_graphics()


## Graphics settings apply to the main window, which draws the viewed zone
## (ZoneView). Zone SubViewports don't render, so they need none.
func update_graphics():
	var window := get_viewport()
	window.msaa_3d = msaa
	window.use_taa = taa
	window.scaling_3d_scale = ZoneView.render_scale(render_resolution, window.get_visible_rect().size)


## The Galaxy that [param node] lives under, or null when there is none (the
## node isn't in the tree yet, or it is running alone in a unit test).
static func find_for(node: Node) -> Galaxy:
	var n := node
	while n:
		if n is Galaxy:
			return n
		n = n.get_parent()
	return null


func _ready():
	#TODO: Serialize from save
	_play_time = 0
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	zone_view.name = "ZoneView"
	add_child(zone_view)
	add_child(hud)
	add_child(zone_stepper)
	# Systems arrive from setup on the server and from the spawner on clients.
	$Systems.child_entered_tree.connect(_on_system_entered)


func _on_system_entered(node: Node) -> void:
	if node is System:
		zone_stepper.add_zone(node)


## Server: send the faction tree to a client that just connected.
## (peer_connected also fires on clients when other peers join; they ignore it.)
func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_rpc_receive_factions.rpc_id(peer_id, factions.to_data())
		var player: Player = $Players.find_player_by_netid(peer_id)
		var character := find_player_character($Systems, player.player_id) if player else null
		if character:
			_resume(character, peer_id)
		else:
			refresh_interest()  # So its ships spawn there now, not up to 0.5 s later.


## Server: a peer left. A player's character stays in the world, hands off the
## controls, until they log back in (Character.pilot_disconnected).
func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for character in $Systems.find_children("*", "", true, false):
		if character is Character and character.is_player() and character.multiplayer_id == peer_id:
			character.pilot_disconnected()
			Log.log([character.name, " left; their character stays"], Log.MessageType.INFO)


## Server: a player whose character is still in the world logged back in from
## [param peer]: they take it over again, where it is, with its camera and HUD.
func _resume(character: Character, peer: int) -> void:
	character.pilot_rejoined(peer)
	refresh_interest()  # Their ship and its system spawn there before the RPCs below.
	var system := System.find_for(character)
	_rpc_resume.rpc_id(peer, String(system.name) if system else "")
	player_enter_system.rpc_id(peer, String(system.name))
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
func _rpc_resume(_system_name: String) -> void:
	_join_menu_wanted = false
	$CanvasLayer/JoinGame.visible = false


## Client: replace the local copy with the server's.
## "authority" means only the server may call this, so a client can't push
## factions to other peers. The data is plain dictionaries, not objects.
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_factions(data: Dictionary) -> void:
	factions = FactionRegistry.from_data(data)
	_factions_synced = true
	Log.log(["Received ", factions.size(), " factions from server"], Log.MessageType.INFO)
	factions_synced.emit()
	_try_show_join_menu()


## Shows the faction picker once it is wanted and there are factions to pick from.
func _try_show_join_menu() -> void:
	if not _join_menu_wanted:
		return
	if not multiplayer.is_server() and not _factions_synced:
		return  # Still waiting for the server's factions.
	_join_menu_wanted = false
	$CanvasLayer/JoinGame.build_faction_menu(factions)
	$CanvasLayer/JoinGame.visible = true


func setup_new_galaxy(dedicated=false, callback = null):
	Log.log(["Setting up galaxy."], Log.MessageType.QUESTION)
	if dedicated:
		callback = Callable(self, "finish_setup_galaxy_all")
	if not active_galaxy and get_tree().root.get_node("entry").is_server:
		if not _start_scenario(callback):
			return
		active_galaxy = true
		Log.log(["Galaxy setup complete."], Log.MessageType.INFO)
	else:
		print("Galaxy already initalized")


## Server: checks the scenario, creates its factions and starts loading its
## systems. [param callback] runs once every system is in the tree.
func _start_scenario(callback) -> bool:
	_scenario = load(Content.path_of(scenario_id)) as Scenario
	if _scenario == null:
		Log.log(["Scenario ", scenario_id, " not found"], Log.MessageType.ERROR)
		return false
	var errors := ScenarioLoader.validate(_scenario, Content.registry)
	if not errors.is_empty():
		Log.log(["Scenario ", scenario_id, " is invalid: ", "; ".join(errors)], Log.MessageType.ERROR)
		return false
	factions = ScenarioLoader.build_factions(_scenario)
	ids = WorldIds.new()
	# Every system and ship scene at once, on worker threads, so populate()
	# later instantiates from the cache instead of reading files on this thread.
	load_scenes.emit(ScenarioLoader.scene_paths(_scenario, Content.registry),
			_on_scenario_scenes_loaded.bind(callback))
	return true


## Adds the scenario's systems, in order, then runs [param callback].
func _on_scenario_scenes_loaded(batch: SceneBatchLoader, callback) -> void:
	_scenario_scenes = batch  # Keeps the ship scenes cached until populate().
	for id in _scenario.systems:
		var scene := batch.scenes.get(Content.path_of(id)) as PackedScene
		if scene == null:
			Log.log(["Scenario system ", id, " failed to load"], Log.MessageType.ERROR)
			continue
		$Systems.add_child(scene.instantiate())
	if callback:
		callback.call()


## The loaded system node for a system content ID, or null.
func _system_node(content_id: StringName) -> Node:
	var path := Content.path_of(content_id)
	if path.begins_with("uid://"):
		path = ResourceUID.uid_to_path(path)
	for system in $Systems.get_children():
		if system.scene_file_path == path:
			return system
	return null


func _on_main_menu_new_game(g_name, _player_name, _port, _server_password, _player_password):
	game_name = g_name
	var callback := Callable(self, "finish_setup_galaxy_client")
	setup_new_galaxy(false, callback)


func _on_main_menu_join_game(_ip, _port, _player_name, _server_password, _player_password):
	pass


func finish_setup_galaxy_all() -> void:
	if not get_tree().root.get_node("entry").is_server:
		_scenario_scenes = null
		return
	var systems := {}
	for id in _scenario.systems:
		systems[id] = _system_node(id)
	ScenarioLoader.populate(_scenario, Content.registry, factions, systems, ids,
			multiplayer.get_unique_id())
	_scenario_scenes = null  # Placed ships hold their own references now.


func finish_setup_galaxy_client():
	update_graphics()
	_join_menu_wanted = true
	_try_show_join_menu()
	finish_setup_galaxy_all()


## Why a spawn request is refused, or "" if it is acceptable. Everything here
## comes from a client, so nothing is trusted: the faction must exist and take
## players, and the system must be one of ours. A plain name check isn't enough
## for the system, since a path such as "../.." would also resolve to a node.
static func check_spawn_request(registry: FactionRegistry, systems: Node,
		faction_id: int, system_name: String) -> String:
	var faction := registry.get_by_id(faction_id)
	if faction == null:
		return "unknown faction %d" % faction_id
	if not faction.accept_players:
		return "faction %s does not accept players" % faction.resource_name
	var system := systems.get_node_or_null(NodePath(system_name))
	if system == null or system.get_parent() != systems:
		return "unknown system %s" % system_name
	return ""


## The living character of player [param player_id] anywhere under
## [param systems], or null. A player has at most one.
static func find_player_character(systems: Node, player_id: int) -> Character:
	for node in systems.find_children("*", "", true, false):
		var c := node as Character
		if c and c._player_pilot_id == player_id and not c.is_queued_for_deletion():
			return c
	return null


@rpc("any_peer", "call_local")
func first_spawn_player(faction_id: int, system_name: String, spawner_name: String) -> void:
	if not multiplayer.is_server():
		return
	var remote_id := multiplayer.get_remote_sender_id()
	# If the host is calling this function, remote id is 0, change to its actual id
	if remote_id == 0:
		remote_id = multiplayer.get_unique_id()
	Log.log(["Spawn request from peer ", remote_id, ": faction ", faction_id, " at ",
			spawner_name if spawner_name else "(first)", " in ", system_name], Log.MessageType.QUESTION)
	var player: Player = $Players.find_player_by_netid(remote_id)
	if player == null:
		Log.log(["Spawn refused for peer ", remote_id, ": not logged in"], Log.MessageType.WARNING)
		return
	var refusal := check_spawn_request(factions, $Systems, faction_id, system_name)
	if not refusal and find_player_character($Systems, player.player_id):
		refusal = "already in the world"
	if refusal:
		Log.log(["Spawn refused for ", player.name, ": ", refusal], Log.MessageType.WARNING)
		return
	var faction: Faction = factions.get_by_id(faction_id)
	var points := _spawn_points(faction)
	refusal = check_spawn_point(points, system_name, spawner_name)
	if refusal:
		Log.log(["Spawn refused for ", player.name, ": ", refusal], Log.MessageType.WARNING)
		return
	var at: String = spawner_name if spawner_name else points[system_name][0]
	var spawn_ship: Ship = get_node("Systems/%s/ships" % system_name).get_node(at)
	player_enter_system.rpc_id(remote_id, system_name)
	var player_pilot := spawn_ship.spawn_crew(
			Character.pilot_data(player.name, faction_id, remote_id, ids.next_pilot(),
				player.player_id))
	if player_pilot == null:
		return
	faction.add_member(player_pilot)
	Log.log(["Created pilot: ", player_pilot, " in faction ", faction.resource_name, " with mpid: ", player_pilot.multiplayer_id], Log.MessageType.SUCCESS)


func pause_game():
	get_tree().paused = true


func unpause_game():
	get_tree().paused = false


func _process(delta: float) -> void:
	_play_time += delta
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_interest_timer -= delta
		if _interest_timer <= 0:
			_interest_timer = INTEREST_SECONDS
			refresh_interest()
	if get_tree().root.get_node("entry").is_server:
		_sync_timer -= delta
		if _sync_timer <= 0:
			_sync_timer = _sync_interval
			_rpc_sync_time.rpc(_play_time)


## Server: works out again which ships each client knows (Interest), from where
## each client's player and each ship is now. Runs every INTEREST_SECONDS, and
## at once when that changes: a client connects, a ship is launched (once it is
## in place: a ship's spawn goes with its place at that moment), a crew member
## boards (before any RPC to them: Godot refuses an RPC to a peer that can't
## see the node).
func refresh_interest() -> void:
	var systems: Array[System] = []
	for node in $Systems.get_children():
		if node is System:
			systems.append(node)
	var ships := {}
	for system in systems:
		for ship in system.get_ships():
			ships[ship] = system
	var peers := {}
	var pictures := {}  # One per top-level faction this refresh.
	for peer in multiplayer.get_peers():
		var player: Player = $Players.find_player_by_netid(peer)
		var character := find_player_character($Systems, player.player_id) if player else null
		peers[peer] = view_of(character, pictures) if character else null
	var changes := interest.update(peers, ships)
	# Spawn or despawn on each client (N5a2). A leaving ship stops its unreliable
	# syncs now and is despawned at the next refresh (see Interest).
	for peer in changes:
		# Lost contact (still in the world, no longer known): the client leaves a
		# ghost where it was last seen (N5c). Freed ones go as "hidden" only.
		for ship: Ship in changes[peer]["leaving"]:
			_contact_lost.rpc_id(peer, ship.ship_id, contact_data(ship, NetworkTime.tick))
		for key in ["leaving", "hidden"]:
			for ship in changes[peer][key]:  # Untyped: a hidden one may have been freed.
				if is_instance_valid(ship) and (ship as Ship).is_inside_tree():
					(ship as Ship).update_interest(peer, false, key == "hidden")
		for ship: Ship in changes[peer]["shown"]:
			ship.update_interest(peer, true)
	for peer in changes:
		Log.log(["Interest: peer ", peer, " now knows ", ships.keys().filter(
				func(s: Ship) -> bool: return interest.knows(peer, s)).size(), " ships (",
				changes[peer]["shown"].size(), " more, ", changes[peer]["leaving"].size(), " leaving, ",
				changes[peer]["hidden"].size(), " gone)"],
				Log.MessageType.INFO)
	interest_refreshed.emit()


## Server: what a client is told about [param ship] when its side loses contact
## (N5c), as last seen at server tick [param tick]. Stations are immobile: their
## ghosts don't drift or fade.
static func contact_data(ship: Ship, tick: int) -> Dictionary:
	var system := System.find_for(ship)
	return {
		"name": String(ship.name), "faction_id": ship.faction_id,
		"system": String(system.name) if system else "",
		"transform": ship.global_transform, "velocity": ship.linear_velocity,
		"immobile": ship.is_station, "tick": tick,
	}


## Client: the server says this player's side lost contact with [param ship_id]
## (it is about to be despawned here). Record it and put a ghost where it was.
@rpc("authority", "call_remote", "reliable")
func _contact_lost(ship_id: int, data: Dictionary) -> void:
	contacts.lost(ship_id, data)
	var system := get_node_or_null(NodePath("Systems/" + String(data.get("system", ""))))
	if not system is System:
		return
	var ghosts: Node = system.get_node_or_null("Ghosts")
	if ghosts == null:
		ghosts = Node3D.new()
		ghosts.name = "Ghosts"
		system.add_child(ghosts)
	var old := ghosts.get_node_or_null("Ghost%d" % ship_id)
	if old:
		old.free()
	var marker := GhostMarker.new()
	marker.setup(contacts, ship_id, func() -> float:
			return snapshot_clock.server_tick(SnapshotClock.local_now()))
	ghosts.add_child(marker)
	Log.log(["Lost contact with ", data.get("name", ship_id)], Log.MessageType.INFO)


## Client: ship [param ship_id] exists here again (Ship._ready): contact regained.
func contact_regained(ship_id: int) -> void:
	if contacts.get_contact(ship_id).is_empty() or contacts.get_contact(ship_id)["in_contact"]:
		return
	contacts.regained(ship_id)
	Log.log(["Contact regained with ", contacts.get_contact(ship_id)["name"]], Log.MessageType.INFO)


## Server: what [param character]'s player may know (Interest.view): their
## system, the ship they are aboard, and their side's sensor picture (fog of
## war, N5b3): the top-level faction's shared picture, the pictures of excluded
## factions they belong to (one-way: covert wings see the shared one too), and
## what the ship they are aboard detects. [param pictures] caches pictures by
## top-level faction across one refresh.
func view_of(character: Character, pictures := {}) -> Dictionary:
	var faction := character.faction
	var top := faction.top_faction if faction else null
	var picture := {}
	if top:
		if not pictures.has(top):
			pictures[top] = pictures_of(top)
		var side: Dictionary = pictures[top]
		picture = (side["shared"] as Dictionary).duplicate()
		var f := faction
		while f:
			if side["groups"].has(f):
				picture.merge(side["groups"][f])
			f = f.parent_faction
	var aboard := character.current_ship
	if aboard:
		picture.merge(Interest.picture([aboard], {aboard: aboard.detected_ships}))
	return Interest.view(System.find_for(character), aboard, picture)


## Server: [param top]'s sensor pictures: "shared", every ship of its own (its
## factions all keep their ships on the top-level one) and what their sensors
## detect (Ship.detected_ships, from each system's sensor scan); and "groups",
## {excluded faction: picture} for the ships of each faction kept out of the
## shared one (its nearest excluded faction). Ships excluded on their own are in
## none: only their crew know them. TODO: sharing with other sides.
static func pictures_of(top: Faction) -> Dictionary:
	var shared: Array = []
	var groups := {}  # Excluded faction -> its ships.
	var detections := {}
	for ship in top.owned_ships:  # Untyped: a destroyed ship may be listed until freed.
		if not is_instance_valid(ship) or (ship as Ship).excluded_from_picture:
			continue
		detections[ship] = (ship as Ship).detected_ships
		var group := _excluded_group((ship as Ship).faction, top)
		if group:
			if not groups.has(group):
				groups[group] = []
			groups[group].append(ship)
		else:
			shared.append(ship)
	var out := {"shared": Interest.picture(shared, detections), "groups": {}}
	for group in groups:
		out["groups"][group] = Interest.picture(groups[group], detections)
	return out


## The nearest faction from [param faction] up to (not including) [param top]
## that is excluded from the shared picture, or null.
static func _excluded_group(faction: Faction, top: Faction) -> Faction:
	var f := faction
	while f and f != top:
		if f.excluded_from_picture:
			return f
		f = f.parent_faction
	return null


## Why [param requester] may not change whether [param target] (a Ship or a
## Faction) is kept out of its side's shared picture, or "": only the leader of
## the faction that owns the ship (for a faction: that faction), or of a
## faction above it, may. Nothing a client sends is trusted: call this first.
static func check_exclusion_change(requester: Character, target: Object) -> String:
	var faction: Faction = null
	if target is Ship:
		faction = (target as Ship).faction
	elif target is Faction:
		faction = target
	if faction == null:
		return "no faction owns that"
	var f := faction
	while f:
		if f.leader_id != 0 and f.leader_id == requester.pilot_id:
			return ""
		f = f.parent_faction
	return "%s doesn't lead %s or a faction above it" % [requester.name, faction.resource_name]


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_sync_time(new_time: float) -> void:
	_play_time = new_time
	

func _on_network_connection_succeeded() -> void:
	finish_setup_galaxy_client()


func _on_join_game_request_spawn(faction_name: String, system_name: String, spawner_name: String) -> void:
	var faction := factions.find_by_name(faction_name)
	if faction == null:
		return
	rpc("first_spawn_player", faction.faction_id, system_name, spawner_name)
	$CanvasLayer/JoinGame.visible = false


## The join menu picked a faction: ask the server where it can spawn (the client
## may not know of those ships at all, netcode N5b2).
func _on_join_game_request_faction(faction_name: String) -> void:
	var faction := factions.find_by_name(faction_name)
	if faction == null:
		return
	if multiplayer.is_server():
		$CanvasLayer/JoinGame.show_spawn(faction_name, _spawn_points(faction))
	else:
		_request_spawn_points.rpc_id(1, faction.faction_id)


## Server: a client's join menu wants [param faction_id]'s spawn points. Only for
## a faction that takes players; the answer goes to the sender.
@rpc("any_peer", "call_remote", "reliable")
func _request_spawn_points(faction_id: int) -> void:
	if not multiplayer.is_server():
		return
	var faction := factions.get_by_id(faction_id)
	if faction == null or not faction.accept_players:
		return
	_receive_spawn_points.rpc_id(multiplayer.get_remote_sender_id(), faction.resource_name,
			_spawn_points(faction))


## Client: the server's answer to _request_spawn_points.
@rpc("authority", "call_remote", "reliable")
func _receive_spawn_points(faction_name: String, points: Dictionary) -> void:
	$CanvasLayer/JoinGame.show_spawn(faction_name, points)


## The nearest capital ship or station on [param pilot]'s side (its own faction
## or an ancestor), not counting [param destroyed], or null.
## [param destroyed] is still in the ship list: it is only queued for freeing.
static func pick_respawn_ship(pilot: Character, destroyed: Ship, ships: Array) -> Ship:
	var own := pilot.faction
	if own == null:
		return null
	var best: Ship = null
	var best_distance := INF
	for target: Ship in ships:
		if target == destroyed or not (target.is_capital or target.is_station):
			continue
		var side := target.faction
		if side == null or not (side == own or own.is_a_parent(side)):
			continue
		var d := target.global_position.distance_to(destroyed.global_position)
		if d < best_distance:
			best_distance = d
			best = target
	return best


func _on_ship_destroyed(ship: Ship):
	## This is ONLY for respawning characters. The destruction of the ship itself
	## is handled elsewhere.
	#TODO: Find closest faction capital or station with capacity and the player respawns there
	#This has to be done at the galaxy level, for now, incase we have to hop to other systems
	#Depending on gamemode we might want something like allegiance with lifepods,
	#X4 with spacesuits (or starfury escape pods), or insta-respawn
	
	# This will also respawn npcs for now
	var system: System = ship.get_current_system()
	var ships := system.get_ships()
	for old_pilot: Character in ship.get_crew():
		var proposed_ship := pick_respawn_ship(old_pilot, ship, ships)
		if proposed_ship:
			#TODO: Genealize this to a multicrew craft
			proposed_ship.spawn_crew(old_pilot.serialize())
