class_name Galaxy
extends Node

var game_name := "default"
var render_resolution := Vector2i(0, 0)
@onready var msaa = AppConfig.get_value("graphics", "msaa")
@onready var taa = AppConfig.get_value("graphics", "taa")
var active_galaxy := false

var ship_id_counter := 0

signal enter_system(system_name)
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


func player_enter_system(system_name) -> void:
	var system: SubViewportContainer = get_node("Systems/" + system_name)
	system.get_node("SubViewport").size = DisplayServer.window_get_size()
	system.visible = true
	#Music Hack
	system.get_node("SubViewport/AudioStreamPlayer").playing = true


func find_pilot_by_network_id(id: int) -> Pilot:
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


func _ready():
	#TODO: Not in ready! Better way to load faction from disk, or stream from server on join
	# IF we do streaming, then move to galaxy setup function
	var ea := Faction.new_faction("Earth Alliance", false, false, false)
	var b5 := Faction.new_faction("Babylon 5", false, false, false)
	b5.parent_faction = ea
	var wing := Faction.new_faction("Alpha Wing", true, true, false)
	wing.parent_faction = b5
	wing = Faction.new_faction("Beta Wing", true, true, false)
	wing.parent_faction = b5
	wing = Faction.new_faction("Delta Wing", true, true, false)
	wing.parent_faction = b5
	wing = Faction.new_faction("Zeta Wing", true, true, false)
	wing.parent_faction = b5


func setup_new_galaxy(dedicated=false, callback = null):
	if dedicated:
		callback = Callable(self, "finish_setup_galaxy_all")
	if not active_galaxy and get_tree().root.get_node("entry").is_server:
		emit_signal("load_scene", "res://systems/test_system/test_system.tscn", $Systems, false, true, callback)
		active_galaxy = true
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
		var babylon5 := preload("res://ships/earth alliance/babylon 5/babylon_5.tscn").instantiate()
		$Systems.add_station(babylon5, "test_system")
		var b5commander: Pilot = Pilot.new_pilot("Commendar Eclair")
		var b5_faction: Faction = Faction.get_faction("Babylon 5")
		b5_faction.add_member(b5commander)
		$"Systems/test_system/SubViewport/ships/Babylon 5".add_captain(b5commander)
		b5commander.multiplayer_id = multiplayer.get_unique_id()
		
		var b5botpilot: Pilot = Pilot.new_pilot("Karren Waffer")
		var zeta_wing: Faction = Faction.get_faction("Zeta Wing")
		zeta_wing.add_member(b5botpilot)
		$"Systems/test_system/SubViewport/ships/Babylon 5".add_passenger(b5botpilot)
		b5botpilot.multiplayer_id = multiplayer.get_unique_id()
		
		var hyperion := preload("res://ships/earth alliance/hyperion/hyperion.tscn").instantiate()
		hyperion.name = "EASS Hyperion"
		hyperion.position = Vector3(5800, 0, 0)
		$Systems.add_ship(hyperion, "test_system")


func finish_setup_galaxy_client():
	update_graphics()
	$CanvasLayer/JoinGame.build_faction_menu()
	$CanvasLayer/JoinGame.visible = true
	finish_setup_galaxy_all()


@rpc("any_peer", "call_local")
func first_spawn_player(faction_id: int, system_name: String, spawner_name: String, next_faction_id: int) -> void:
	if not multiplayer.is_server():
		return
	var remote_id := multiplayer.get_remote_sender_id()
	# If the host is calling this function, remote id is 0, change to its actual id
	if remote_id == 0:
		remote_id = multiplayer.get_unique_id()
	Logger.log(["Attemping Created player pilot: in faction ", faction_id, " with mpid: ", remote_id], Logger.MessageType.QUESTION)
	Faction._next_id = next_faction_id
	var player: Player = $Players.find_player_by_netid(remote_id)
	var player_pilot: Pilot = Pilot.new_pilot(player.name)
	var faction: Faction = Faction.factions[faction_id]
	faction.add_member(player_pilot)
	player_pilot._player_pilot_id = player.player_id
	player_pilot.set_multiplayer_id(remote_id)
	
	#TODO: Change this to be via system_name and spawner_name
	player_enter_system(system_name)
	$"Systems/test_system/SubViewport/ships/Babylon 5".add_passenger(player_pilot)
	Logger.log(["Created pilot: ", player_pilot, " in faction ", faction.resource_name, " with mpid: ", player_pilot.multiplayer_id], Logger.MessageType.SUCCESS)


func _on_network_connection_succeeded() -> void:
	finish_setup_galaxy_client()


func _on_join_game_request_spawn(faction_name: String, system_name: String, spawner_name: String) -> void:
	rpc("first_spawn_player", Faction.get_faction(faction_name).faction_id, system_name, spawner_name, Faction._next_id)
	$CanvasLayer/JoinGame.visible = false


func _on_join_game_request_faction(faction_name: String) -> void:
	$CanvasLayer/JoinGame.show_spawn(get_spawn_points(Faction.get_faction(faction_name)))
