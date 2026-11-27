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
## Fired on this client by its own pilot (prediction): its fire_tick is this
## machine's tick, and it is drawn on that timeline, with the predicted ship.
## Otherwise drawn at the moment this machine shows other ships
## (Galaxy.shown_tick), where its shooter is.
var predicted := false
## Server: ticks back its hits are checked against targets, to where its
## shooter saw them (favour the shooter, ShotField.rewind_for); 0 for NPCs and
## the host.
var rewind_ticks := 0
## Which gun of its ship fired it (its index under Guns): with the fire tick,
## how a hit event names it.
var gun_index := 0
## Server: the tick of the input that fired it on its pilot's client (that
## client knows its own copy by this tick), or -1 (an NPC's, the host's).
var client_tick := -1


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
