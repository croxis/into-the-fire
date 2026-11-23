class_name ShipPrediction
extends RefCounted
## Own-ship prediction on the pilot's client (netcode slices N3b/N3c). No nodes
## or networking: Ship records and reconciles through this.
##
## The client flies its ship at once from its own input. Each tick, Ship records
## the thrust it applied, in the ship's own frame. The server, later, sends the
## ship's state together with the client tick of the last input it applied (the
## ack). reconcile() starts again from that state and replays the recorded
## thrust for every tick after the ack, with the same FlightIntegrator, so a
## correct prediction lands exactly where the ship already is and a wrong one
## (a collision, a lost input) is carried forward from the server's truth.
##
## Thrust, not input, is recorded: the helm's flight assist (PIDs) keeps state
## of its own, which replaying input would disturb.

## Ticks of thrust kept at most (two seconds at 60 Hz), if the server goes quiet.
const MAX_HISTORY := 120

var _history: Dictionary[int, Array] = {}  # tick -> [force, torque], ship frame.
var _last_ack := -1


## Remembers the thrust applied at [param tick], in the ship's own frame.
func record(tick: int, local_force: Vector3, local_torque: Vector3) -> void:
	_history[tick] = [local_force, local_torque]
	while _history.size() > MAX_HISTORY:
		_history.erase(_history.keys().min())


## The ship's state at [param last_tick], replayed from [param server] (the
## server's state after applying input [param ack]). Returns null for an ack
## older than one already used. Thrust up to the ack is forgotten.
func reconcile(server: FlightIntegrator.FlightState, ack: int, last_tick: int,
		flight: FlightIntegrator, dt: float) -> FlightIntegrator.FlightState:
	if ack < _last_ack:
		return null
	_last_ack = ack
	for tick in _history.keys():
		if tick <= ack:
			_history.erase(tick)
	var s := server.duplicate()
	for tick in range(ack + 1, last_tick + 1):
		var force := Vector3.ZERO
		var torque := Vector3.ZERO
		if _history.has(tick):
			var basis := s.transform.basis
			force = basis * _history[tick][0]
			torque = basis * _history[tick][1]
		s = flight.step(s, force, torque, dt)
	return s


## The earliest tick still recorded, or -1 when none is.
func oldest_tick() -> int:
	return _history.keys().min() if not _history.is_empty() else -1


func size() -> int:
	return _history.size()
