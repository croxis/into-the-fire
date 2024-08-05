extends Node

var PlayerScene := preload("res://ships/earth alliance/aurora_starfury/auora_starfury.tscn")
var game_name := "default"
var render_resolution := Vector2i(0, 0)
@onready var msaa = AppConfig.get_value("graphics", "msaa")
@onready var taa = AppConfig.get_value("graphics", "taa")
var active_galaxy := false

signal enter_system(system_name)
signal load_scene(path, node: Node, make_active_scene: bool, show_load_screen: bool, callback)


func get_spawn_points(_team) -> Dictionary:
	# For now return spawn points in {system_name: [spawn_ship]} type format
	# Eventually we will migrate to some other type of thing, such as checking
	# Inventory for ships
	# Also, eventually, we will also only launch from spawn points we are
	# on the team of
	var spawn_points = {}
	for system in $Systems.get_children():
		var viewport = system.get_node("SubViewport")
		for station in viewport.get_node("Node3D/stations").get_children():
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
	#TODO: This needs to be this client only
	print_debug("Sizing: ", DisplayServer.window_get_size()," for ", system_name )
	var system: SubViewportContainer = get_node("Systems/" + system_name)
	system.get_node("SubViewport").size = DisplayServer.window_get_size()
	system.visible = true
	#Music Hack
	system.get_node("SubViewport/Node3D/AudioStreamPlayer").playing = true


@rpc("any_peer", "call_local")
func show_spawn() -> void:
	$CanvasLayer/spawn_picker.show_spawn(get_spawn_points(""))


@rpc("any_peer", "call_local")
func request_spawn(system_name, spawner_name):
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	print_debug("Spawn requested in ", system_name, " ", spawner_name, " by ", peer_id)
	var top_system := $Systems.get_node(system_name)
	var system := top_system.get_node("SubViewport/Node3D")
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
	ship._player_pilot_id = peer_id
	system.get_node("ships").add_child(ship, true)
	ship.global_transform.origin = spawn_position
	ship.connect("destroyed", player_died)
	

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
	if not active_galaxy and multiplayer.is_server():
		print("not active and is server: ", active_galaxy, " ", multiplayer.is_server())
		emit_signal("load_scene", "res://systems/test_system/test_system.tscn", $Systems, false, true, callback)
		active_galaxy = true
	else:
		print("Galaxy already initalized")


func _on_main_menu_new_game(g_name, player_name, port, server_password, player_password):
	game_name = g_name
	var callback := Callable(self, "finish_setup_galaxy_client")
	setup_new_galaxy(false, callback)


func _on_main_menu_join_game(ip, port, player_name, server_password, player_password):
	setup_new_galaxy()


func finish_setup_galaxy_all() -> void:
	# Hack until we figure out what we are doing #
	if multiplayer.is_server():
		var pilot = preload("res://ship_systems/pilots/Pilot.tscn")
		var b5commander: Pilot = pilot.instantiate()
		b5commander.name = "Commendar Eclair"
		b5commander.faction = $"Factions/Earth Alliance/Babylon 5"
		b5commander._multiplayer_id = multiplayer.get_unique_id()
		#$Systems.add_child(b5commander)
		#b5commander.reparent($"Systems/test_system/SubViewport/Node3D/stations/Babylon 5")
		$"Systems/PilotLimbo".add_child(b5commander)
		print($"Systems/PilotLimbo".get_children())
	#player_enter_system("test_system")
	#show_spawn()


func finish_setup_galaxy_client():
	update_graphics()
	$CanvasLayer/FactionPicker.build_faction_menu($Factions)
	$CanvasLayer/FactionPicker.visible = true
	finish_setup_galaxy_all()


func _on_faction_picker_request_faction(faction_name: String) -> void:
	print_debug("Faction picker: ", faction_name)
	$CanvasLayer/FactionPicker.visible = false
	rpc("request_faction", faction_name)
	$CanvasLayer/spawn_picker.visible = true


@rpc("any_peer", "call_local")
func request_faction(faction_name):
	if not multiplayer.is_server():
		return
	var pilot = preload("res://ship_systems/pilots/Pilot.tscn")
	var player_pilot: Pilot = pilot.instantiate()
	player_pilot.faction = $Factions.get_faction(faction_name)
	player_pilot._multiplayer_id = multiplayer.get_remote_sender_id()
	var player: Player = $Players.find_player_by_netid(multiplayer.get_remote_sender_id())
	player_pilot.name = player.name
	player_pilot._player_pilot_id = player.player_id
	$Systems/PilotLimbo.add_child(player_pilot)
	Logger.log(["Created pilot: ", player_pilot, " in faction ", player_pilot.faction], Logger.MessageType.SUCCESS)
