class_name PatrolRoute
extends Node3D
## A default patrol route authored in a capital ship's or station's scene: its
## Marker3D children are the waypoints, flown in order and, when [member loop],
## round again. Routes live under the ship's PatrolRoutes node, beside the
## hull (not under a rotating section). A commander posting a patrol takes one
## that fits (pick), or builds a ring when none does.
##
## Routes travel in objectives relative to their anchor ship, in its frame with
## scale left out (anchor_frame, from_anchor), so a moving carrier's patrol moves with it
## and a scaled ship doesn't stretch it.

## Waypoints in a ring a commander builds.
const RING_POINTS := 6
## How far out a built ring sits, as a share of the radius wanted.
const RING_SHARE := 0.6

## Fly the route round again after the last waypoint.
@export var loop := true


## This route's waypoints, relative to [param anchor] (anchor_frame).
func waypoints(anchor: Node3D) -> Array[Vector3]:
	var inverse := anchor_frame(anchor).affine_inverse()
	var out: Array[Vector3] = []
	for child in get_children():
		if child is Marker3D:
			out.append(inverse * (child as Marker3D).global_position)
	return out


## [param anchor]'s position and rotation, without scale: the frame routes are
## kept in.
static func anchor_frame(anchor: Node3D) -> Transform3D:
	return Transform3D(anchor.global_basis.orthonormalized(), anchor.global_position)


## [param points], relative to [param anchor], in its system's space.
static func from_anchor(anchor: Node3D, points: Array) -> Array[Vector3]:
	var frame := anchor_frame(anchor)
	var out: Array[Vector3] = []
	for p: Vector3 in points:
		out.append(frame * p)
	return out


## [param count] waypoints on a level ring of [param radius] metres round the
## anchor, starting [param phase] of a step round.
static func ring(radius: float, count := RING_POINTS, phase := 0.0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in count:
		var angle := TAU * (i + phase) / count
		out.append(Vector3(cos(angle), 0.0, sin(angle)) * radius)
	return out


## Whether every waypoint is within [param radius] of the anchor (and there is
## at least one).
static func fits_within(points: Array, radius: float) -> bool:
	if points.is_empty():
		return false
	for p: Vector3 in points:
		if p.length() > radius:
			return false
	return true


## The default routes in [param ship]'s scene.
static func routes_of(ship: Node3D) -> Array[PatrolRoute]:
	var out: Array[PatrolRoute] = []
	var holder := ship.get_node_or_null("PatrolRoutes")
	if holder:
		for child in holder.get_children():
			if child is PatrolRoute:
				out.append(child)
	return out


## Waypoints, relative to [param anchor], for a patrol within [param radius]:
## the first authored route that fits, else a built ring.
static func pick(anchor: Node3D, radius: float) -> Array[Vector3]:
	for route in routes_of(anchor):
		var points := route.waypoints(anchor)
		if fits_within(points, radius):
			return points
	return ring(radius * RING_SHARE)
