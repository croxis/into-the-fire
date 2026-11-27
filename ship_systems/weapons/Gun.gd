extends Node3D
class_name Gun

@export var damage: float
@export var cooldown: float
# If a projectile weapon, what is the speed of the bolt
@export var speed: float
@export var bolt_resource: PackedScene

## Fired at [param tick] (netcode ticks): what makes a bolt and its sound
## listens to this.
signal fired(gun: Gun, tick: int)

## The first tick it may fire again.
var _ready_tick := -1


## The cooldown in netcode ticks, at least one.
func cooldown_ticks() -> int:
	return maxi(1, ceili(cooldown / NetworkTime.ticktime))


## Fires at [param tick] if its cooldown has passed; true if it fired. Ticks,
## not frames, so the server and the shooter's client agree on when it fires.
func fire_at(tick: int) -> bool:
	if tick < _ready_tick:
		return false
	_ready_tick = tick + cooldown_ticks()
	fired.emit(self, tick)
	return true
