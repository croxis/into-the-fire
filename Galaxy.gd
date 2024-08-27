class_name Galaxy
extends Node

var PlayerScene := preload("res://ships/earth alliance/aurora_starfury/auora_starfury.tscn")
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
			for station in viewport.get_node("stations").get_children():
				if station.has_spawn_points:
					if system not in spawn_points:
						spawn_points[system] = []
					spawn_points[system].append(station)
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


@rpc("any_peer", "call_local")
func show_spawn(faction: Faction) -> void:
	$CanvasLayer/spawn_picker.show_spawn(get_spawn_points(faction))


@rpc("any_peer", "call_local")
func request_spawn(system_name: String, spawner_name: String):
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	Logger.log(["Spawn requested in ", system_name, " ", spawner_name, " by ", peer_id], Logger.MessageType.QUESTION)
	var top_system := $Systems.get_node(system_name)
	var system := top_system.get_node("SubViewport")
	var spawner: Node3D
	if system.get_node("stations").has_node(spawner_name):
		spawner = system.get_node("stations").get_node(spawner_name)
	elif system.get_node("ships").has_node(spawner_name):
		spawner = system.get_node("ships").get_node(spawner_name)
	else:
		print_debug("Critical error! ", system_name, " ", spawner_name, " does not exist")
		return
	var spawn_point = spawner.find_free_spawner()
	var spawn_position = spawn_point.global_transform.origin
	var ship := PlayerScene.instantiate()
	#ship._player_pilot_id = peer_id
	ship.ship_id = ship_id_counter
	ship_id_counter += 1
	system.get_node("ships").add_child(ship, true)
	ship.global_transform.origin = spawn_position
	ship.connect("destroyed", player_died)
	
	var old_pilot: Pilot = find_pilot_by_network_id(peer_id)
	var pilot: Pilot = ship.get_node("CrewMultiplayerSpawner").spawn({"name": old_pilot.name, "multiplayer_id": old_pilot.multiplayer_id})
	pilot._faction_name = old_pilot._faction_name
	pilot._player_pilot_id = old_pilot._player_pilot_id
	ship.add_pilot(pilot)
	old_pilot.queue_free()
	ship.set_camera.rpc_id(pilot.multiplayer_id)
	Logger.log(["Spawn complete for ", pilot], Logger.MessageType.SUCCESS)
	

func find_pilot_by_network_id(id: int) -> Pilot:
	for pilot in $Systems.find_children("*", "Pilot", true, false):
		if pilot.multiplayer_id == id:
			return pilot
	return null
	

func _on_spawn_picker_request_spawn(system_name, spawner_name):
	rpc("request_spawn", system_name, spawner_name)
	$CanvasLayer/spawn_picker.visible = false
	
	
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


func setup_new_galaxy(dedicated=false, callback = null):
	if dedicated:
		callback = Callable(self, "finish_setup_galaxy_all")
	#if not active_galaxy and multiplayer.is_server():
	if not active_galaxy and get_tree().root.get_node("entry").is_server:
		#print(active_galaxy, " ", multiplayer.is_server())
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
	# Hack until we figure"res://ships/earth alliance/babylon 5/babylon_5.tscn" out what we are doing #
	#if multiplayer.is_server():
	if get_tree().root.get_node("entry").is_server:
		var babylon5 := preload("res://ships/earth alliance/babylon 5/babylon_5.tscn").instantiate()
		$Systems.add_station(babylon5, "test_system")
		var pilot = preload("res://ship_systems/pilots/Pilot.tscn")
		var b5commander: Pilot = pilot.instantiate()
		b5commander.name = "Commendar Eclair"
		b5commander.set_faction($"Factions/Earth Alliance/Babylon 5")
		$"Systems/test_system/SubViewport/stations/Babylon 5".add_captain(b5commander)
		b5commander.multiplayer_id = multiplayer.get_unique_id()


func finish_setup_galaxy_client():
	update_graphics()
	$CanvasLayer/FactionPicker.build_faction_menu($Factions)
	$CanvasLayer/FactionPicker.visible = true
	finish_setup_galaxy_all()


func _on_faction_picker_request_faction(faction_name: String) -> void:
	#TODO: on clicking the different spawnpoints, the camera switches views
	$CanvasLayer/FactionPicker.visible = false
	rpc("request_faction", faction_name)
	var faction: Faction = $Factions.get_faction(faction_name)
	player_enter_system("test_system")
	show_spawn(faction)


@rpc("any_peer", "call_local")
func request_faction(faction_name):
	if not multiplayer.is_server():
		return
	var pilot = preload("res://ship_systems/pilots/Pilot.tscn")
	var player_pilot: Pilot = pilot.instantiate()
	player_pilot.set_faction($Factions.get_faction(faction_name))
	var player: Player = $Players.find_player_by_netid(multiplayer.get_remote_sender_id())
	player_pilot.name = player.name
	player_pilot._player_pilot_id = player.player_id
	player_pilot.multiplayer_id = multiplayer.get_remote_sender_id()
	$"Systems/test_system/SubViewport/stations/Babylon 5".add_passenger(player_pilot)
	player_pilot.set_multiplayer_id(multiplayer.get_remote_sender_id())
	Logger.log(["Created pilot: ", player_pilot, " in faction ", player_pilot._faction_name, " with mpid: ", player_pilot.multiplayer_id], Logger.MessageType.SUCCESS)


func _on_network_connection_succeeded() -> void:
	finish_setup_galaxy_client()
