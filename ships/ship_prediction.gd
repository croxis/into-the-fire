class_name ShipPrediction
extends RefCounted
## Own-ship prediction on the pilot's client (netcode slices N3b/N3c). No nodes
## or networking: Ship records and reconciles through this.
##
## The client flies its ship at once from its own input. Each tick, Ship records
## the input its helms used. The server, later, sends the ship's state together
## with the client tick of the last input it applied (the ack). reconcile()
## starts again from that state and replays the recorded input for every tick
## after the ack, with the same FlightIntegrator, so a correct prediction lands
## exactly where the ship already is and a wrong one (a collision, a lost
## input) is carried forward from the server's truth.
##
## Input, not thrust, is recorded: flight assist (autospin, autobreak) works
## thrust out from the ship's spin and speed at that tick, so after a correction
## the replay must work it out again from the replayed state, as the server did.
## The caller passes how (thrust_for).

## Ticks of thrust kept at most (two seconds at 60 Hz), if the server goes quiet.
const MAX_HISTORY := 120

var _history: Dictionary[int, Variant] = {}  # tick -> input, as the caller recorded it.
var _last_ack := -1


## Remembers the input used at [param tick].
func record(tick: int, input: Variant) -> void:
	_history[tick] = input
	while _history.size() > MAX_HISTORY:
		_history.erase(_history.keys().min())


## The ship's state at [param last_tick], replayed from [param server] (the
## server's state after applying input [param ack]). [param thrust_for] gives
## [force, torque] in world space for (input, state before the tick). A tick
## with no input recorded (none yet) coasts. Returns null for an ack older
## than one already used. Input up to the ack is forgotten.
func reconcile(server: FlightIntegrator.FlightState, ack: int, last_tick: int,
		flight: FlightIntegrator, dt: float, thrust_for: Callable) -> FlightIntegrator.FlightState:
	if not confirm(ack):
		return null
	var s := server.duplicate()
	for tick in range(ack + 1, last_tick + 1):
		var push: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
		if _history.has(tick):
			push = thrust_for.call(_history[tick], s)
		s = flight.step(s, push[0], push[1], dt)
	return s


## The server has applied input [param ack]: forget input up to it. False for
## an ack older than one already used (nothing changes then).
func confirm(ack: int) -> bool:
	if ack < _last_ack:
		return false
	_last_ack = ack
	for tick in _history.keys():
		if tick <= ack:
			_history.erase(tick)
	return true


## The earliest tick still recorded, or -1 when none is.
func oldest_tick() -> int:
	return _history.keys().min() if not _history.is_empty() else -1


func size() -> int:
	return _history.size()
