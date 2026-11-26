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
## Server: which ships each client is told about (netcode N5). Kept up to date
## every INTEREST_SECONDS and when a ship appears (refresh_interest).
var interest := Interest.new()
const INTEREST_SECONDS := 0.5
var _interest_timer := 0.0

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


func get_spawn_points(faction: Faction) -> Dictionary:
	# For now return spawn points in {system_name: [spawn_ship]} type format
	# Eventually we will migrate to some other type of thing, such as checking
	# Inventory for ships
	# Also, eventually, we will also only launch from spawn points we are
	# on the team of
	var spawn_points = {}
	for system in $Systems.get_children():
		if system is System:
			for ship in system.get_ships():
				if ship.has_spawn_points:
					if system not in spawn_points:
						spawn_points[system] = []
					spawn_points[system].append(ship)
	# TODO: Add hyperspace here
	# TODO: Add random generated deep space systems here
	return spawn_points


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
	Log.log(["Attemping Created player pilot: in faction ", faction_id, " with mpid: ", remote_id], Log.MessageType.QUESTION)
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
	#TODO: Change this to be via system_name and spawner_name
	player_enter_system.rpc_id(remote_id, system_name)
	var player_pilot := ($"Systems/test_system/ships/Babylon 5" as Ship).spawn_crew(
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
## each client's player and each ship is now.
func refresh_interest() -> void:
	var systems: Array[System] = []
	for node in $Systems.get_children():
		if node is System:
			systems.append(node)
	var ships := {}
	var spawn_systems: Array[System] = []
	for system in systems:
		for ship in system.get_ships():
			ships[ship] = system
			if ship.has_spawn_points and system not in spawn_systems:
				spawn_systems.append(system)
	var peers := {}
	for peer in multiplayer.get_peers():
		peers[peer] = _player_system(peer)
	var changes := interest.update(peers, ships, spawn_systems)
	for peer in changes:
		Log.log(["Interest: peer ", peer, " now knows ", ships.keys().filter(
				func(s: Ship) -> bool: return interest.knows(peer, s)).size(), " ships (",
				changes[peer]["shown"].size(), " more, ", changes[peer]["hidden"].size(), " fewer)"],
				Log.MessageType.INFO)


## Server: the system [param peer]'s player character is in, or null (no
## character yet, or not logged in).
func _player_system(peer: int) -> System:
	var player: Player = $Players.find_player_by_netid(peer)
	if player == null:
		return null
	var character := find_player_character($Systems, player.player_id)
	return System.find_for(character) if character else null


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


func _on_join_game_request_faction(faction_name: String) -> void:
	$CanvasLayer/JoinGame.show_spawn(get_spawn_points(factions.find_by_name(faction_name)))


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
