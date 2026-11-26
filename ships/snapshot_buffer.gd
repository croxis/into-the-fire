class_name SnapshotBuffer
extends RefCounted
## A remote ship's recent states from the server, each stamped with the server
## tick it was taken after (netcode slice N4b). No nodes or networking: Ship
## pushes snapshots in as they arrive and asks where the ship was at a moment.
##
## Snapshots come unreliable and can arrive late or out of order; push() keeps
## them in tick order. sample() answers for any tick, fractional ones too
## (render frames fall between ticks): between two snapshots it follows a curve
## that matches both positions and both velocities (cubic Hermite), so a turning
## ship doesn't cut corners; past the newest it carries on at the last velocity
## for a little while (a late packet), then holds.

## Snapshots kept at most: about a second at 30 snapshots a second.
const MAX_SNAPSHOTS := 32
## How far past the newest snapshot a ship keeps moving on its own (250 ms).
## Longer, and a ship that turned or stopped would be shown far from the truth.
const MAX_EXTRAPOLATION_TICKS := 15

var _tick_seconds: float
var _ticks: Array[int] = []  # Oldest first.
var _states: Dictionary[int, FlightIntegrator.FlightState] = {}


func _init(tick_seconds: float) -> void:
	_tick_seconds = tick_seconds


## Adds the state after server tick [param tick]. False when it is a repeat, or
## older than everything kept with the buffer full (nothing changes then).
func push(tick: int, state: FlightIntegrator.FlightState) -> bool:
	if _states.has(tick):
		return false
	if _ticks.size() >= MAX_SNAPSHOTS and tick < _ticks[0]:
		return false
	_ticks.insert(_ticks.bsearch(tick), tick)
	_states[tick] = state.duplicate()
	while _ticks.size() > MAX_SNAPSHOTS:
		_states.erase(_ticks.pop_front())
	return true


## The newest snapshot's tick, or -1 when there are none.
func newest_tick() -> int:
	return _ticks[-1] if not _ticks.is_empty() else -1


func size() -> int:
	return _ticks.size()


## Where the ship was at [param at] (a server tick, fractional for render
## frames), or null with no snapshots yet.
func sample(at: float) -> FlightIntegrator.FlightState:
	if _ticks.is_empty():
		return null
	if at <= _ticks[0]:
		return _states[_ticks[0]].duplicate()
	if at >= _ticks[-1]:
		return _extrapolate(_states[_ticks[-1]], minf(at - _ticks[-1], MAX_EXTRAPOLATION_TICKS))
	var i := _ticks.bsearch(int(floor(at)), false) - 1  # Last tick at or before `at`.
	var ta := _ticks[i]
	var tb := _ticks[i + 1]
	return _between(_states[ta], _states[tb], (at - ta) / (tb - ta), (tb - ta) * _tick_seconds)


## [param s] carried on for [param ticks] at its velocities.
func _extrapolate(s: FlightIntegrator.FlightState, ticks: float) -> FlightIntegrator.FlightState:
	var out := s.duplicate()
	var t := ticks * _tick_seconds
	out.transform.origin += s.linear_velocity * t
	var turn := s.angular_velocity * t
	if turn.length() > 1e-12:
		var scale := s.transform.basis.get_scale()
		out.transform.basis = (Basis(turn.normalized(), turn.length()) * s.transform.basis.orthonormalized()) \
				.orthonormalized() * Basis.from_scale(scale)
	return out


## The state a fraction [param u] of the way from [param a] to [param b], which
## are [param span] seconds apart.
func _between(a: FlightIntegrator.FlightState, b: FlightIntegrator.FlightState, u: float,
		span: float) -> FlightIntegrator.FlightState:
	var u2 := u * u
	var u3 := u2 * u
	var out := FlightIntegrator.FlightState.new()
	out.transform.origin = (2 * u3 - 3 * u2 + 1) * a.transform.origin \
			+ (u3 - 2 * u2 + u) * span * a.linear_velocity \
			+ (-2 * u3 + 3 * u2) * b.transform.origin \
			+ (u3 - u2) * span * b.linear_velocity
	var qa := a.transform.basis.get_rotation_quaternion()
	var qb := b.transform.basis.get_rotation_quaternion()
	var scale := a.transform.basis.get_scale().lerp(b.transform.basis.get_scale(), u)
	out.transform.basis = Basis(qa.slerp(qb, u)) * Basis.from_scale(scale)
	out.linear_velocity = a.linear_velocity.lerp(b.linear_velocity, u)
	out.angular_velocity = a.angular_velocity.lerp(b.angular_velocity, u)
	return out
