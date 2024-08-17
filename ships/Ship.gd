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

var faction: Faction:
	get:
		if ($Crew.captain):
			return $Crew.captain.faction
		else:
			return null

@export_node_path("Camera3D") var camera_path: NodePath
@onready var camera: Camera3D = get_node_or_null(camera_path)

@export var ship_class := ""

@export var target_rot = Vector3(0,0,0)
@export var target_pos = Vector3(0,0,0)
@export var autospin := false
@export var autobreak := true

@export var max_health := 100
@export var is_station := false


var health := max_health:
	set(new_health):
		print_debug("New Health: ", new_health)
		health = new_health
		if has_node("SubViewportCenter"):
			$SubViewportCenter/center_ui.set_health(health)
		if (health <= 0.0):
			destroy()
var engine_length = 7.5
var thruster_force: Vector3 = Vector3(0, 0, 0)
var thruster_torque: Vector3 = Vector3(0, 0, 0)
var _debug_all_stop := false

var start_speed = 0

signal destroyed(id)

var bay: int = 1
var slot: int = 1
var has_spawn_points := true


# Called when the node enters the scene tree for the first time.
func _ready():
	# If in editor simply disable processing as it's not needed here
	if (Engine.is_editor_hint()):
		set_physics_process(false)
	Logger.log(["Creating ship with id: ", ship_id, ". Name: ", name], Logger.MessageType.QUESTION)
	
	#TODO: Change to when pilot joins
	#if (multiplayer.get_unique_id() == _player_pilot_id):
		# Set the camera
		#camera.set_znear(0.3)  # This should be set per ship
	#	camera.far = 30000
		# Ensure it is the active one
	#	camera.current = true
	#	print_debug("Setting camera")
	#inputs.set_multiplayer_authority(_player_pilot_id)
	
	can_sleep = false
	target_rot = rotation
	if has_node("$SubViewportCenter"):
		$SubViewportCenter/center_ui.set_autobreak(autobreak)
		$SubViewportCenter/center_ui.set_autospin(autospin)
	Logger.log(["Ship created: ", ship_id], Logger.MessageType.SUCCESS)


func add_captain(pilot: Pilot):
	if $Crew.captain:
		return
	$Crew.captain = pilot
	if (multiplayer.get_unique_id() == pilot._multiplayer_id):
		camera.far = 30000
		camera.near = 0.3
		camera.current = true
	$Crew.add_child(pilot)


func add_passenger(pilot: Pilot):
	Logger.log(["Adding pilot ", pilot, "to ship ", self], Logger.MessageType.QUESTION)
	var max_capacity: int = $Crew.max_passengers
	if $Crew.pilot:
		max_capacity += 1
	if $Crew.captain:
		max_capacity += 1
	if $Crew.get_child_count() >= max_capacity:
		Logger.log(["Too many passengers."], Logger.MessageType.WARNING)
		return
	if (multiplayer.get_unique_id() == pilot._multiplayer_id):
		camera.far = 30000
		camera.near = 0.3
		camera.current = true
	if pilot.get_parent():
		pilot.reparent($Crew)
	else:
		$Crew.add_child(pilot)


func add_pilot(pilot: Pilot):
	if $Crew.pilot:
		return
	$Crew.pilot = pilot
	if (multiplayer.get_unique_id() == pilot._multiplayer_id):
		camera.far = 30000
		camera.near = 0.3
		camera.current = true
	$Crew.add_child(pilot)
		

func _input(event):
	if event.is_action_pressed("debug_kill"):
		print_debug("Debug kill request by ", multiplayer.get_unique_id())
		#health = -1
		rpc("debug_set_health", -1)
	if event.is_action_pressed("autobreak_toggle"):
		rpc("autobreak_toggle")
	if event.is_action_pressed("autospin_toggle"):
		rpc("autospin_toggle")


@rpc("any_peer")
func debug_set_health(new_health):
	print("RPC called by: ", multiplayer.get_remote_sender_id())
	health = new_health


@rpc("any_peer", "call_local")
func autobreak_toggle():
	autobreak = !autobreak
	$SubViewportCenter/center_ui.set_autobreak(autobreak)


@rpc("any_peer", "call_local")
func autospin_toggle():
	autospin = !autospin
	target_rot = rotation
	$SubViewportCenter/center_ui.set_autospin(autospin)


func _integrate_forces(state: PhysicsDirectBodyState3D):
	if is_station:
		return
	if _debug_all_stop:
		state.angular_velocity = Vector3(0,0,0)
		state.linear_velocity = Vector3(0,0,0)
		target_rot = rotation
		_debug_all_stop = false
	$SubViewportCenter/center_ui.set_speed(state.linear_velocity.length())


