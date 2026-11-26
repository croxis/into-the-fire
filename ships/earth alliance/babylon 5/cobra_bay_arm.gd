extends Node3D
## One of Babylon 5's cobra bay launch arms. It runs on the clock, not on timers
## and free-running animations: given a ship, the server notes the tick the
## deploy starts (WAIT_TICKS on) and tells the clients that know the station;
## each machine then poses the arm from time (update_to), the server by its
## tick and a client at the moment it draws the station (Galaxy.shown_tick). So
## every client's arm is where the server's is at that moment. The server holds
## the ship at the arm's spawn point until the deploy ends, then lets it go.

## Ticks from a ship arriving to the arm swinging out: one second.
const WAIT_TICKS := 60
## Speed the ship leaves the arm at, along its nose (about Babylon 5's spin
## at the bays).
const LAUNCH_SPEED := 30.0

var is_empty := false:
	get:
		if $"loading/loadingexternder/extender-rotating/spawn_point".get_child_count() == 0 and is_ready:
			return true
		return false

var is_ready := true

## Server: the ship on the arm, until the deploy lets it go.
var ship: Ship
## The server tick the deploy animation starts, or -1 with no launch under way.
var deploy_start_tick := -1
## Client: the launching ship's name (it may not have spawned here yet).
var _ship_name := ""


func _process(_delta: float) -> void:
	if deploy_start_tick >= 0:
		update_to(Galaxy.shown_tick(self))


## Server: [param _newship] launches from this arm.
func spawn_ship(_newship: Ship):
	if not is_empty:
		Log.log(["NOT EMPTY!", name], Log.MessageType.WARNING)
		return
	ship = _newship
	ship.freeze = true
	is_ready = false
	deploy_start_tick = NetworkTime.tick + WAIT_TICKS
	_place_ship()
	var station := _station()
	if multiplayer.has_multiplayer_peer() and station:
		for peer in multiplayer.get_peers():
			if station.interest.is_known_to(peer):
				_deploy.rpc_id(peer, deploy_start_tick, String(ship.name))
	Log.log(["Spawn Ship:", _newship], Log.MessageType.INFO)


## Clients: this arm launches [param ship_name], its deploy starting at server
## tick [param start_tick].
@rpc("authority", "call_remote", "reliable")
func _deploy(start_tick: int, ship_name: String) -> void:
	deploy_start_tick = start_tick
	_ship_name = ship_name
	is_ready = false


## Poses the arm for server tick [param server_ticks] (fractional): waiting,
## swinging out with the ship, or swinging back. The server lets the ship go
## as the deploy ends.
func update_to(server_ticks: float) -> void:
	if deploy_start_tick < 0:
		return
	var ticks := server_ticks - deploy_start_tick
	var tick_seconds := NetworkTime.ticktime
	var own := _own_ship_here()
	if ticks < deploy_ticks():
		_pose("deploy", maxf(ticks, 0.0) * tick_seconds)
		_place_ship()
		# The pilot's client: their ship rides this arm, drawn with the station,
		# while the server still holds it. Its release can arrive before this
		# arm (drawn in the past) ends the swing: from then on prediction flies it.
		if own and own.freeze:
			own.held_by_local_arm = true
			own.place(_spawn_transform())
		elif own:
			own.held_by_local_arm = false
		return
	if own:
		own.held_by_local_arm = false  # The server's release takes over (prediction).
	if ship:  # Server: the deploy is over.
		_place_ship()
		ship.freeze = false
		ship.linear_velocity = -ship.global_transform.basis.z.normalized() * LAUNCH_SPEED
		ship = null
		Log.log(["Finish deploy animation"], Log.MessageType.INFO)
	if ticks < deploy_ticks() + return_ticks():
		_pose("return", (ticks - deploy_ticks()) * tick_seconds)
		return
	_pose("return", return_ticks() * tick_seconds)
	deploy_start_tick = -1
	_ship_name = ""
	is_ready = true


func deploy_ticks() -> float:
	return $AnimationPlayer.get_animation("deploy").length / NetworkTime.ticktime


func return_ticks() -> float:
	return $AnimationPlayer.get_animation("return").length / NetworkTime.ticktime


## The arm as [param animation] has it [param seconds] in.
func _pose(animation: StringName, seconds: float) -> void:
	var player: AnimationPlayer = $AnimationPlayer
	if player.assigned_animation != animation:
		player.play(animation)
		player.pause()
	player.seek(seconds, true)


## Server: the ship at the arm's spawn point. Position and rotation only: the
## bays sit under scaled nodes (a spawn point's global scale is 0.81), which
## would shrink the ship and its thrust.
func _place_ship() -> void:
	if ship:
		ship.global_transform = _spawn_transform()


func _spawn_transform() -> Transform3D:
	var at: Transform3D = $"loading/loadingexternder/extender-rotating/spawn_point".global_transform
	return Transform3D(at.basis.orthonormalized(), at.origin)


## Client: the launching ship, if it has spawned here and this client predicts
## it (our player is its pilot), else null.
func _own_ship_here() -> Ship:
	if _ship_name.is_empty():
		return null
	var system := System.find_for(self)
	var found := system.get_node_or_null(NodePath("ships/" + _ship_name)) as Ship if system else null
	return found if found and found.is_predicted_here() else null


func _station() -> Ship:
	var n := get_parent()
	while n and not n is Ship:
		n = n.get_parent()
	return n as Ship
