extends ConsoleCapability
class_name HelmCapability

@export var autospin := false
@export var autobreak := false
@export var ship: Ship
@export var target_rot = Vector3(0,0,0)
@export var target_pos = Vector3(0,0,0)
@export var target_global_transform := Transform3D()
@export var input_rotation_throttle := Vector3()
@export var rotation_throttle := Vector3()
@export var throttle := Vector3()


func _physics_process(dt: float) -> void:
	_rollback_tick(dt, 0, 0)


func _rollback_tick(dt, _tick, _is_fresh):
	if autospin:
		# We can just assume local space
		# If there is no input on an axis, we want to stop motion on it
		# If we are spinning left, then a right input would be the same as neutral, until the rotation stops.
		# This is not the same as an "arcade mode". The ship will continue to spin ever faster
		# An arcade mode wouldn't be a bad idea to implement. Still newtonian, but the flight model
		# would act more like X or Wing Commander
		var deadzone := 0.001
		# The X axis of the joystick manipulates the y axis of the ship. Godot accounts for this
		if abs(input_rotation_throttle.y) <= deadzone:
			var ry := ship.local_angular_velocity.y
			var err_rot_y := 0.0 - ry
			rotation_throttle.y = $PIDS/PID_rotate_break_Y._update(err_rot_y, dt)		
		if abs(input_rotation_throttle.x) <= deadzone:
			var rx := ship.local_angular_velocity.x
			var err_rot_x := 0.0 - rx
			rotation_throttle.x = $PIDS/PID_rotate_break_X._update(err_rot_x, dt)
		if abs(input_rotation_throttle.z) <= deadzone:
			var rz := ship.local_angular_velocity.z
			var err_rot_z := 0.0 - rz
			rotation_throttle.z = $PIDS/PID_rotate_break_Z._update(err_rot_z, dt)

	if autobreak:
		var local_velocity := ship.global_transform.basis.transposed() * ship.linear_velocity
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
	system.request_thrust(throttle, rotation_throttle)


func toggle_autospin() -> bool:
	autospin = !autospin
	if autospin:
		target_global_transform = ship.global_transform
	return autospin


func toggle_autobreak() -> bool:
	autobreak = !autobreak
	return autobreak


func _debug_all_stop():
	ship._debug_all_stop = true
	target_rot = ship.rotation


func launch_completed():
	target_global_transform = ship.global_transform