func _physics_process(dt: float) -> void:
	if is_station:
		return
	if not $Crew.pilot:
		return
	# For now throttle is capped at  1. In the future we can boost power to engines.
	# In Godot 3.2 add_force is cleared every physics frame
	if multiplayer.multiplayer_peer == null or multiplayer.get_unique_id() == _player_pilot_id:
		# The client which this player represent will update the controls state, and notify it to everyone.
		inputs.update()
		
	# Start of PID code
	# https://raw.githubusercontent.com/itspacchu/GodotRocket/master/scripts/rocket.gd
	var rotation_throttle = inputs.rotation_throttle
	var throttle = inputs.throttle
	
	if(autospin):
		target_rot.x += inputs.rotation_throttle.x * dt
		target_rot.y += inputs.rotation_throttle.y * dt
		target_rot.z += inputs.rotation_throttle.z * dt
			
		var rx = rotation.x
		var ry = rotation.y
		var rz = rotation.z
		
		var err_rot_x := 0.0
		var err_rot_y := 0.0
		var err_rot_z := 0.0
		
		# Correct for wraparound at 180/-180 or pi/-pi
		if target_rot.x - rx > 3.14159: target_rot.x -= 2*3.14159
		elif target_rot.x - rx < -3.14159: target_rot.x += 2*3.14159
		if target_rot.y - ry > 3.14159: target_rot.y -= 2*3.14159
		elif target_rot.y - ry < -3.14159: target_rot.y += 2*3.14159
		if target_rot.z - rz > 3.14159: target_rot.z -= 2*3.14159
		elif target_rot.z - rz < -3.14159: target_rot.z += 2*3.14159
		
		err_rot_x = target_rot.x - rx
		err_rot_y = target_rot.y - ry
		err_rot_z = target_rot.z - rz		
	
		var pidx = $PIDS/PID_rotate_X._update(err_rot_x,dt)
		var pidy = $PIDS/PID_rotate_Y._update(err_rot_y,dt)
		var pidz = $PIDS/PID_rotate_Z._update(err_rot_z,dt)
		
		#DebugDraw3D.draw_arrow_ray(self.global_position, target_rot, 100, Color.MAGENTA, 10.0)
		#print_debug(self.global_position, target_rot)
		#print_debug(target_rot.x, " ", rx, " ", pidx)
		rotation_throttle = Vector3(pidx, pidy, pidz)
				
	if autobreak:
		var local_velocity := global_transform.basis.transposed() * linear_velocity
		if -0.009 < throttle.x and throttle.x < 0.009:
			if local_velocity.x > 5:
				throttle.x = -1
			elif local_velocity.x > 0:
				throttle.x = -0.2
			if local_velocity.x < -5:
				throttle.x = 1
			elif local_velocity.x < 0:
				throttle.x = 0.2
		if -0.009 < throttle.y and throttle.y < 0.009:
			if local_velocity.y > 5:
				throttle.y = -1
			elif local_velocity.y > 0:
				throttle.y = -0.2
			if local_velocity.y < -5:
				throttle.y = 1
			elif local_velocity.y < 0:
				throttle.y = 0.2
		if -0.009 < throttle.z and throttle.z < 0.009:
			if local_velocity.z > 5:
				throttle.z = -1
			elif local_velocity.z > 0:
				throttle.z = -0.2
			if local_velocity.z < -5:
				throttle.z = 1
			elif local_velocity.z < 0:
				throttle.z = 0.2
			
		
	#print_debug(target_rot.z, " ", rotation.z, " ", rotation_throttle.z)
	$Engines.request_thrust(throttle, rotation_throttle)
	
	for thruster in $Engines.thrusters:
		apply_force(global_transform.basis * thruster.force_vector, global_transform.basis * thruster.position)
	
	if inputs.debug_all_stop:
		_debug_all_stop = true
	
	$SubViewportCenter/center_ui.set_acceleration((linear_velocity.length() - start_speed)/dt)	
	start_speed = linear_velocity.length()
	return
	
	# Code below this was an attempt to make a realistic controler for thrusters
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
			print_debug(tcv, " ", uiv)
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
		$Engines.thrusters[i].power = thruster_control_vector[i]


func bullet_hit(damage, bullet_global_trans):
	print_debug("Hit")
	var BASE_BULLET_BOOST = 1
	var direction_vect = bullet_global_trans.basis.z.normalized() * BASE_BULLET_BOOST
	apply_impulse((bullet_global_trans.origin - global_transform.origin).normalized(), direction_vect * damage)
	health -= damage


func destroy() -> void:
	print_debug("Destroyed: ", _player_pilot_id)
	emit_signal("destroyed", _player_pilot_id)
	queue_free()


func find_free_spawner() -> Node3D:
	var search = true
	var spawn_joint
	print_debug("Children: ", get_child_count())
	for c in get_children():
		print(c)
	var spawners := $rotation/Cobra_Bays/Spawner
	while search:
		#if get_node("rotation/Cobra_Bays/Spawner/Bay" + str(bay) + "/" + str(slot) + "/Area3D").get_overlapping_bodies().is_empty():
		if spawners.get_node("Bay" + str(bay) + "/" + str(slot) + "/Area3D").get_overlapping_bodies().is_empty():
			var spawn_point = spawners.get_node("Bay" + str(bay) + "/" + str(slot))
			search = false
			spawn_joint = spawn_point
		slot += 1
		if slot > 7:
			bay += 1
			slot = 1
		if bay > 4:
			bay = 1
			slot = 1
	return spawn_joint
