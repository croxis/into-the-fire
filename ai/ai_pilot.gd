class_name AiPilot
extends RefCounted
## How an NPC flies (server only): it works out the helm throttles a pilot's
## controls would set, each tick (Character._apply_input, InputSource.AI). Fly
## to a point and hold there (fly_to), follow a route (follow), or hands off
## (stop). Every NPC character has one; it does nothing until given orders.
##
## Newtonian, like the players' ships: it chooses the velocity it wants (toward
## the target, no faster than it can still brake from, braking on its reverse
## thrusters alone), then points the nose at the velocity change it needs and
## lets each axis thrust toward it. Ships strafe weakly (a Starfury: 37.5 m/s²
## forward, 4.2 sideways), so the main engines do most of the work, as for a
## player. Each ship's accelerations come from its own thrusters.

## Within this distance of a point to hold, it counts as there.
const HOLD_RADIUS := 50.0
## A route's waypoints are passed within this distance, without stopping.
const PASS_RADIUS := 200.0
## Cruise speed, in m/s.
const CRUISE_SPEED := 250.0
## Share of the reverse thrust it plans its braking with.
const BRAKE_MARGIN := 0.8
## Close in, it slows to this share of the remaining distance per second, so it
## settles on a point instead of circling it (the braking curve alone is too
## fast for a pilot that must turn first).
const APPROACH_RATE := 0.25
## Seconds to close a velocity difference at full thrust: smaller is snappier.
const RESPONSE := 0.25
## Rotation: throttle per radian of heading error, and per rad/s of spin.
const TURN_GAIN := 2.0
const SPIN_DAMPING := 1.0
## Below this velocity change (m/s) it points at the target instead.
const SETTLE_SPEED := 5.0

## The waypoint being flown to (follow).
var waypoint_index := 0

var _route: Array[Vector3] = []
var _loop := false
var _anchor: WeakRef = null  # Route points are relative to it when set.
var _last_anchor_frame := Transform3D()
var _active := false


## Fly to [param point] (system space) and hold there.
func fly_to(point: Vector3) -> void:
	follow([point], false)


## Fly [param route] (system space, or relative to [param anchor] when given:
## PatrolRoute.from_anchor), passing each waypoint; round again when
## [param loop], else hold at the last.
func follow(route: Array[Vector3], loop: bool, anchor: Node3D = null) -> void:
	_route = route.duplicate()
	_loop = loop
	_anchor = weakref(anchor) if anchor else null
	if anchor:
		_last_anchor_frame = PatrolRoute.anchor_frame(anchor)
	waypoint_index = 0
	_active = not _route.is_empty()


## Hands off: no orders.
func stop() -> void:
	_active = false
	_route.clear()


func has_orders() -> bool:
	return _active


## True once a route that doesn't loop has reached its last waypoint (it then
## holds there).
func is_done() -> bool:
	return _active and not _loop and waypoint_index == _route.size() - 1 \
			and _arrived_at_last


var _arrived_at_last := false


## Where it is flying to now, in system space.
func current_target() -> Vector3:
	if _route.is_empty():
		return Vector3.ZERO
	var anchor: Node3D = _anchor.get_ref() if _anchor else null
	if anchor and anchor.is_inside_tree():
		_last_anchor_frame = PatrolRoute.anchor_frame(anchor)
	if _anchor:
		return _last_anchor_frame * _route[waypoint_index]
	return _route[waypoint_index]


## [throttle, rotation throttle] for [param ship] this tick: what a pilot's
## controls would set at its helm. Zero without orders.
func steer(ship: Ship) -> Array[Vector3]:
	if not _active or ship == null:
		return [Vector3.ZERO, Vector3.ZERO]
	var target := current_target()
	var last := waypoint_index == _route.size() - 1
	var holding := last and not _loop
	var to_target := target - ship.global_position
	var distance := to_target.length()
	# Next waypoint once this one is passed.
	if not holding and distance < PASS_RADIUS:
		waypoint_index = (waypoint_index + 1) % _route.size()
		target = current_target()
		to_target = target - ship.global_position
		distance = to_target.length()
		last = waypoint_index == _route.size() - 1
		holding = last and not _loop
	if holding and distance < HOLD_RADIUS:
		_arrived_at_last = true
	var a := accelerations(ship)
	# The speed it can still brake from (to a stop when holding, to half cruise
	# when passing through).
	var end_speed := 0.0 if holding else CRUISE_SPEED * 0.5
	var brake: float = a.reverse * BRAKE_MARGIN
	var reach := maxf(distance - (HOLD_RADIUS * 0.5 if holding else 0.0), 0.0)
	var speed := minf(CRUISE_SPEED, sqrt(end_speed * end_speed + 2.0 * brake * reach))
	if holding:
		speed = minf(speed, distance * APPROACH_RATE)
	var wanted := to_target.normalized() * speed if distance > 0.01 else Vector3.ZERO
	var change := wanted - ship.linear_velocity
	var to_local := ship.global_basis.orthonormalized().transposed()
	return [_throttle(to_local * change, a), _turn(ship, to_local, change, to_target)]


