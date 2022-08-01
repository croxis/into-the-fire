extends Node3D


var speed = 0.307


func _ready():
	print("Example of search for star by hip id: ", $StarField.get_star_hip("1"))
	print("Example of search for star by proper name: ", $StarField.get_star_proper("Sol"))


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if Input.is_action_pressed("tilt_down"):
		$Camera.rotate_x(-speed/100)
	if Input.is_action_pressed("forward"):
		# Move as long as the key/button is pressed.
		$StarField.position.z += speed * delta
	if Input.is_action_pressed("backwards"):
		# Move as long as the key/button is pressed.
		$StarField.position.z -= speed * delta
	if Input.is_action_pressed("left"):
		# Move as long as the key/button is pressed.
		$StarField.position.x += speed * delta
	if Input.is_action_pressed("right"):
		# Move as long as the key/button is pressed.
		$StarField.position.x -= speed * delta


func _on_star_field_star_debug(message):
	print(message)
	$Control/Control._on_star_field_star_debug(message)
