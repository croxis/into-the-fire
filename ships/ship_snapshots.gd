class_name ShipSnapshots
extends RefCounted
## One ship's motion as tick-stamped snapshots (netcode slices N4b/N4c), not
## through the MultiplayerSynchronizer (it sends motion only when a ship
## appears). Each Ship owns one (Ship.snapshots). The server sends them every
## INTERVAL_TICKS (send); clients keep them in a SnapshotBuffer and draw the
## ship from them a little in the past (draw). The pilot's own client predicts
## its ship instead and ignores them. The RPC itself, Ship._receive_snapshot,
## stays on the ship: Godot routes RPCs by node path.

## Ticks between snapshots: 2 at 60 Hz, so 30 a second.
const INTERVAL_TICKS := 2
const REPORT_TICKS := 300  # Every 5 s at 60 Hz.

## Client: this ship's snapshots, in tick order.
var buffer := SnapshotBuffer.new(1.0 / 60.0)
## When snapshots arrive, so when to draw from them. Shared by every ship in
## the Galaxy (Ship._ready sets it); a ship on its own (tests) keeps its own.
var clock := SnapshotClock.new()
## Set to treat this machine as a client that draws this ship (unit tests).
var drawing_forced := false
## Server: the tick of the last snapshot sent.
var last_sent_tick := -INTERVAL_TICKS

var _ship: Ship
var _drawn := false  # Client: drawn from snapshots, kinematic.
var _drawn_frames := 0  # Since the last drawing report.
var _drawn_behind := 0.0  # Summed ticks behind the newest snapshot.
var _drawn_past_newest := 0  # Frames drawn past the newest (extrapolated).
var _next_report_tick := 0


func _init(ship: Ship) -> void:
	_ship = ship


## Server, after each tick loop: sends the ship's state after [param last_tick]
## to the clients that should have it, when one is due.
func send(last_tick: int) -> void:
	if not is_due(last_tick):
		return
	last_sent_tick = last_tick
	var pilot := _ship.remote_pilot()
	var knows := Callable()
	var galaxy := _ship.galaxy
	if galaxy:
		knows = func(peer: int) -> bool: return galaxy.interest.knows(peer, _ship)
	for peer in recipients(_ship.multiplayer.get_peers(), pilot.multiplayer_id if pilot else 0, knows):
		_ship._receive_snapshot.rpc_id(peer, last_tick, _ship.global_transform,
				_ship.linear_velocity, _ship.angular_velocity)


## Server: whether a snapshot goes out after [param last_tick]. Counted from
## the last one sent, since a loop can run several ticks at once.
func is_due(last_tick: int) -> bool:
	return last_tick - last_sent_tick >= INTERVAL_TICKS


## Server: the peers a snapshot goes to: those that confirmed they have this
## ship (ShipInterest.confirmed, so the RPC finds it) and are still
## [param connected], except [param pilot_peer], who predicts the ship and gets
## its own state, and any that [param knows] (peer -> bool, Galaxy.interest)
## says aren't told about it (netcode N5). Peers that left are forgotten.
func recipients(connected: Array, pilot_peer: int, knows := Callable()) -> Array[int]:
	var out: Array[int] = []
	for peer in _ship.interest.confirmed.keys():
		if not peer in connected:
			_ship.interest.forget(peer)
		elif peer != pilot_peer and (not knows.is_valid() or knows.call(peer)):
			out.append(peer)
	return out


## Client: keeps a snapshot, which arrived at this machine's clock
## [param local_now], for drawing the ship (draw). The newest also sets the
## clock: a late one would make the server look further behind than it is.
## Ignored for the ship this client predicts.
func take(tick: int, s: FlightIntegrator.FlightState, local_now: float) -> void:
	if _ship.is_predicted_here():
		return
	if not buffer.push(tick, s) or tick != buffer.newest_tick():
		return
	clock.observe(tick, local_now)
	if buffer.size() == 1:
		Log.log(["First snapshot for ", _ship.name, " (server tick ", tick, ")"], Log.MessageType.INFO)


## True on a client for a ship it doesn't predict: drawn from snapshots.
func is_drawn_here() -> bool:
	if _ship.is_predicted_here():
		return false
	return drawing_forced or not _ship.multiplayer.is_server()


## Client, each frame: a ship nobody here predicts is drawn from its snapshots
## at the clock's moment, [constant SnapshotClock.DELAY_TICKS] behind the newest
## (netcode slice N4c), instead of being flown here. When this client starts
## predicting it (our player took the helm), it stays frozen until the server's
## first state for the pilot lets it go (ShipReconciler.reconcile), as on a launch
## arm.
##
## [param local_now] is this machine's steady clock in ticks
## (SnapshotClock.local_now), not NetworkTime.tick: netfox runs a client's ticks
## a little fast or slow to catch up with the server, and doesn't tick before a
## game starts, so snapshots measured against it said the server was further
## ahead than it was and ships were drawn past their newest.
func draw(local_now: float) -> void:
	if not is_drawn_here():
		if _drawn:
			_drawn = false
			_ship.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC  # As the launch arms freeze.
		return
	if clock.has_estimate():
		var at := clock.render_tick(local_now)
		if show(at):
			_note_drawn(at)


## Puts the ship where its snapshots have it at server tick [param at],
## kinematic: Jolt doesn't fly it, but other bodies still hit it. Its velocities
## are zeroed: on a kinematic body they would be a conveyor-belt surface
## velocity. False with no snapshots of this ship yet (it stays as it spawned).
func show(at: float) -> bool:
	var s := buffer.sample(at)
	if s == null:
		return false
	if not _drawn:
		_drawn = true
		_ship.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		_ship.freeze = true
		_ship.linear_velocity = Vector3.ZERO
		_ship.angular_velocity = Vector3.ZERO
	_ship.place(s.transform)
	return true


## Client: every 5 s, how far behind its newest snapshot the ship was drawn and
## how often it ran past it (a late or lost snapshot, so extrapolated).
func _note_drawn(at: float) -> void:
	_drawn_frames += 1
	_drawn_behind += buffer.newest_tick() - at
	if at > buffer.newest_tick():
		_drawn_past_newest += 1
	if NetworkTime.tick >= _next_report_tick:
		_next_report_tick = NetworkTime.tick + REPORT_TICKS
		Log.log(["Drawing ", _ship.name, ": ", "%.1f" % (_drawn_behind / _drawn_frames),
				" ticks behind the newest snapshot, ", _drawn_past_newest, " of ", _drawn_frames,
				" frames past it"], Log.MessageType.INFO)
		_drawn_frames = 0
		_drawn_behind = 0.0
		_drawn_past_newest = 0
