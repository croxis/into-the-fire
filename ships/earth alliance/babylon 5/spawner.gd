extends Node3D

var bay: int = 1
var slot: int = 1

const BAY_COUNT := 4
const ARMS_PER_BAY := 7


## [launch_point, position] for a free cobra bay arm, or [] when all are busy.
func find_free_spawner() -> Array:
	var spawn_joint: Node3D
	var spawners := $"../rotation/Cobra_Bays/Spawner"
	# Try each arm once. When all are busy, say so instead of looping forever.
	for _i in BAY_COUNT * ARMS_PER_BAY:
		var arm = spawners.get_node("Cobra Bay" + str(bay) + "/spawn_arms/CobraBayArm" + str(slot))
		slot += 1
		if slot > ARMS_PER_BAY:
			bay += 1
			slot = 1
		if bay > BAY_COUNT:
			bay = 1
			slot = 1
		if arm.is_empty:
			spawn_joint = arm
			break
	if spawn_joint == null:
		return []
	var spawn_position = spawn_joint.get_node("loading/loadingexternder/extender-rotating/spawn_point").global_transform.origin
	return [spawn_joint, spawn_position]
