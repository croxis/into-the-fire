class_name Galaxy
extends Node

var game_name := "default"
var render_resolution := Vector2i(0, 0)
@onready var msaa = PlayerConfig.get_config("graphics", "msaa", 0)
@onready var taa = PlayerConfig.get_config("graphics", "taa", 0)
var active_galaxy := false

@export var ship_id_counter := 0

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
signal load_scene(path, node: Node, make_active_scene: bool, show_load_screen: bool, callback)


func get_spawn_points(faction: Faction) -> Dictionary:
	# For now return spawn points in {system_name: [spawn_ship]} type format
	# Eventually we will migrate to some other type of thing, such as checking
	# Inventory for ships
	# Also, eventually, we will also only launch from spawn points we are
	# on the team of
	var spawn_points = {}
	for system in $Systems.get_children():
		if system.has_node("SubViewport"):
			var viewport = system.get_node("SubViewport")
			for ship in viewport.get_node("ships").get_children():
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


@rpc("any_peer", "call_local") ##
func player_enter_system(system_name) -> void:
	var system: SubViewportContainer = get_node("Systems/" + system_name)
	system.get_node("SubViewport").size = DisplayServer.window_get_size()
	system.visible = true
	#Music Hack
	system.get_node("SubViewport/AudioStreamPlayer").playing = true
	var remote_id := multiplayer.get_remote_sender_id()
	# If the host is calling this function, remote id is 0, change to its actual id
	if remote_id == 0:
		remote_id = multiplayer.get_unique_id()
	var player: Player = $Players.find_player_by_netid(remote_id)
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


func update_graphics():
	if self.has_node("Systems"):
		for subviewportcontainer in $Systems.get_children():
			if subviewportcontainer is SubViewportContainer:
				subviewportcontainer.get_node("SubViewport").size = render_resolution
				subviewportcontainer.get_node("SubViewport").msaa_3d = msaa
				subviewportcontainer.get_node("SubViewport").use_taa = taa


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


## Server: playtest factions. Moves to scenario data in a later step.
func _create_playtest_factions() -> void:
	factions = FactionRegistry.new()
	var ea := factions.create("Earth Alliance")
	var b5 := factions.create("Babylon 5", false, false, false, ea)
	for wing_name in ["Alpha Wing", "Beta Wing", "Delta Wing", "Zeta Wing"]:
		factions.create(wing_name, true, true, false, b5)


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
		_create_playtest_factions()
		emit_signal("load_scene", Content.path_of(&"b5:test_system"), $Systems, false, true, callback)
		active_galaxy = true
		Log.log(["Galaxy setup complete."], Log.MessageType.INFO)
	else:
		print("Galaxy already initalized")


func _on_main_menu_new_game(g_name, _player_name, _port, _server_password, _player_password):
	game_name = g_name
	var callback := Callable(self, "finish_setup_galaxy_client")
	setup_new_galaxy(false, callback)


func _on_main_menu_join_game(_ip, _port, _player_name, _server_password, _player_password):
	pass


func finish_setup_galaxy_all() -> void:
	# Hack until we figure out what we are doing #
	if get_tree().root.get_node("entry").is_server:
		var babylon5: Ship = Content.instantiate(&"b5:babylon_5")
		babylon5.ship_id = ship_id_counter
		ship_id_counter += 1
		
		$Systems.add_station(babylon5, "test_system")
		var b5_faction: Faction = factions.find_by_name("Babylon 5")
		# Set after adding to the system: ships find the registry through Galaxy.
		babylon5.faction_id = b5_faction.faction_id
		b5_faction.doctrine = FactionDoctrine.new()
		b5_faction.doctrine.minimum_patrol_fighters = 2
		b5_faction.doctrine.retreat_when_hull_percent = 0.25
		# NPC crew go through the ship's crew spawner so clients receive them too.
		var server_id := multiplayer.get_unique_id()
		var b5commander := babylon5.spawn_crew(
				Character.pilot_data("Commendar Eclair", b5_faction.faction_id, server_id))
		b5_faction.add_member(b5commander)
		$"Systems/test_system/SubViewport/ships/Babylon 5/Consoles/StationCommand".occupy(b5commander)

		b5_faction.add_member(babylon5.spawn_crew(
				Character.pilot_data("Lt Commendar Eekvonova", b5_faction.faction_id, server_id)))

		var zeta_wing: Faction = factions.find_by_name("Zeta Wing")
		for bot_name in ["Karren Waffer", "Doe John", "Susan B. Anntonny"]:
			zeta_wing.add_member(babylon5.spawn_crew(
					Character.pilot_data(bot_name, zeta_wing.faction_id, server_id)))

		var hyperion: Ship = Content.instantiate(&"b5:hyperion")
		hyperion.name = "EASS Hyperion"
		hyperion.position = Vector3(5800, 0, 0)
		$Systems.add_ship(hyperion, "test_system")
		hyperion.faction_id = factions.find_by_name("Earth Alliance").faction_id
		hyperion.ship_id = ship_id_counter
		ship_id_counter += 1


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
	if refusal:
		Log.log(["Spawn refused for ", player.name, ": ", refusal], Log.MessageType.WARNING)
		return
	var faction: Faction = factions.get_by_id(faction_id)
	#TODO: Change this to be via system_name and spawner_name
	player_enter_system.rpc_id(remote_id, system_name)
	var player_pilot := ($"Systems/test_system/SubViewport/ships/Babylon 5" as Ship).spawn_crew(
			Character.pilot_data(player.name, faction_id, remote_id, player.player_id))
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
	if get_tree().root.get_node("entry").is_server:
		_sync_timer -= delta
		if _sync_timer <= 0:
			_sync_timer = _sync_interval
			_rpc_sync_time.rpc(_play_time)


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


func _on_ship_destroyed(ship: Ship):
	## This is ONLY for respawning characters. The destruction of the ship itself
	## is handled elsewhere.
	#TODO: Find closest faction capital or station with capacity and the player respawns there
	#This has to be done at the galaxy level, for now, incase we have to hop to other systems
	#Depending on gamemode we might want something like allegiance with lifepods,
	#X4 with spacesuits (or starfury escape pods), or insta-respawn
	
	# This will also respawn npcs for now
	var system: System = ship.get_current_system()
	var ships:= system.get_ships()
	for old_pilot: Character in ship.get_crew():
		var distance: float = -1
		var proposed_ship: Ship
		for target_ship in ships:
			if not (target_ship.is_capital or target_ship.is_station):
				continue
			var own_side: bool = old_pilot.faction != null and target_ship.faction != null and (
					old_pilot.faction == target_ship.faction or old_pilot.faction.is_a_parent(target_ship.faction))
			if own_side:
				var d = abs(target_ship.global_position.distance_to(ship.global_position))
				if distance == -1 or d < distance:
					distance = d
					proposed_ship = target_ship
		if proposed_ship:
			#TODO: Genealize this to a multicrew craft
			proposed_ship.spawn_crew(old_pilot.serialize())
