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


## Called by the ship each tick, before it flies (Ship._rollback_tick), so the
## thruster power set here moves the ship on the same tick.
func _rollback_tick(dt, _tick, _is_fresh):
	var local_velocity := Vector3.ZERO
	var local_spin := Vector3.ZERO
	if ship:
		local_velocity = ship.global_transform.basis.transposed() * ship.linear_velocity
		local_spin = ship.local_angular_velocity
	var throttles := assist(input_record(), local_velocity, local_spin, dt)
	throttle = throttles[0]
	rotation_throttle = throttles[1]
	system.request_thrust(throttle, rotation_throttle)


## What the pilot (or NPC) set at this helm this tick: the input a replay of
## this tick needs (own-ship prediction, ShipPrediction).
func input_record() -> Dictionary:
	return {"throttle": throttle, "rotation": input_rotation_throttle,
			"autospin": autospin, "autobreak": autobreak}


## [linear, rotation] throttles for [param input] (an input_record()), with
## flight assist working against [param local_velocity] and
## [param local_spin] (the ship's own frame). Replays call this with the
## replayed state, so it must depend on nothing else: the PIDs have only
## proportional gain (ki = kd = 0), so their own memory doesn't matter. Give
## them integral or derivative gain and replays need the PIDs' state too.
func assist(input: Dictionary, local_velocity: Vector3, local_spin: Vector3,
		dt: float) -> Array[Vector3]:
	var linear: Vector3 = input.throttle
	var input_rotation: Vector3 = input.rotation
	# Pilot input drives rotation; autospin only takes over idle axes below.
	var rotation := input_rotation
	if input.autospin:
		# We can just assume local space
		# If there is no input on an axis, we want to stop motion on it
		# If we are spinning left, then a right input would be the same as neutral, until the rotation stops.
		# This is not the same as an "arcade mode". The ship will continue to spin ever faster
		# An arcade mode wouldn't be a bad idea to implement. Still newtonian, but the flight model
		# would act more like X or Wing Commander
		var deadzone := 0.001
		# The X axis of the joystick manipulates the y axis of the ship. Godot accounts for this
		if abs(input_rotation.y) <= deadzone:
			rotation.y = $PIDS/PID_rotate_break_Y._update(0.0 - local_spin.y, dt)
		if abs(input_rotation.x) <= deadzone:
			rotation.x = $PIDS/PID_rotate_break_X._update(0.0 - local_spin.x, dt)
		if abs(input_rotation.z) <= deadzone:
			rotation.z = $PIDS/PID_rotate_break_Z._update(0.0 - local_spin.z, dt)

	if input.autobreak:
		if linear.x == 0:
			linear.x = $PIDS/PID_X._update(0.0 - local_velocity.x, dt)
			if abs(linear.x) < 0.02:
				linear.x = 0.0
		if linear.y == 0:
			linear.y = $PIDS/PID_X._update(0.0 - local_velocity.y, dt)
			if abs(linear.y) < 0.02:
				linear.y = 0.0
		if linear.z == 0:
			linear.z = $PIDS/PID_X._update(0.0 - local_velocity.z, dt)
			if abs(linear.z) < 0.02:
				linear.z = 0.0
	return [linear, rotation]


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
