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
## [param rewind]: ticks back its shot is checked against targets (W4).
func fire_at(tick: int, rewind := 0) -> bool:
	if tick < _ready_tick:
		return false
	_ready_tick = tick + cooldown_ticks()
	var ship := ShotField._ship_of(self)
	var system := System.find_for(self)
	# The server's shot is the real one, and it tells the clients that know the
	# ship (Ship.announce_shot). The pilot's own client fires its copy at once
	# (prediction). Any other client waits for the server's fire event.
	var serving := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	var predicting := ship != null and ship.is_predicted_here()
	if system and (serving or predicting):
		var shot := make_shot(tick)
		shot.predicted = predicting
		shot.rewind_ticks = rewind
		system.shots.add(shot)
		if serving and ship and multiplayer.has_multiplayer_peer():
			ship.announce_shot(get_index(), shot)
	fired.emit(self, tick)
	return true


## A shot from the muzzle at [param tick]: forward (-z) at the gun's speed,
## plus its ship's own velocity.
func make_shot(tick: int) -> Shot:
	var ship := ShotField._ship_of(self)
	var v := -global_basis.z.normalized() * speed
	if ship:
		v += ship.linear_velocity
	return Shot.new(global_position, v, tick, damage, ship)
