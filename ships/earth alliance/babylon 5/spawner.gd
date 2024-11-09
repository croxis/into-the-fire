extends Node3D

var bay: int = 1
var slot: int = 1

func find_free_spawner() -> Node3D:
	var search = true
	var spawn_joint: Node3D
	var spawners := $"../rotation/Cobra_Bays/Spawner"
	while search:
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
