extends Node3D
class_name Bolt
## How a Shot looks: drawn each frame where the shot is at the moment this
## machine shows (Galaxy.shown_tick), growing as it weakens. Nothing else: the
## shot itself is data in its system's ShotField, and hits are the server's.

var shot: Shot


func _process(_delta: float) -> void:
	if shot == null:
		return
	var at := Galaxy.shown_tick(self)
	var grow := 1.0 + 0.2 * maxf(0.0, shot.seconds_at(at))
	var along := shot.velocity.normalized() if shot.velocity else Vector3.FORWARD
	var up := Vector3.UP if absf(along.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	# The capsule lies along the root's z (its mesh is turned): point that along the flight.
	global_transform = Transform3D(Basis.looking_at(along, up).scaled(Vector3.ONE * grow),
			shot.position_at(at))
