extends Node3D

var bay: int = 1
var slot: int = 1
var has_spawn_points := true
@onready var camera := $rotation/CnC/Camera3D

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

func add_captain(pilot: Pilot):
	if $Crew.captain:
		return
	$Crew.captain = pilot
	if (multiplayer.get_unique_id() == pilot._multiplayer_id):
		camera.far = 30000
		camera.near = 0.3
		camera.current = true
	$Crew.add_child(pilot)


func add_passenger(pilot: Pilot):
	var max_capacity: int = $Crew.max_passengers
	if $Crew.pilot:
		max_capacity += 1
	if $Crew.captain:
		max_capacity += 1
	if $Crew.get_child_count() >= max_capacity:
		return
	if (multiplayer.get_unique_id() == pilot._multiplayer_id):
		camera.far = 30000
		camera.near = 0.3
		camera.current = true
	$Crew.add_child(pilot)


func remove_passenger() -> Pilot:
	return null
