extends Node3D
class_name Gun

@export var damage: float
@export var cooldown: float
# If a projectile weapon, what is the speed of the bolt
@export var speed: float
@export var bolt_resource: PackedScene
## The bolt's radius at the muzzle, in metres (Shot.radius).
@export var bolt_radius := 0.0
## How fast its bolts dissipate: growth in muzzle sizes per second, damage
## spread over the larger bolt (Shot.growth).
@export var growth := 0.2

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
## [param client_tick]: the remote pilot's input tick that fired it (Shot.client_tick).
func fire_at(tick: int, rewind := 0, client_tick := -1) -> bool:
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
		shot.client_tick = client_tick
		shot.gun_index = get_index()
		system.shots.add(shot)
		if serving and ship and multiplayer.has_multiplayer_peer():
			ship.announce_shot(get_index(), shot)
	fired.emit(self, tick)
	return true


## Plays this gun's firing sound, if it has one (each Bolt calls it when it is
## first drawn; there are no bolts on headless machines).
func play_fire_sound() -> void:
	var player := get_node_or_null(^"AudioStreamPlayer3D") as AudioStreamPlayer3D
	if player and player.stream:
		player.play()


## A shot from the muzzle at [param tick]: along the gun's +z at its speed,
## plus its ship's own velocity. Guns fire along +z, not Godot's -z forward:
## the scenes are built that way (the Starfury's Guns node is turned half a
## turn, so its guns' +z is the ship's forward).
func make_shot(tick: int) -> Shot:
	var ship := ShotField._ship_of(self)
	var v := global_basis.z.normalized() * speed
	if ship:
		v += ship.linear_velocity
	return shot_from(global_position, v, tick)


## A shot of this gun's from [param origin] at [param velocity], fired at
## [param tick]: the gun's damage and bolt size (a client builds the shots it
## is told about this way; a fire event carries only the path).
func shot_from(origin: Vector3, velocity: Vector3, tick: int) -> Shot:
	var shot := Shot.new(origin, velocity, tick, damage, ShotField._ship_of(self))
	shot.radius = bolt_radius
	shot.growth = growth
	return shot
