#@tool
extends RigidBody3D
class_name Ship

@export var ship_id: int

@export var faction_id: int:
	#TODO: Need to give the ship faction ownership. There needs to be rules on this.
	# Option 1: Ships are owned at the top level faction. Simple.
	# Option 2: Fancy permission system...
	# 1) Factions need some sort of permission control. If B5 owns a ship, can any earthforce fly it?
	# 2) If alpha wing member flies the B5 ship, the ownership should stay b5
	# 3) A ship can be gifted by the faction owner.
	# 4) A transfer can happen by parent faction commanders
	# For now....
	set(new_id):
		if faction:
			if faction.faction_id == new_id:
				return
			faction.remove_ship(self)
		faction_id = new_id
		faction.add_ship(self)
		# A zero value is no faction.
		Log.log(["Player gets new faction ID:", name, faction.resource_name, faction.faction_id, faction_id], Log.MessageType.INFO)
@export var faction: Faction:
	set(new_faction):
		assert(false, "BOO! DO NOT SET FACTIONS DIRECTLY")
	get:
		return Faction.factions[faction_id]

@export_node_path("Camera3D") var camera_path: NodePath
@onready var passenger_camera: Camera3D = get_node_or_null(camera_path)

@export var ship_class := ""

@export var max_health := 100
@export var is_station := false:
	set(set_station):
		if set_station:
			add_to_group("station")
		else:
			remove_from_group("station")
	get:
		return is_in_group("station")
@export var is_capital := false:
	set(set_capital):
		if set_capital:
			add_to_group("capital")
		else:
			remove_from_group("capital")
	get:
		return is_in_group("capital")
@export var has_spawn_points := false

@export var sensor: Sensor

@export var em_output_base: float = 1.0
@export var neutron_output_base: float = 1.0
var em_output := 1.0
var neutron_output := 1.0

var detected_ships: Array[Ship] = []

var galaxy: Galaxy

var health := max_health:
	set(new_health):
		health = new_health
		if has_node("SubViewportCenter"):
			$SubViewportCenter/center_ui.set_health(health)
		if (health <= 0.0):
			destroy()
var engine_length = 7.5
#var thruster_force: Vector3 = Vector3(0, 0, 0)
#var thruster_torque: Vector3 = Vector3(0, 0, 0)
var acceleraction: Vector3 = Vector3(0, 0, 0)
var _debug_all_stop := false

var start_velocity := Vector3(0, 0, 0)

@export var local_angular_velocity: Vector3:
	get:
		return angular_velocity * global_basis

var is_spawning := false

signal destroyed(ship: Ship)


# Called when the node enters the scene tree for the first time.
func _ready():
	# If in editor simply disable processing as it's not needed here
	if (Engine.is_editor_hint()):
		set_physics_process(false)	
	can_sleep = false
	#target_rot = rotation_degrees
	
	galaxy = get_tree().root.get_node("entry/Galaxy")
	destroyed.connect(galaxy._on_ship_destroyed)
	print_debug("Frozen: ", freeze, freeze_mode)


func add_passenger(pilot: Character):
	if $Crew.add_passenger(pilot) and pilot.multiplayer_id:
		set_camera.rpc_id(pilot.multiplayer_id)
		Log.log(["Passenger added to ", name, " ", ship_id, " id ", pilot.multiplayer_id], Log.MessageType.INFO)
		set_capital_ui.rpc_id(pilot.multiplayer_id)


func get_crew() -> Array[Character]:
	var crew: Array[Character] = []
	for c in $Crew.get_children():
		crew.append(c)
	return crew


@rpc("call_local")
func set_camera():
	Log.log(["Setting Camera"], Log.MessageType.QUESTION)
	passenger_camera.far = 30000
	passenger_camera.near = 0.3
	passenger_camera.current = true


@rpc("call_local")
func set_capital_ui():
	Log.log(["Is capital or station?", is_capital, ", ", is_station], Log.MessageType.INFO)
	if is_capital or is_station:
		$CapitalUI.visible = true
	else:
		$CapitalUI.visible = false


@rpc("call_local")
func disable_capital_ui():
	$CapitalUI.visible = false


func debug_set_health(new_health):
	health = new_health


func _integrate_forces(state: PhysicsDirectBodyState3D):
	if is_station:
		return
	if _debug_all_stop:
		state.angular_velocity = Vector3(0,0,0)
		state.linear_velocity = Vector3(0,0,0)
		_debug_all_stop = false


func _rollback_tick(dt, _tick, _is_fresh):
	if is_station:
		return
	
	for thruster in $Engines.thrusters:
		apply_force(global_transform.basis * thruster.force_vector, global_transform.basis * thruster.position)
	
	acceleraction = (linear_velocity - start_velocity) / dt
	start_velocity = linear_velocity


func _physics_process(dt: float) -> void:
	_rollback_tick(dt, 0, 0)


