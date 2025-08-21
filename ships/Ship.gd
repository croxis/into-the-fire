#@tool
extends RigidBody3D
class_name Ship

@onready var inputs:
	get:
		if ($Crew.pilot):
			return $Crew.pilot.get_node("InputsSync")

@export var ship_id: int

@export var _player_pilot_id: int:
	get:
		if ($Crew.pilot):
			return $Crew.pilot._player_pilot_id
		else:
			return -1

var multiplayer_pilot_id: int:
	get:
		if ($Crew.pilot):
			return $Crew.pilot.multiplayer_id
		else:
			return -1

@export var faction_name: String

@export_node_path("Camera3D") var camera_path: NodePath
@onready var camera: Camera3D = get_node_or_null(camera_path)

@export var ship_class := ""

@export var target_rot = Vector3(0,0,0)
@export var target_pos = Vector3(0,0,0)
@export var target_global_transform := Transform3D()
@export var autospin := false
@export var autobreak := false

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

@export var faction: Faction:
	set(new_faction):
		if faction:
			faction.owned_ships.erase(self)
		faction = new_faction
		if self not in faction.owned_ships:
			faction.owned_ships.append(self)

var galaxy: Galaxy

var health := max_health:
	set(new_health):
		health = new_health
		if has_node("SubViewportCenter"):
			$SubViewportCenter/center_ui.set_health(health)
		if (health <= 0.0):
			destroy()
var engine_length = 7.5
var thruster_force: Vector3 = Vector3(0, 0, 0)
var thruster_torque: Vector3 = Vector3(0, 0, 0)
var acceleraction: Vector3 = Vector3(0, 0, 0)
var _debug_all_stop := false

var start_velocity := Vector3(0, 0, 0)

@export var local_angular_velocity: Vector3:
	get:
		return angular_velocity * global_basis

var is_spawning := false			

signal destroyed(ship_id)


# Called when the node enters the scene tree for the first time.
func _ready():
	# If in editor simply disable processing as it's not needed here
	Logger.log(["Creating ship with id: ", ship_id, ". Name: ", name], Logger.MessageType.QUESTION)
	if (Engine.is_editor_hint()):
		set_physics_process(false)	
	can_sleep = false
	#target_rot = rotation_degrees
	target_global_transform = global_transform
	galaxy = get_tree().root.get_node("entry/Galaxy")
	Logger.log(["Ship created: ", ship_id], Logger.MessageType.SUCCESS)
	DebugDraw3D.scoped_config().set_viewport(get_viewport())


func add_captain(pilot: Pilot):
	Logger.log(["Adding captain: ", pilot.multiplayer_id, " on ", self], Logger.MessageType.INFO)
	#TODO: Need to give the ship faction ownership. There needs to be rules on this.
	# Option 1: Ships are owned at the top level faction. Simple.
	# Option 2: Fancy permission system...
	# 1) Factions need some sort of permission control. If B5 owns a ship, can any earthforce fly it?
	# 2) If alpha wing member flies the B5 ship, the ownership should stay b5
	# 3) A ship can be gifted by the faction owner.
	# 4) A transfer can happen by parent faction commanders
	# For now....
	if not faction:
		faction = pilot.faction
	if $Crew.set_captain(pilot) and pilot.multiplayer_id:
		# This does not work as the pilot does not have a multiplayer_id when it is added.
		# This is because the multiplayerspawner only seems to work when multiplayer 
		# authority is set AFTER the pilot is child to a parent.
		set_camera.rpc_id(pilot.multiplayer_id)


func add_passenger(pilot: Pilot):
	if $Crew.add_passenger(pilot) and pilot.multiplayer_id:
		set_camera.rpc_id(pilot.multiplayer_id)
		set_capital_ui.rpc_id(pilot.multiplayer_id)


func get_crew() -> Array[Pilot]:
	var crew: Array[Pilot] = []
	for c in $Crew.get_children():
		crew.append(c)
	return crew


func add_pilot(pilot: Pilot):
	Logger.log(["Adding pilot: ", pilot.multiplayer_id, " on ", self], Logger.MessageType.INFO)
	if $Crew.set_pilot(pilot) and pilot.multiplayer_id:
		Logger.log(["Requesting camera rpc"], Logger.MessageType.QUESTION)
		set_camera.rpc_id(pilot.multiplayer_id)


@rpc("call_local")
func set_camera():
	Logger.log(["Setting Camera"], Logger.MessageType.QUESTION)
	camera.far = 30000
	camera.near = 0.3
	camera.current = true


@rpc("call_local")
func set_capital_ui():
	if is_capital or is_station:
		$CapitalUI.visible = true


func debug_set_health(new_health):
	health = new_health


func _integrate_forces(state: PhysicsDirectBodyState3D):
	if is_station:
		return
	if _debug_all_stop:
		state.angular_velocity = Vector3(0,0,0)
		state.linear_velocity = Vector3(0,0,0)
		target_rot = rotation
		_debug_all_stop = false


