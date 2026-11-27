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

var _system: System
var _hits_allowed: bool
var _shots: Array[Shot] = []
var _bolts: Dictionary[Shot, Node3D] = {}


## [param hits_allowed] false: this field never decides hits, even on a server.
func _init(system: System, hits_allowed := true) -> void:
	_system = system
	_hits_allowed = hits_allowed


func add(shot: Shot) -> void:
	_shots.append(shot)
	if DisplayServer.get_name() != "headless" and _system.has_node("bolts"):
		var bolt: Bolt = BoltScene.instantiate()
		bolt.shot = shot
		_system.get_node("bolts").add_child(bolt)
		_bolts[shot] = bolt


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
			var hit := _hit(shot, tick)
			if hit:
				hit.take_shot(shot.damage_at(tick), shot)
				_remove(shot)
				continue
		if shot.expired_at(tick):
			_remove(shot)


## The ship [param shot] hits between the last tick and [param tick], or null.
func _hit(shot: Shot, tick: int) -> Ship:
	var from := shot.position_at(maxi(shot.fire_tick, tick - 1))
	var to := shot.position_at(tick)
	if from == to:
		return null
	var space := _system.find_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclude: Array[RID] = []
	for i in MAX_RAY_RETRIES:
		query.exclude = exclude
		var result := space.intersect_ray(query)
		if result.is_empty():
			return null
		var ship := _ship_of(result.collider)
		if ship and ship != shot.shooter:
			return ship
		exclude.append(result.rid)  # The shooter's own hull, or something not a ship.
	return null


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
