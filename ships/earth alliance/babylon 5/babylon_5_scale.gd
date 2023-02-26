extends Node3D

var bay: int = 1
var slot: int = 1
var has_spawn_points := true

func find_free_spawner() -> Node3D:
	var search = true
	var spawn_joint
	print_debug("Children: ", get_child_count())
	for c in get_children():
		print(c)
	var spawners := $rotation/Cobra_Bays/Spawner
	while search:
		#if get_node("rotation/Cobra_Bays/Spawner/Bay" + str(bay) + "/" + str(slot) + "/Area3D").get_overlapping_bodies().is_empty():
		if spawners.get_node("Bay" + str(bay) + "/" + str(slot) + "/Area3D").get_overlapping_bodies().is_empty():
			var spawn_point = spawners.get_node("Bay" + str(bay) + "/" + str(slot))
			search = false
			spawn_joint = spawn_point
		slot += 1
		if slot > 7:
			bay += 1
			slot = 1
		if bay > 4:
			bay = 1
			slot = 1
	return spawn_joint
