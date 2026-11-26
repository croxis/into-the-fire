class_name SnapshotClock
extends RefCounted
## A client's estimate of the server's tick, from when snapshots arrive, and the
## moment remote ships are drawn at (netcode slice N4c). No nodes or networking.
##
## A client's netfox tick doesn't match the server's (it ran about the latency
## behind in tests), so we measure the gap ourselves: each snapshot says which
## server tick it is from, and [method observe] notes it against this client's
## tick when it arrives. That gap is the newest server tick we can have by now,
## not the server's tick this instant (a snapshot is a one-way trip old): it is
## exactly what drawing needs. Arrival times jitter, so the gap is averaged.
##
## Remote ships are drawn [constant DELAY_TICKS] behind it, so the snapshots on
## both sides of the drawn moment have usually arrived and SnapshotBuffer can
## follow the curve between them; a lost or late one is covered by extrapolating.
## The local time passed in must be steady and measured the same way in both
## calls, so any constant offset cancels out: Ship uses real time in ticks, not
## the netfox tick, which netfox speeds up and slows down to match the server.

## How far behind the newest snapshot ships are drawn: 100 ms. Covers the
## 2 ticks between snapshots, arrival jitter and one lost snapshot.
const DELAY_TICKS := 6.0
## How much of each new measurement goes into the average. Small, so jitter
## barely moves the drawn moment; it never moves it backwards (ticks advance
## 2 per snapshot, the average a few hundredths).
const SMOOTHING := 0.05
## A measurement this far off the average is a new clock, not jitter (netfox
## recalibrated this client's tick, or the connection stalled): start again.
const RESET_TICKS := 30.0

var _offset := 0.0  # Server tick minus local tick.
var _has_estimate := false


## This machine's steady clock in ticks (real time, not the netfox tick, which
## netfox speeds up and slows down): what [method observe] and
## [method render_tick] expect.
static func local_now() -> float:
	return Time.get_ticks_usec() / 1e6 / NetworkTime.ticktime


## A snapshot from server tick [param server_tick] arrived at [param local_now]
## (this machine's steady clock, in ticks).
func observe(server_tick: int, local_now: float) -> void:
	var measured := server_tick - local_now
	if not _has_estimate or absf(measured - _offset) > RESET_TICKS:
		_offset = measured
		_has_estimate = true
	else:
		_offset += (measured - _offset) * SMOOTHING


func has_estimate() -> bool:
	return _has_estimate


## The newest server tick this client can have heard of at [param local_now].
func server_tick(local_now: float) -> float:
	return local_now + _offset


## The server tick remote ships are drawn at, at [param local_now].
func render_tick(local_now: float) -> float:
	return server_tick(local_now) - DELAY_TICKS
