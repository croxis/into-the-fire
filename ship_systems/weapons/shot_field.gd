class_name ShotField
extends RefCounted
## The shots flying in one star system (System.shots). Stepped once per tick
## after the system's physics step (ZoneStepper -> System.after_step), so the
## hulls are where this tick put them. On the server each shot's stretch of
## path this tick is checked against them, and a hit does damage
## (Ship.take_shot); clients only draw shots (a Bolt each, on machines that
## render).

const BoltScene := preload("res://ship_systems/weapons/effects/bolt/Bolt.tscn")
## Retries past the shooter's own hull (the muzzle can sit inside it).
const MAX_RAY_RETRIES := 4
## The furthest back a shot is checked (250 ms): favouring the shooter past
## this would let a target be hit long after it reached cover on its own screen.
const MAX_REWIND_TICKS := 15
## Ticks of ship transforms kept (server), for rewound checks.
const HISTORY_TICKS := MAX_REWIND_TICKS + 2

var _system: System
var _hits_allowed: bool
## Server: [param shot] hit [param target] at [param at] this tick.
signal hit(shot: Shot, target: Ship, at: Vector3)

var _shots: Array[Shot] = []
var _bolts: Dictionary[Shot, Node3D] = {}
## Server: ship -> {tick: global transform}, the last HISTORY_TICKS ticks.
var _history: Dictionary[Ship, Dictionary] = {}
## Where the last hit _hit found struck (on the target as it is now).
var _last_hit_at := Vector3.ZERO
## Counted since the last report (report).
var _fired := 0
var _hits := 0


## Ticks back to check a remote player's shot fired at server tick
## [param server_tick], from their input for client tick [param input_tick],
## made while they showed other ships [param view_ticks] behind it: from now
## to the server tick they were looking at, 0 to MAX_REWIND_TICKS.
static func rewind_for(server_tick: int, input_tick: int, view_ticks: int) -> int:
	return clampi(server_tick - (input_tick - view_ticks), 0, MAX_REWIND_TICKS)


## Server, after each physics step: where every ship in the system is at
## [param tick], for rewound checks.
func record_history(tick: int) -> void:
	if _system.multiplayer.has_multiplayer_peer() and not _system.multiplayer.is_server():
		return
	for ship in _system.get_ships():
		var h: Dictionary = _history.get_or_add(ship, {})
		h[tick] = ship.global_transform
		h.erase(tick - HISTORY_TICKS)
	for ship in _history.keys():
		if not is_instance_valid(ship) or not ship.is_inside_tree():
			_history.erase(ship)


## Where [param ship] was at [param tick], or where it is now if that's not kept.
func _transform_at(ship: Ship, tick: int) -> Transform3D:
	var h: Dictionary = _history.get(ship, {})
	return h.get(tick, ship.global_transform)


## Shots play their gun's sound as they are added: on machines that make sound
## (not headless ones: a dedicated server, the tests).
var plays_sounds := DisplayServer.get_name() != "headless"


## [param hits_allowed] false: this field never decides hits, even on a server.
func _init(system: System, hits_allowed := true) -> void:
	_system = system
	_hits_allowed = hits_allowed


func add(shot: Shot) -> void:
	_shots.append(shot)
	_fired += 1
	if DisplayServer.get_name() != "headless" and _system.has_node("bolts"):
		var bolt: Bolt = BoltScene.instantiate()
		bolt.shot = shot
		_system.get_node("bolts").add_child(bolt)
		_bolts[shot] = bolt
	if plays_sounds:
		var gun := _gun_of(shot)
		if gun:
			gun.play_fire_sound()


## The gun that fired [param shot] (its shooter's gun at Shot.gun_index), or null.
static func _gun_of(shot: Shot) -> Gun:
	if shot.shooter == null or not is_instance_valid(shot.shooter):
		return null
	var guns := shot.shooter.get_node_or_null(^"Guns")
	if guns == null or shot.gun_index >= guns.get_child_count():
		return null
	return guns.get_child(shot.gun_index) as Gun


## "N fired, M hits" since the last report, or "" if nothing fired (System
## logs it every 5 s).
func report() -> String:
	if _fired == 0 and _hits == 0:
		return ""
	var line := "%d fired, %d hits" % [_fired, _hits]
	_fired = 0
	_hits = 0
	return line


