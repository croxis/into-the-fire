extends Node3D

var bay: int = 1
var slot: int = 1

func find_free_spawner() -> Array:
	var search = true
	var spawn_joint: Node3D
	var spawners := $"../rotation/Cobra_Bays/Spawner"
	while search:
		if spawners.get_node("Cobra Bay" + str(bay) + "/spawn_arms/CobraBayArm" + str(slot)).is_empty:
			spawn_joint = spawners.get_node("Cobra Bay" + str(bay) + "/spawn_arms/CobraBayArm" + str(slot))
			search = false
		slot += 1
		if slot > 7:
			bay += 1
			slot = 1
		if bay > 4:
			bay = 1
			slot = 1
	var spawn_position = spawn_joint.get_node("loading/loadingexternder/extender-rotating/spawn_point").global_transform.origin
	return [spawn_joint, spawn_position]
