extends Node3D
## The Hyperion's launch bays (Bay1..Bay3, Area3Ds under this node).
##
## Follows the launch contract Ship.request_launch expects (see also Babylon 5's
## spawner): find_free_spawner() returns [launch_point, position], or [] when no
## bay is free. Here the launch point is this node, and spawn_ship() launches the
## fighter from the bay that was found.

const BAY_COUNT := 3

## A closed hangar launches nothing (for damage or lockdowns later).
@export var bays_closed := false

var bay: int = 1  # The bay to try first next time, so launches take turns.
var _launch_bay: Area3D  # The bay find_free_spawner() picked for spawn_ship().


func find_free_spawner() -> Array:
	if bays_closed:
		return []
	# Try each bay once. When all are busy, say so instead of looping forever.
	for _i in BAY_COUNT:
		var candidate: Area3D = get_node("Bay" + str(bay))
		bay = bay % BAY_COUNT + 1
		if candidate.get_overlapping_bodies().is_empty():
			_launch_bay = candidate
			return [self, candidate.global_position]
	return []


## Launches [param ship] from the bay found last. Placeholder flight: it faces
## the way the Hyperion faces and keeps the Hyperion's velocity, so the carrier
## doesn't run it over. Tune launch direction and speed here.
func spawn_ship(ship: Ship) -> void:
	var carrier := get_parent() as RigidBody3D
	var at := _launch_bay.global_position if _launch_bay else global_position
	ship.global_transform = Transform3D(global_basis.orthonormalized(), at)
	if carrier:
		ship.linear_velocity = carrier.linear_velocity
