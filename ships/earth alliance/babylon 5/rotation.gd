#@tool
extends MeshInstance3D

# TODO: Should the rotating section's collision be an AnimatableBody3D turned
# on netfox ticks? Its StaticBody3Ds (Main_Cylinder, Neck_Section) are turned
# here every render frame, so Jolt sees them teleport: a ship touching the
# hull isn't carried along, and the rotation doesn't follow the 60 Hz ticks.

@export var rpm = 0.75
var radian_per_second = rpm * 2 * PI / 60

# Called when the node enters the scene tree for the first time.
func _ready():
	name = 'rotation'

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	rotation.x -= radian_per_second * delta
