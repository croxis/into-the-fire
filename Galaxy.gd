extends Node

var PlayerScene := preload("res://ships/earth alliance/aurora_starfury/auora_starfury.tscn")

signal enter_system(system_name)


func _ready():
	# Debug
	get_spawn_points("")


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
	#if player_id == multiplayer.get_unique_id():
	#	show_spawn()


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
	$spawn_picker.show_spawn(get_spawn_points(""))


func _on_network_connection_succeeded():
	show_spawn()


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
	$spawn_picker.visible = false
	
	
func set_resolution(resolution: Vector2i) -> void:
	print_debug("Setting resolution: ", resolution)
	for subviewportcontainer in $Systems.get_children():
		#subviewportcontainer.size = resolution
		subviewportcontainer.get_node("SubViewport").size = resolution


func set_msaa(status):
	for subviewportcontainer in $Systems.get_children():
		subviewportcontainer.get_node("SubViewport").msaa_3d = status


func set_taa(status):
	for subviewportcontainer in $Systems.get_children():
		subviewportcontainer.get_node("SubViewport").use_taa = status
