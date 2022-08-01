extends Node3D

# Called when the node enters the scene tree for the first time.
func _ready():
	#print(get_tree().get_root().get_children())
	get_tree().get_root().get_node("entry").get_node("MainMenu").visible = true
	var ran = $StarField.get_star_proper("Ran")
	var ran_position = Vector3(ran['x'].to_float(), ran['y'].to_float(), ran['z'].to_float())
	ran_position.z += $StarField.AU_IN_PARSEC * 1.058  # Distance of epsilon 3 to RAN
	print(ran_position)
	$StarField.celestial_coords = ran_position
	print($StarField.celestial_coords)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
