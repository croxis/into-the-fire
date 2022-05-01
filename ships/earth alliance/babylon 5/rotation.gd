extends MeshInstance3D

@export var rpm = 0.75
var radian_per_second = rpm * 2 * PI / 60

# Called when the node enters the scene tree for the first time.
func _ready():
	name = 'rotation'

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	rotation.x -= radian_per_second * delta