func _physics_process(dt: float) -> void:
	if is_station:
		return
	if not $Crew.pilot_name:
		return
	# For now throttle is capped at 1. In the future we can boost power to engines.
	# In Godot 3.2 add_force is cleared every physics frame
	if multiplayer.multiplayer_peer == null or multiplayer.get_unique_id() == multiplayer_pilot_id:
		# The client which this player represent will update the controls state, and notify it to everyone.
		inputs.update()
	
	if inputs.autobreak_toggle:
		autobreak = !autobreak
		Logger.log(["Requesting autobreak_toggle set to ", autobreak, " for ", self], Logger.MessageType.QUESTION)

	if inputs.autospin_toggle:
		autospin = !autospin
		if autospin:
			target_global_transform = global_transform
		#target_rot = rotation
		Logger.log(["Requesting autospin set to ", autospin, " for ", self], Logger.MessageType.QUESTION)

	var rotation_throttle = inputs.rotation_throttle
	var throttle = inputs.throttle
	
	if autospin:
		# We can just assume local space
		# If there is no input on an axis, we want to stop motion on it
		# If we are spinning left, then a right input would be the same as neutral, until the rotation stops.
		# This is not the same as an "arcade mode". The ship will continue to spin ever faster
		# An arcade mode wouldn't be a bad idea to implement. Still newtonian, but the flight model
		# would act more like X or Wing Commander
		var deadzone := 0.001
		# The X axis of the joystick manipulates the y axis of the ship. Godot accounts for this
		if abs(inputs.rotation_throttle.y) <= deadzone:
			var ry := local_angular_velocity.y
			var err_rot_y := 0.0 - ry
			rotation_throttle.y = $PIDS/PID_rotate_break_Y._update(err_rot_y, dt)		
		if abs(inputs.rotation_throttle.x) <= deadzone:
			var rx := local_angular_velocity.x
			var err_rot_x := 0.0 - rx
			rotation_throttle.x = $PIDS/PID_rotate_break_X._update(err_rot_x, dt)
		if abs(inputs.rotation_throttle.z) <= deadzone:
			var rz := local_angular_velocity.z
			var err_rot_z := 0.0 - rz
			rotation_throttle.z = $PIDS/PID_rotate_break_Z._update(err_rot_z, dt)
	
	# Start of PID code
	# https://raw.githubusercontent.com/itspacchu/GodotRocket/master/scripts/rocket.gd
	#if false:
	##if autospin:
		##This needs to be replaced with the steering behavior that I've been reading about
		## However! What we really want is just stopping the rotation
		#target_rot.x += inputs.rotation_throttle.x * dt
		#target_rot.y += inputs.rotation_throttle.y * dt
		#target_rot.z += inputs.rotation_throttle.z * dt
			#
		#var rx = rotation.x
		#var ry = rotation.y
		#var rz = rotation.z
		#
		#var err_rot_x := 0.0
		#var err_rot_y := 0.0
		#var err_rot_z := 0.0
		#
		## Correct for wraparound at 180/-180 or pi/-pi
		#if target_rot.x - rx > 3.14159: target_rot.x -= 2*3.14159
		#elif target_rot.x - rx < -3.14159: target_rot.x += 2*3.14159
		#if target_rot.y - ry > 3.14159: target_rot.y -= 2*3.14159
		#elif target_rot.y - ry < -3.14159: target_rot.y += 2*3.14159
		#if target_rot.z - rz > 3.14159: target_rot.z -= 2*3.14159
		#elif target_rot.z - rz < -3.14159: target_rot.z += 2*3.14159
		#
		#err_rot_x = target_rot.x - rx
		#err_rot_y = target_rot.y - ry
		#err_rot_z = target_rot.z - rz
		#
		#target_global_transform = target_global_transform.orthonormalized()
	#
		#var pidrx = $PIDS/PID_rotate_X._update(err_rot_x,dt)
		#var pidry = $PIDS/PID_rotate_Y._update(err_rot_y,dt)
		#var pidrz = $PIDS/PID_rotate_Z._update(err_rot_z,dt)
