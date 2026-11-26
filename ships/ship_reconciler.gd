class_name ShipReconciler
extends RefCounted
## Own-ship prediction's network side (netcode N3b/N3c, N4a, time dilation).
## Each Ship owns one (Ship.reconciler). After each tick loop the server sends
## the remote pilot their ship's state and the last input tick it applied
## (send_state); the pilot's client starts again from it, replays its own
## recorded input since (reconcile, through ShipPrediction) and eases the
## correction in (CorrectionSmoother). The RPC itself, Ship._receive_state,
## stays on the ship: Godot routes RPCs by node path.

const REPORT_TICKS := 300  # Every 5 s at 60 Hz.

## The pilot's client records its helms' input here each tick and replays it
## when the server's state arrives.
var prediction := ShipPrediction.new()
## Eases the server's corrections in over a few ticks instead of jumping (N4a).
var smoother := CorrectionSmoother.new()
## The client's lead controller, instead of Galaxy.input_lead (unit tests).
var input_lead_override: InputLead
## Corrections since the last prediction report.
var corrections := 0

var _ship: Ship
var _largest_correction := 0.0
var _next_report_tick := 0
var _last_lead_usec := 0


func _init(ship: Ship) -> void:
	_ship = ship


## Server: tell the remote pilot where their ship is after the ticks just run,
## and which of their inputs that includes. Returns true when sent. A player who
## disconnected can still be seated here, so only connected peers are sent to.
func send_state() -> bool:
	var pilot := _ship.remote_pilot()
	if pilot == null or pilot.input_channel.last_applied_tick < 0:
		return false
	if not pilot.multiplayer_id in _ship.multiplayer.get_peers():
		return false
	# With how many of their inputs are queued, and the cushion: their client
	# steers how far ahead it runs from that (time dilation, InputLead).
	_ship._receive_state.rpc_id(pilot.multiplayer_id, pilot.input_channel.last_applied_tick,
			_ship.global_transform, _ship.linear_velocity, _ship.angular_velocity, _ship.freeze,
			pilot.input_channel.queued(), pilot.input_channel.cushion)
	return true


## The pilot's client: what Ship._receive_state brought. The server had
## [param queued] of our inputs waiting (-1: not sent), with a cushion of
## [param cushion].
func receive(ack: int, server: FlightIntegrator.FlightState, frozen: bool, queued: int,
		cushion: int) -> void:
	if queued >= 0:
		_steer_lead(queued, cushion)
	reconcile(server, ack, NetworkTime.tick - 1, frozen)


## The pilot's client: start again from [param server] (the server's state
## after applying input [param ack]) and replay our own ticks up to
## [param last_tick], the last one this client ran. While the server holds the
## ship [param frozen] (on a launch arm), the arm moves it, not the pilot: the
## client freezes it too and puts it exactly where the server has it, with no
## replay. Released, it is predicted again.
func reconcile(server: FlightIntegrator.FlightState, ack: int, last_tick: int,
		frozen := false) -> void:
	var ship := _ship
	if frozen:
		if not prediction.confirm(ack):
			return  # Older than a state already used.
		ship.freeze = true
		smoother.reset()
		if not ship.held_by_local_arm:  # Else our own arm places it, drawn with the station.
			ship.place(server.transform)
		return
	if ship.freeze:
		ship.freeze = false  # Released by the arm.
	if ship.flight == null:
		ship.flight = FlightIntegrator.from_body(PhysicsServer3D.body_get_direct_state(ship.get_rid()))
	var now := prediction.reconcile(server, ack, last_tick, ship.flight, NetworkTime.ticktime,
			ship.replay_thrust)
	if now == null:
		return  # Older than a state already used.
	ship.place(smoother.apply(ship.global_transform, now.transform))
	var error := smoother.last_correction
	if error > 0.001:
		corrections += 1
		_largest_correction = maxf(_largest_correction, error)
	ship.linear_velocity = now.linear_velocity
	ship.angular_velocity = now.angular_velocity


## The pilot's client, after each tick loop: every 5 s, how many corrections
## the server's states made.
func report() -> void:
	if NetworkTime.tick < _next_report_tick:
		return
	_next_report_tick = NetworkTime.tick + REPORT_TICKS
	if corrections:
		Log.log(["Prediction for ", _ship.name, ": ", corrections, " corrections, largest ",
				"%.3f m" % _largest_correction], Log.MessageType.INFO)
	corrections = 0
	_largest_correction = 0.0


## The pilot's client: the server had [param queued] of our inputs waiting,
## with a cushion of [param cushion]. Steer how far ahead of server time we run
## so they arrive just in time (InputLead), and have netfox run that far ahead.
func _steer_lead(queued: int, cushion: int) -> void:
	var lead := input_lead_override
	if lead == null:
		lead = _ship.galaxy.input_lead if _ship.galaxy else null
	if lead == null:
		return
	var now := Time.get_ticks_usec()
	var dt := NetworkTime.ticktime if _last_lead_usec == 0 else minf((now - _last_lead_usec) / 1e6, 0.25)
	_last_lead_usec = now
	lead.observe(queued, cushion, dt)
	NetworkTime.lead_seconds = lead.lead_seconds
