extends Node3D

# Camera Move
@export_range(0, 500, 1) var camera_move_speed: float = 20.0

# Camera Rotate
var camera_rotation_direction: float = 0
@export_range(0, 10, 0.1) var camera_rotation_speed: float = 0.2
@export_range(0, 20, 10) var camera_base_rotation_speed: float = 10
@export_range(-3.14/2, 10, 1) var camera_socket_rotation_x_min: float = -3.14/2
@export_range(0, 3.14/2, 1) var camera_socket_rotation_x_max: float = 3.14/2

# Camera Pan
@export_range(0, 32, 4) var camera_automatic_pan_margin: int = 16
@export_range(0, 20, 0.5) var camera_automatic_pan_speed: float = 12.0

# Camera zoom
var camera_zoom_direction: float = 0
@export_range(0, 500, 1) var camera_zoom_speed: float = 100.0
@export_range(-1000, 500, 1) var camera_zoom_min: float = -1000
@export_range(0, 1000, 1) var camera_zoom_max: float = 1000.0
@export_range(0, 2, 0.1) var camera_zoom_speed_dampening: float = 0.92

# Flags
var camera_can_process: bool = true
var camera_can_move_base: bool = true
var camera_can_zoom: bool = true
var camera_can_automatic_pan: bool = true
var camera_can_rotate_base: bool = true
var camera_can_rotate_socket_x: bool = true
var camera_can_rotate_by_mouse_offset: bool = true

# Internal Flags
var _camera_is_rotating_base: bool = false
var _camera_is_rotating_mouse: bool = false
var _mouse_last_position: Vector2 = Vector2.ZERO

var camera
@onready var camera_socket: Node3D = $RTSCameraSocket

# Called when the node enters the scene tree for the first time.
func _ready():
	#TODO: Make this viable for VR!
	camera = $RTSCameraSocket/Camera3D


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if !camera_can_process: return
	if !camera.current: return
	camera_base_move(delta)
	camera_zoom_update(delta)
	camera_automatic_panning(delta)
	camera_base_rotate(delta)
	camera_rotate_to_mouse_offset(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Hack for now
	if event.is_action_pressed("rts_mode_toggle"):
		#TODO: How to return to camera?
		camera.current = !camera.current
	
	# Camera zoom
	if event.is_action("rts_camera_zoom_in"):
		camera_zoom_direction = -1
	elif event.is_action("rts_camera_zoom_out"):
		camera_zoom_direction = 1
	
	# Camera rotations
	if event.is_action_pressed("rts_camera_rotate_right"):
		camera_rotation_direction = -1
		_camera_is_rotating_base = true
	elif event.is_action_pressed("rts_camera_rotate_left"):
		camera_rotation_direction = 1
		_camera_is_rotating_base = true
	elif event.is_action_released("rts_camera_rotate_left") or event.is_action_released("rts_camera_rotate_right"):
		_camera_is_rotating_base = false
	
	if event.is_action_pressed("camera_rotate"):
		_mouse_last_position = get_viewport().get_mouse_position()
		_camera_is_rotating_mouse = true
	elif event.is_action_released("camera_rotate"):
		_camera_is_rotating_mouse = false
	

# Moves the base of the camera with WASD
func camera_base_move(delta: float) -> void:
	if !camera_can_move_base: return
	if !camera.current: return
	
	var velocity_direction:Vector3 = Vector3.ZERO
	
	if Input.is_action_pressed("rts_camera_forward"): velocity_direction -= transform.basis.z
	if Input.is_action_pressed("rts_camera_backwards"): velocity_direction += transform.basis.z
	if Input.is_action_pressed("rts_camera_left"): velocity_direction -= transform.basis.x
	if Input.is_action_pressed("rts_camera_right"): velocity_direction += transform.basis.x
		
	position += velocity_direction.normalized() * delta * camera_move_speed


# Controls the zoom of the camera
func camera_zoom_update(delta: float) -> void:
	if !camera_can_zoom: return
	var new_zoom: float = clamp(camera.position.z + camera_zoom_speed * camera_zoom_direction * delta, camera_zoom_min, camera_zoom_max)
	camera.position.z = new_zoom
	camera_zoom_direction *= camera_zoom_speed_dampening


# Rotates the socket based on mouse offsets
func camera_rotate_to_mouse_offset(delta: float) -> void:
	if !camera_can_rotate_by_mouse_offset or !_camera_is_rotating_mouse: return
	var mouse_offset: Vector2 = get_viewport().get_mouse_position()
	mouse_offset = mouse_offset - _mouse_last_position
	
	_mouse_last_position = get_viewport().get_mouse_position()
	
	camera_base_rotate_left_right(delta, mouse_offset.x)
	camera_socket_rotate_x(delta, mouse_offset.y)
	

# Rotates the camera base
func camera_base_rotate(delta: float) -> void:
	if !camera_can_rotate_base or !_camera_is_rotating_base: return
	camera_base_rotate_left_right(delta, camera_rotation_direction * camera_base_rotation_speed)


# Rotates the socket
func camera_socket_rotate_x(delta: float, dir: float) -> void:
	if !camera_can_rotate_socket_x: return
	var new_rotation_x: float = camera_socket.rotation.x
	new_rotation_x -= dir * delta * camera_rotation_speed
	new_rotation_x = clamp(new_rotation_x, camera_socket_rotation_x_min, camera_socket_rotation_x_max)
	camera_socket.rotation.x = new_rotation_x
	

func camera_base_rotate_left_right(delta: float, dir: float) -> void:
	rotation.y += dir * camera_rotation_speed * delta

# Pans camera automatically based on screen margins
func camera_automatic_panning(delta: float) -> void:
	if !camera_can_automatic_pan: return
	
	var viewport_current: Viewport = get_viewport()
	var pan_direction: Vector2 = Vector2(-1, -1)  # Starts negative
	var viewport_visible_rectangle: Rect2i = Rect2i(viewport_current.get_visible_rect())
	var viewport_size: Vector2i = viewport_visible_rectangle.size
	var current_mouse_position: Vector2 = viewport_current.get_mouse_position()
	
	# Panning on the x axis
	if ((current_mouse_position.x < camera_automatic_pan_margin) or (current_mouse_position.x > viewport_size.x - camera_automatic_pan_margin)):
		if current_mouse_position.x > viewport_size.x / 2:
			pan_direction.x = 1
		translate(Vector3(pan_direction.x * delta * camera_automatic_pan_speed, 0, 0))
	
	# Panning on the y axis
	if ((current_mouse_position.y < camera_automatic_pan_margin) or (current_mouse_position.y > viewport_size.y - camera_automatic_pan_margin)):
		if current_mouse_position.y > viewport_size.y / 2:
			pan_direction.y = 1
		translate(Vector3(0, 0, pan_direction.y * delta * camera_automatic_pan_speed)) # Remember in 3D z is screen up