func count() -> int:
	return _shots.size()


func all() -> Array[Shot]:
	return _shots.duplicate()


## After the system's physics step for [param tick]: hits (server), then
## shots past their lifetime.
func step(tick: int) -> void:
	var decides := _hits_allowed and (not _system.multiplayer.has_multiplayer_peer() or _system.multiplayer.is_server())
	for shot in _shots.duplicate():
		if decides:
			var target := _hit(shot, tick)
			if target:
				target.take_shot(shot.damage_at(tick), shot)
				_hits += 1
				_remove(shot)
				show_hit(_last_hit_at)
				hit.emit(shot, target, _last_hit_at)
				if shot.shooter and is_instance_valid(shot.shooter) and _system.multiplayer.has_multiplayer_peer():
					shot.shooter.announce_hit(shot, _last_hit_at)
				continue
		if shot.expired_at(tick):
			_remove(shot)


## The ship [param shot] hits between the last tick and [param tick], or null.
func _hit(shot: Shot, tick: int) -> Ship:
	var from := shot.position_at(maxi(shot.fire_tick, tick - 1))
	var to := shot.position_at(tick)
	if from == to:
		return null
	if shot.rewind_ticks > 0:
		return _rewound_hit(shot, tick, from, to)
	var space := _system.find_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if shot.shooter and is_instance_valid(shot.shooter):
		exclude.append(shot.shooter.get_rid())  # A bolt starts inside its own ship's reach.
	for i in MAX_RAY_RETRIES:
		var result := _sweep(space, from, to, shot.radius_at(tick), exclude)
		if result.is_empty():
			return null
		var ship := _ship_of(result.collider)
		if ship and ship != shot.shooter:
			_last_hit_at = result.position
			return ship
		exclude.append(result.rid)  # The shooter's own hull, or something not a ship.
	return null


## Client: drops [param shooter]'s shot from gun [param gun] fired at
## [param tick] (a hit event names it so). False if there is none.
func remove_named(shooter: Ship, gun: int, tick: int) -> bool:
	for shot in _shots:
		if shot.shooter == shooter and shot.gun_index == gun and shot.fire_tick == tick:
			_remove(shot)
			return true
	return false


## A brief flash at [param at], on machines that render.
func show_hit(at: Vector3) -> void:
	if DisplayServer.get_name() == "headless" or not _system.has_node("bolts"):
		return
	var flash := HitFlash.new()
	_system.get_node("bolts").add_child(flash)
	flash.global_position = at


## Bytes of a hit event (encode_hit): gun index (u8), the shot's fire tick as
## the receiving client knows it (s32), where it hit (3 doubles).
const HIT_BYTES := 29


static func encode_hit(gun: int, tick: int, at: Vector3) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(HIT_BYTES)
	b[0] = gun
	b.encode_s32(1, tick)
	for i in 3:
		b.encode_double(5 + i * 8, at[i])
	return b


## {"gun", "tick", "position"} from [param bytes] (encode_hit), or null.
static func decode_hit(bytes: Variant) -> Variant:
	if not bytes is PackedByteArray or (bytes as PackedByteArray).size() != HIT_BYTES:
		return null
	var b: PackedByteArray = bytes
	var at := Vector3(b.decode_double(5), b.decode_double(13), b.decode_double(21))
	if not at.is_finite():
		return null
	return {"gun": b[0], "tick": b.decode_s32(1), "position": at}


## Bytes of a fire event (encode_fire): gun index (u8), fire tick (s32),
## origin (3 doubles: large world coordinates), velocity (3 float32).
const FIRE_BYTES := 41


## Server: a fire event for [param shot] from gun [param gun] of its ship.
static func encode_fire(gun: int, shot: Shot) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(FIRE_BYTES)
	b[0] = gun
	b.encode_s32(1, shot.fire_tick)
	for i in 3:
		b.encode_double(5 + i * 8, shot.origin[i])
		b.encode_float(29 + i * 4, shot.velocity[i])
	return b