## Per-axis throttle toward the velocity change [param change_local].
static func _throttle(change_local: Vector3, a: Dictionary) -> Vector3:
	var t := Vector3.ZERO
	t.x = clampf(change_local.x / (a.lateral * RESPONSE), -1.0, 1.0) if a.lateral > 0.0 else 0.0
	t.y = clampf(change_local.y / (a.vertical * RESPONSE), -1.0, 1.0) if a.vertical > 0.0 else 0.0
	# -Z is forward: the main engines push toward -Z, the reverse ones toward +Z.
	var along: float = a.forward if change_local.z < 0.0 else a.reverse
	t.z = clampf(change_local.z / (along * RESPONSE), -1.0, 1.0) if along > 0.0 else 0.0
	return t


## Rotation throttle turning the nose (-Z) toward the velocity change wanted,
## or toward the target once that change is small; roll is only damped.
static func _turn(ship: Ship, to_local: Basis, change: Vector3, to_target: Vector3) -> Vector3:
	var aim := change if change.length() > SETTLE_SPEED else to_target
	var spin := ship.local_angular_velocity
	var rotation := Vector3(-spin.x, -spin.y, -spin.z) * SPIN_DAMPING
	if aim.length() > 0.01:
		var nose := Vector3(0, 0, -1)
		var want := (to_local * aim).normalized()
		var axis := nose.cross(want)
		var angle := nose.angle_to(want)
		if axis.length() < 0.0001 and angle > 1.0:
			axis = Vector3.UP  # Straight behind: turn either way.
		if axis.length() > 0.0001:
			var turn := axis.normalized() * angle * TURN_GAIN
			rotation.x += turn.x
			rotation.y += turn.y
	return rotation.clamp(-Vector3.ONE, Vector3.ONE)


## The ship's accelerations at full throttle, m/s²: "forward" (main engines),
## "reverse", "lateral" and "vertical" (the weaker of each pair). Measured the
## way its engines really push (Engines.request_thrust, then their net force):
## many thrusters are angled, so their rated forces don't simply add up.
## Measured once per ship; the helm sets the real throttles later the same
## tick, so measuring leaves nothing behind.
static func accelerations(ship: Ship) -> Dictionary:
	if ship.has_meta(&"ai_accelerations"):
		return ship.get_meta(&"ai_accelerations")
	var out := {"forward": 0.0, "reverse": 0.0, "lateral": 0.0, "vertical": 0.0}
	var engines := ship.get_node_or_null("Engines")
	if engines == null or ship.mass <= 0.0:
		return out
	out.forward = _push(engines, Vector3(0, 0, -1), ship.mass)
	out.reverse = _push(engines, Vector3(0, 0, 1), ship.mass)
	out.lateral = minf(_push(engines, Vector3(1, 0, 0), ship.mass), _push(engines, Vector3(-1, 0, 0), ship.mass))
	out.vertical = minf(_push(engines, Vector3(0, 1, 0), ship.mass), _push(engines, Vector3(0, -1, 0), ship.mass))
	engines.request_thrust(Vector3.ZERO, Vector3.ZERO)
	ship.set_meta(&"ai_accelerations", out)
	return out


## Acceleration along [param direction] (ship frame) at full throttle that way.
static func _push(engines: Node, direction: Vector3, mass: float) -> float:
	engines.request_thrust(direction, Vector3.ZERO)
	return maxf(engines.linear_force.dot(direction), 0.0) / mass
