#@tool
extends MeshInstance3D
## Babylon 5's rotating section. Its angle is worked out from server time, not
## added up frame by frame, so every machine shows the same angle for the same
## moment: the server by its tick, a client at the tick it draws the station
## at (SnapshotClock, about 100 ms in the past). Added up on each machine and
## synced once a second, the angles drifted apart and snapped, and a ship held
## by a launch arm was shown off its arm.

# TODO: Should the rotating section's collision be an AnimatableBody3D turned
# on netfox ticks? Its StaticBody3Ds (Main_Cylinder, Neck_Section) are turned
# here every render frame, so Jolt sees them teleport: a ship touching the
# hull isn't carried along.

@export var rpm = 0.75
var _start_angle := 0.0


func _ready():
	name = 'rotation'
	_start_angle = rotation.x


## The section's angle about x at [param server_ticks] (fractional), starting
## from [param start] at tick 0 and turning at [param turns_per_minute].
static func angle_at(start: float, turns_per_minute: float, server_ticks: float, tick_seconds: float) -> float:
	var turned := turns_per_minute * TAU / 60.0 * server_ticks * tick_seconds
	return fposmod(start - turned, TAU)


func _process(_delta):
	rotation.x = angle_at(_start_angle, rpm, Galaxy.shown_tick(self), NetworkTime.ticktime)
