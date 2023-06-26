extends MultiplayerSynchronizer


# For now throttle is capped at  1. In the future we can boost power to engines.
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
@export var autospin_toggle := false
@export var autobreak_toggle := false


func _ready():
	# Only process for the local player.
	set_process(get_multiplayer_authority() == multiplayer.get_unique_id())


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
		throttle.z = -1
	if (Input.is_action_pressed("backward_full_thrust")):
		throttle.z = 1
	if (Input.is_action_pressed("slide_left_full")):
		throttle.x = -1
	if (Input.is_action_pressed("slide_right_full")):
		throttle.x = 1
	if (Input.is_action_pressed("slide_up_full")):
		throttle.y = 1
	if (Input.is_action_pressed("slide_down_full")):
		throttle.y = -1
	if (Input.is_action_pressed("rotate_left_full")):
		rotation_throttle.y = 1
	if (Input.is_action_pressed("rotate_right_full")):
		rotation_throttle.y = -1
	if (Input.is_action_pressed("rotate_down_full")):
		rotation_throttle.x = -1
	if (Input.is_action_pressed("rotate_up_full")):
		rotation_throttle.x = 1
	if (Input.is_action_pressed("clockwise_full")):
		rotation_throttle.z = -1
	if (Input.is_action_pressed("counter_clockwise_full")):
		rotation_throttle.z = 1
	if (Input.is_action_pressed("debug_all_stop")):
		print_debug("Debug all stop")
		throttle = Vector3(0, 0, 0)
		rotation_throttle = Vector3(0, 0, 0)
		debug_all_stop = true
	fire_primary = Input.is_action_pressed("fire_primary")
	fire_secondary = Input.is_action_pressed("fire_secondary")
	#autobreak_toggle = Input.is_action_pressed("autobreak_toggle")
	#autospin_toggle = Input.is_action_pressed("autospin_toggle")