#
		#rotation_throttle = Vector3(pidrx, pidry, pidrz)
				
	if autobreak:
		var local_velocity := global_transform.basis.transposed() * linear_velocity
		if throttle.x == 0:
			var err_x := 0.0 - local_velocity.x
			throttle.x = $PIDS/PID_X._update(err_x, dt)
			if abs(throttle.x) < 0.02:
				throttle.x = 0.0
		if throttle.y == 0:
			var err_y := 0.0 - local_velocity.y
			throttle.y = $PIDS/PID_X._update(err_y, dt)
			if abs(throttle.y) < 0.02:
				throttle.y = 0.0
		if throttle.z == 0:
			var err_z := 0.0 - local_velocity.z
			throttle.z = $PIDS/PID_X._update(err_z, dt)
			if abs(throttle.z) < 0.02:
				throttle.z = 0.0
	
	$Engines.request_thrust(throttle, rotation_throttle)
	
	for thruster in $Engines.thrusters:
		apply_force(global_transform.basis * thruster.force_vector, global_transform.basis * thruster.position)
	
	if inputs.debug_all_stop:
		_debug_all_stop = true
	
	acceleraction = (linear_velocity - start_velocity) / dt
	start_velocity = linear_velocity
	return
	
	"""# Code below this was an attempt to make a realistic controler for thrusters
	var stableize := false
	
	if stableize:
		# Code here to reduce motion by requesting the opposite thrust
		pass
	
	var thruster_control_vector := []
	thruster_control_vector.resize($Engines.thrusters.size())
	
	var user_input_vector := [inputs.rotation_throttle.x, inputs.rotation_throttle.y, inputs.rotation_throttle.z, inputs.throttle.x, inputs.throttle.y, inputs.throttle.z]  #6 Components (Tx,Ty,Tz,Fx,Fy,Fz)
	for i in range(user_input_vector.size()):
		if user_input_vector[i] >= 0:
			# Use positive Torque or Force ControlVector
			#thruster_control_vector += $Engines.twelve_control_vectors[2 * i] * user_input_vector[i]
			var tcv = $Engines.twelve_control_vectors[2 * i]
			var uiv = user_input_vector[i]
			thruster_control_vector += tcv * uiv
		else:
			# Use negative Torque or Force ControlVector, also negate component since its negative
			thruster_control_vector += ($Engines.twelve_control_vectors[2 * i] + 1) * -user_input_vector[i]
	
	var absolute_maximum := 0.0
	for item in thruster_control_vector:
		if abs(item) > absolute_maximum:
			absolute_maximum = abs(item)
	if absolute_maximum > 1:
		for i in thruster_control_vector.size():
			thruster_control_vector[i] = thruster_control_vector[i] / absolute_maximum
	
	for i in range($Engines.thrusters.size()):
		$Engines.thrusters[i].power = thruster_control_vector[i]"""


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
	emit_signal("destroyed", ship_id)
	faction.owned_ships.erase(self)
	queue_free()


func find_free_spawner() -> Node3D:
	return $Spawner.find_free_spawner()


func _on_area_3d_dock_body_entered(body: Ship) -> void:
	if body == self:
		#can't dock with self, silly
		return
	if body.is_spawning:
		return
	Logger.log([body, " ship entered dock on ", name], Logger.MessageType.INFO)
	body.get_node("Crew").captain_name = ""
	body.get_node("Crew").pilot_name = ""
	for c in body.get_crew():
		add_passenger(c)
	body.queue_free()


func _on_crew_child_exiting_tree(node: Node) -> void:
	$CapitalUI.visible = false


func _on_button_launch_pressed() -> void:
	var system_name := get_parent().get_parent().get_parent().name
	galaxy.rpc("request_spawn", system_name, name)
	$CapitalShipControl.visible = false


func _on_capital_ui_request_launch() -> void:
	print_debug(multiplayer.get_unique_id())
	var player: Player = galaxy.get_node('Players').find_player_by_netid(multiplayer.get_unique_id())	
	rpc("request_launch", 0, player.player_id)


@rpc("any_peer", "call_local")
func request_launch(ship_id: int, pilot_id: int):
	if not multiplayer.is_server():
		return
	var remote_id := multiplayer.get_remote_sender_id()
	# If the host is calling this function, remote id is 0, change to its actual id
	if remote_id == 0:
		remote_id = multiplayer.get_unique_id()
	
	Logger.log(["Spawn requested in ", get_current_system().name, " ", name, " by ", remote_id], Logger.MessageType.QUESTION)
	var top_system := get_current_system()
	var system := top_system.get_node("SubViewport")

	var spawn_point = find_free_spawner()
	var spawn_position = spawn_point.global_transform.origin
	#TODO: Keep an inventory of docked ships
	
	var PlayerScene := load("res://ships/earth alliance/aurora_starfury/auora_starfury.tscn")
	var new_ship: Ship = PlayerScene.instantiate()
	new_ship.is_spawning = true
	
	#TODO: Pull ship from existing invetory using the id
	new_ship.ship_id = galaxy.ship_id_counter
	galaxy.ship_id_counter += 1
	top_system.add_ship(new_ship)
	
	new_ship.global_transform.origin = spawn_position
	
	var old_pilot: Pilot
	if pilot_id:
		old_pilot = $Crew.remove_passenger_by_id(pilot_id)
	else:		
		old_pilot = $Crew.remove_passenger_by_multiplayerid(remote_id)
	print_debug(old_pilot, pilot_id)
	var pilot: Pilot = new_ship.get_node("CrewMultiplayerSpawner").spawn({"name": old_pilot.name, "multiplayer_id": old_pilot.multiplayer_id})
	pilot._faction_id = old_pilot._faction_id
	pilot._player_pilot_id = old_pilot._player_pilot_id
	new_ship.add_pilot(pilot)
	old_pilot.queue_free()
	new_ship.set_camera.rpc_id(pilot.multiplayer_id)
	await get_tree().create_timer(1.0).timeout
	new_ship.is_spawning = false
	Logger.log(["Spawn complete for ", pilot], Logger.MessageType.SUCCESS)


func get_current_system() -> System:
	return get_parent().get_parent().get_parent()


func is_player_pilot() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.get_unique_id() == multiplayer_pilot_id


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
