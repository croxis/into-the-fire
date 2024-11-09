extends Node3D


var bay: int = 1

func find_free_spawner() -> Node3D:
	var search = true
	var spawn_joint: Node3D
	var spawners := $"."
	while search:
		if spawners.get_node("Bay" + str(bay)).get_overlapping_bodies().is_empty():
			var spawn_point = spawners.get_node("Bay" + str(bay))
			search = false
			spawn_joint = spawn_point
		bay += 1
		if bay > 3:
			bay = 1
	return spawn_joint