## Client: {"gun", "tick", "origin", "velocity"} from [param bytes]
## (encode_fire), or null when they aren't a fire event.
static func decode_fire(bytes: Variant) -> Variant:
	if not bytes is PackedByteArray or (bytes as PackedByteArray).size() != FIRE_BYTES:
		return null
	var b: PackedByteArray = bytes
	var origin := Vector3(b.decode_double(5), b.decode_double(13), b.decode_double(21))
	var velocity := Vector3(b.decode_float(29), b.decode_float(33), b.decode_float(37))
	if not origin.is_finite() or not velocity.is_finite():
		return null
	return {"gun": b[0], "tick": b.decode_s32(1), "origin": origin, "velocity": velocity}


## [param shot]'s hit from [param from] to [param to] (this tick's stretch)
## against each ship where it was [member Shot.rewind_ticks] back. Physics only
## knows hulls where they are now, so the stretch is moved with each ship from
## then to now (its transform now x its transform then, inverted) and tested
## against that ship alone. The nearest hit along the stretch wins.
func _rewound_hit(shot: Shot, tick: int, from: Vector3, to: Vector3) -> Ship:
	var space := _system.find_world_3d().direct_space_state
	var best: Ship = null
	var best_fraction := INF
	var best_at := Vector3.ZERO
	for ship in _system.get_ships():
		if ship == shot.shooter:
			continue
		var then_from := _transform_at(ship, tick - 1 - shot.rewind_ticks)
		var then_to := _transform_at(ship, tick - shot.rewind_ticks)
		var radius := ship.visual_radius() + shot.radius_at(tick)  # Hull and bolt.
		if Geometry3D.get_closest_point_to_segment(then_to.origin, from, to).distance_to(then_to.origin) \
				> radius + from.distance_to(to):
			continue
		var now := ship.global_transform
		var a := now * (then_from.affine_inverse() * from)
		var b := now * (then_to.affine_inverse() * to)
		var fraction := _ray_fraction(space, a, b, ship, shot.radius_at(tick))
		if fraction < best_fraction:
			best_fraction = fraction
			best = ship
			best_at = a.lerp(b, fraction)
	if best:
		_last_hit_at = best_at
	return best


## How far along [param a] to [param b] (0 to 1) a bolt of [param radius]
## first touches [param ship]'s own hull, or INF; other bodies in the way are
## passed through.
static func _ray_fraction(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, ship: Ship,
		radius := 0.0) -> float:
	var exclude: Array[RID] = []
	for i in MAX_RAY_RETRIES:
		var result := _sweep(space, a, b, radius, exclude)
		if result.is_empty():
			return INF
		if _ship_of(result.collider) == ship:
			return result.fraction
		exclude.append(result.rid)
	return INF


## The first body a bolt of [param radius] touches going from [param a] to
## [param b], skipping [param exclude]: {collider, rid, position, fraction
## (0 to 1 along the way)}, or empty. Radius 0 is a ray; otherwise a sphere
## swept along the way (cast_motion finds how far it gets, get_rest_info what
## it touched there).
static func _sweep(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, radius: float,
		exclude: Array[RID]) -> Dictionary:
	if radius <= 0.0:
		var ray := PhysicsRayQueryParameters3D.create(a, b)
		ray.exclude = exclude
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			return {}
		return {collider = hit.collider, rid = hit.rid, position = hit.position,
				fraction = a.distance_to(hit.position) / maxf(a.distance_to(b), 1e-9)}
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), a)
	query.motion = b - a
	query.exclude = exclude
	var reach := space.cast_motion(query)
	if reach.size() < 2 or reach[0] >= 1.0:
		return {}  # [1, 1]: nothing in the way.
	query.transform.origin = a + (b - a) * reach[1]
	query.motion = Vector3.ZERO
	var info := space.get_rest_info(query)
	if info.is_empty():
		return {}
	return {collider = instance_from_id(info.collider_id), rid = info.rid, position = info.point,
			fraction = reach[1]}


static func _ship_of(node: Object) -> Ship:
	var n := node as Node
	while n and not n is Ship:
		n = n.get_parent()
	return n as Ship


func _remove(shot: Shot) -> void:
	_shots.erase(shot)
	var bolt: Node3D = _bolts.get(shot)
	if bolt and is_instance_valid(bolt):
		bolt.queue_free()
	_bolts.erase(shot)
