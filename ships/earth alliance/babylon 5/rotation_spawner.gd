extends HingeJoint3D
var is_empty := true
var x = true
var time = 0.0

# Called when the node enters the scene tree for the first time.
func _ready():
	$"Camera3D".current = true


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	#get_hinge_angle()
	time += delta
	if time > 5.0 and x:
		self.set_node_b("")
		print("pop")
		x = false
