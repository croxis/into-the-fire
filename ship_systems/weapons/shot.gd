class_name Shot
extends RefCounted
## One shot from a gun (weapons netcode): a straight line from [member origin]
## at [member velocity], from server tick [member fire_tick]. Plain data, moved
## by tick number rather than by physics, so every machine that knows a shot
## puts it in the same place for the same tick. ShotField flies them; the
## server checks each tick's stretch of the path for hits.

## Ticks a shot lasts (10 s at 60 Hz), as the old bolts did.
const LIFETIME_TICKS := 600

var origin: Vector3
var velocity: Vector3
var fire_tick: int
## Damage at the muzzle; it falls off with time in flight (damage_at).
var damage: float
## The ship that fired it: never hit by its own shots.
var shooter: Ship


func _init(from: Vector3, v: Vector3, tick: int, muzzle_damage: float, fired_by: Ship = null) -> void:
	origin = from
	velocity = v
	fire_tick = tick
	damage = muzzle_damage
	shooter = fired_by


## Where the shot is at [param tick] (fractional ticks between).
func position_at(tick: float) -> Vector3:
	return origin + velocity * (seconds_at(tick))


func seconds_at(tick: float) -> float:
	return (tick - fire_tick) * NetworkTime.ticktime


## Damage on a hit at [param tick]: the muzzle damage / (1 + 0.2 x seconds in
## flight), as the old bolts grew and weakened.
func damage_at(tick: float) -> float:
	return damage / (1.0 + 0.2 * seconds_at(tick))


func expired_at(tick: int) -> bool:
	return tick - fire_tick >= LIFETIME_TICKS
