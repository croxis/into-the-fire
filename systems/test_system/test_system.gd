extends Node3D


func _ready():
	#print(get_tree().get_root().get_children())StarField
	var ran = $StarField.get_star_proper("Ran")
	var ran_position = Vector3(ran['x'].to_float(), ran['y'].to_float(), ran['z'].to_float())
	ran_position.z += $StarField.AU_IN_PARSEC * 1.058  # Distance of epsilon 3 to RAN
	$StarField.celestial_coords = ran_position
	$StarField.mag_ref = 7.0
	$StarField.mag_limit = 7.0