func _process(_delta: float) -> void:
	pass
	#DebugDraw3D.draw_arrow_ray(global_position, target_rot, 32.0, Color.LAVENDER, 0.5)
	#DebugDraw3D.draw_arrow(global_position, global_position+Vector3(0,0,-2050), Color.MAGENTA, 32, false)
	#DebugDraw3D.draw_arrow(position, position+Vector3(0,2000,-2050), Color.MAGENTA, 32, false)
	#DebugDraw2D.set_text("Frames drawn", Engine.get_frames_drawn())


func bullet_hit(damage, bullet_global_trans):
	var BASE_BULLET_BOOST = 1
	var direction_vect = bullet_global_trans.basis.z.normalized() * BASE_BULLET_BOOST
	apply_impulse((bullet_global_trans.origin - global_transform.origin).normalized(), direction_vect * damage)
	health -= damage


func destroy() -> void:
	emit_signal("destroyed", self)
	faction.remove_ship(self)
	queue_free()


func find_free_spawner() -> Array:
	var s = $Spawner.find_free_spawner()
	return s


func _on_area_3d_dock_body_entered(body) -> void:
	if body == self:
		#can't dock with self, silly
		return
	if body is not Ship:
		return
	if body.is_spawning:
		return
	Log.log([body, " ship entered dock on ", name], Log.MessageType.INFO)
	for c in body.get_crew():
		add_passenger(c)
	body.queue_free()


func _on_crew_child_exiting_tree(_node: Node) -> void:
	return
	Log.log(["_on_crew_child_exiting_tree"], Log.MessageType.INFO)
	$CapitalUI.visible = false


func _on_button_launch_pressed() -> void:
	var system_name := get_parent().get_parent().get_parent().name
	galaxy.rpc("request_spawn", system_name, name)
	$CapitalShipControl.visible = false


func _on_capital_ui_request_launch() -> void:
	var player: Player = galaxy.get_node('Players').find_player_by_netid(multiplayer.get_unique_id())	
	Log.log(["_on_capital_ui_request_launch ship_id:", ship_id, player.name, multiplayer.get_unique_id()], Log.MessageType.INFO)
	rpc("request_launch", ship_id, player.player_id)


@rpc("any_peer", "call_local")
func request_launch(p_ship_id: int, pilot_id: int):
	if not multiplayer.is_server():
		return
	var remote_id := multiplayer.get_remote_sender_id()
	# If the host is calling this function, remote id is 0, change to its actual id
	if remote_id == 0:
		remote_id = multiplayer.get_unique_id()
	
	Log.log(["Spawn requested in ", get_current_system().name, " ", name, " by ", remote_id], Log.MessageType.QUESTION)
	var top_system := get_current_system()
	#var system := top_system.get_node("SubViewport")

	var spawn := find_free_spawner()
	var spawn_point = spawn[0]
	var spawn_position = spawn[1]
	print_debug("Spawn: ", spawn)
	#TODO: Keep an inventory of docked ships
	
	var PlayerScene := load("res://ships/earth alliance/aurora_starfury/auora_starfury.scn")
	var new_ship: Ship = PlayerScene.instantiate()
	new_ship.is_spawning = true
	
	#TODO: Pull ship from existing invetory using the id
	new_ship.ship_id = galaxy.ship_id_counter
	galaxy.ship_id_counter += 1
	top_system.add_ship(new_ship)
	new_ship.global_transform.origin = spawn_position
	spawn_point.spawn_ship(new_ship)
	var old_pilot: Character
	if pilot_id:
		old_pilot = $Crew.remove_passenger_by_id(pilot_id)
	else:
		old_pilot = $Crew.remove_passenger_by_multiplayerid(remote_id)
	new_ship.faction_id = old_pilot.faction_id
	var pilot: Character = new_ship.get_node("CrewMultiplayerSpawner").spawn(old_pilot.serialize())
	#TODO: Genealize this to a multicrew craft
	var cockpit: Console = new_ship.get_node("Consoles/Cockpit") as Console
	
	cockpit.occupy(pilot)
	old_pilot.queue_free()
	#new_ship.set_camera.rpc_id(pilot.multiplayer_id)
	disable_capital_ui.rpc_id(pilot.multiplayer_id)
	await get_tree().create_timer(2.0).timeout
	new_ship.is_spawning = false
	for c in $Consoles.get_children():
		if c is Console:
			c = c as Console
			if c.has_capability("Helm"):
				c.launch_completed()
	Log.log(["Spawn complete for ", pilot], Log.MessageType.SUCCESS)


func get_current_system() -> System:
	return get_parent().get_parent().get_parent()


func sensor_check(other_ship: Ship) -> bool:
	var detected := false
	var distance := global_position.distance_to(other_ship.global_position)
	#TODO: Calculate angular size of other ship. IF bigger than 1 degree, it is detected.
	var em_signal := other_ship.em_output / pow(distance/1000.0, 2) # Convert to km. Signal strength of 1.0 can be detected by a sensor of 1.0 at 1 km
	var neuteno_signal := other_ship.neutron_output / pow(distance/1000.0, 2)
	if em_signal > sensor.em_sensitive or neuteno_signal > sensor.neutrino_sensitive:
		detected = true
	if detected:
		detected_ships.append(other_ship)
	else:
		detected_ships.erase(other_ship)
	return detected
