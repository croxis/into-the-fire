extends Node

# Eventually each individual engine will be modeled to react to the desired
# pilot Input. For now it is just generic
# For now throttle is capped at  1. In the future we can boost power to engines.
# In Godot 3.2 add_force is cleared every physics frame
@export var throttle: Vector3 = Vector3():
	set(value):
		# This will be sent by players, make sure values are within limits.
		throttle = clamp(value, Vector3(-1, -1, -1), Vector3(1, 1, 1))

@export var rotation_throttle: Vector3 = Vector3():
	set(value):
		# This will be sent by players, make sure values are within limits.
		rotation_throttle = clamp(value, Vector3(-1, -1, -1), Vector3(1, 1, 1))

@export var debug_all_stop: bool = false
@export var fire_primary: bool = false
@export var fire_secondary: bool = false


func update():
	throttle = Vector3(0, 0, 0)
	rotation_throttle = Vector3(0, 0, 0)
	debug_all_stop = false

	# Consider squaring or cubing results to get more precise movements 
	throttle.z = Input.get_axis("throttle_backward", "throttle_forward")
	rotation_throttle.y = Input.get_axis("right_rotation", "left_rotation")
	rotation_throttle.x = Input.get_axis("up_rotation", "down_rotation")
	rotation_throttle.z = Input.get_axis("clock_rotation", "counter_rotation")
	
	if (Input.is_action_pressed("forward_full_thrust")):
		throttle.z = 1
	if (Input.is_action_pressed("backward_full_thrust")):
		throttle.z = -1
	if (Input.is_action_pressed("slide_left_full")):
		throttle.x = 1
	if (Input.is_action_pressed("slide_right_full")):
		throttle.x = -1
	if (Input.is_action_pressed("slide_up_full")):
		throttle.y = 1
	if (Input.is_action_pressed("slide_down_full")):
		throttle.y = -1
	if (Input.is_action_pressed("rotate_left_full")):
		rotation_throttle.y = 1
	if (Input.is_action_pressed("rotate_right_full")):
		rotation_throttle.y = -1
	if (Input.is_action_pressed("rotate_down_full")):
		rotation_throttle.x = 1
	if (Input.is_action_pressed("rotate_up_full")):
		rotation_throttle.x = -1
	if (Input.is_action_pressed("clockwise_full")):
		rotation_throttle.z = 1
	if (Input.is_action_pressed("counter_clockwise_full")):
		rotation_throttle.z = -1
	if (Input.is_action_pressed("debug_all_stop")):
		print("Debug all stop")
		throttle = Vector3(0, 0, 0)
		rotation_throttle = Vector3(0, 0, 0)
		debug_all_stop = true
	fire_primary = Input.is_action_pressed("fire_primary")
	fire_secondary = Input.is_action_pressed("fire_secondary")
