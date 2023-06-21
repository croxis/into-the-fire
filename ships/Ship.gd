#@tool
extends RigidBody3D
class_name Ship


# Cache the pilot ID in here
@export var _player_pilot_id: int:
	set(id):
		_player_pilot_id = id
		# Give authority over the player input to the appropriate peer.
		$InputsSync.set_multiplayer_authority(id)

@onready var inputs = $InputsSync
@export_node_path("Camera3D") var camera_path: NodePath
@onready var camera: Camera3D = get_node_or_null(camera_path)

@export var ship_class := ""
# Thrust values. Eventually this will be per engine
# Max thrust is 8 gs
# Thrust = 3800000 N
# Array +x, -x, +y, -y, +z, -z
# In furute individual engines will be modeled. This is the "aggrigate" of all
# engines in that direction
@export var max_thrust = [3800000, 3800000 / 2, 3800000 / 4, 3800000 / 4, 3800000 / 4, 3800000 / 4]
		

# Eventually each individual engine will be modeled to react to the desired
# pilot input. For now it is just generic
# For now throttle is capped at  1. In the future we can boost power to engines.
# In Godot 3.2 add_force is cleared every physics frame
# Engine distance from origin. Estimated by eyeballing. For torque
# TODO: Move these to export and editable in the editor as soon as 
# that functionality is available

@export var max_health := 100
var health := max_health:
	set(new_health):
		print_debug("New Health: ", new_health)
		health = new_health
		$SubViewportCenter/center_ui.set_health(health)
		if (health <= 0.0):
			destroy()
var engine_length = 7.5
var thruster_force: Vector3 = Vector3(0, 0, 0)
var thruster_torque: Vector3 = Vector3(0, 0, 0)
var _debug_all_stop := false

var start_speed = 0

signal destroyed(id)


# Called when the node enters the scene tree for the first time.
func _ready():
	# If in editor simply disable processing as it's not needed here
	if (Engine.is_editor_hint()):
		set_physics_process(false)
	print_debug("Creating ship with id: ", _player_pilot_id, ". My ID: ", multiplayer.get_unique_id())
	if (multiplayer.get_unique_id() == _player_pilot_id):
		# Set the camera
		#camera.set_znear(0.3)  # This should be set per ship
		camera.far = 30000
		# Ensure it is the active one
		camera.current = true
		print_debug("Setting camera")
	$InputsSync.set_multiplayer_authority(_player_pilot_id)
	can_sleep = false
	print_debug("Ship created: ", _player_pilot_id)


func _input(event):
	if event.is_action_pressed("debug_kill"):
		print_debug("Debug kill request by ", multiplayer.get_unique_id())
		#health = -1
		rpc("debug_set_health", -1)

@rpc("any_peer")
func debug_set_health(new_health):
	print("RPC called by: ", multiplayer.get_remote_sender_id())
	health = new_health


func _integrate_forces(state: PhysicsDirectBodyState3D):
	if _debug_all_stop:
		state.angular_velocity = Vector3(0,0,0)
		state.linear_velocity = Vector3(0,0,0)
		_debug_all_stop = false
	$SubViewportCenter/center_ui.set_speed(state.linear_velocity.length())


func _physics_process(dt: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.get_unique_id() == _player_pilot_id:
		# The client which this player represent will update the controls state, and notify it to everyone.
		inputs.update()
	
	# This codeblock is to cheat
	# Linear and torque are modeled independently 
	$Engines.apply_linear_thrust(inputs.throttle)
	$Engines.apply_torque_thrust(inputs.rotation_throttle)
	
	# add_force is cleared after every frame
	#apply_central_force(global_transform.basis * $Engines.linear_force)
	#apply_torque(global_transform.basis * $Engines.torque_force)
	#if $Engines.torque_force:
	#	print_debug($Engines.torque_force)
	#apply_torque($Engines.torque_force)
	
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
		
	return
	
	
	# Old code below
	
	# Torque is, simplified, force times length. The length of the engines from
	# axis is currently eyeballed. Math will be more elaborate later when indiv
	# thrusters are moddled
	
	if inputs.rotation_throttle.x > 0:
		thruster_torque.x = engine_length * max_thrust[5] * inputs.rotation_throttle.x
	elif inputs.rotation_throttle.x < 0:
		thruster_torque.x = engine_length * max_thrust[5] * inputs.rotation_throttle.x
	else:
		thruster_torque.x = 0
	if inputs.rotation_throttle.y > 0:
		thruster_torque.y = engine_length * max_thrust[5] * inputs.rotation_throttle.y
	elif inputs.rotation_throttle.y < 0:
		thruster_torque.y = engine_length * max_thrust[5] * inputs.rotation_throttle.y
	else:
		thruster_torque.y = 0
	if inputs.rotation_throttle.z > 0:
		thruster_torque.z = engine_length * max_thrust[5] * inputs.rotation_throttle.z
	elif inputs.rotation_throttle.z < 0:
		thruster_torque.z = engine_length * max_thrust[5] * inputs.rotation_throttle.z
	else:
		thruster_torque.z = 0
	thruster_torque = thruster_torque / 7  # Modifyer to make the fury not SOOOO twitchy
	apply_torque(global_transform.basis * thruster_torque)
	
	$SubViewportCenter/center_ui.set_acceleration((linear_velocity.length() - start_speed)/dt)	
	start_speed = linear_velocity.length()


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
