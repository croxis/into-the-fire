class_name InputChannel
extends RefCounted
## A pilot's tick-stamped input, from their client to the server (netcode slice
## N3a, own-ship prediction). No nodes or networking here: Character sends the
## packets and feeds them in.
##
## Client side, record() stamps each tick's input and returns the packet to
## send: the newest REDUNDANCY inputs, so the unreliable channel can lose a
## packet or two without losing input. Server side, receive() checks a packet
## (it comes from a client, so anything at all) and queues new inputs by tick;
## next() hands out one input per server tick, in order. last_applied_tick is
## the client tick of the input the server used: the server sends it back with
## the ship's state, so the client knows which of its inputs to replay (N3b/c).

## Inputs per packet: this tick's and the three before it.
const REDUNDANCY := 4
## Queued inputs kept at most (about half a second); a flood drops the oldest.
const MAX_QUEUE := 30
const _VECTOR_FIELDS: Array[String] = ["throttle", "rotation_throttle"]
const _BOOL_FIELDS: Array[String] = ["autospin_toggle", "autobreak_toggle", "debug_all_stop"]

## Server: the client tick of the last input handed out by next(), -1 before any.
var last_applied_tick := -1

var _recent: Array[Dictionary] = []  # Client: the latest records, oldest first.
var _queue: Dictionary[int, Dictionary] = {}  # Server: tick -> record.
var _last: Dictionary = make_record(-1, Vector3.ZERO, Vector3.ZERO)  # Server.


static func make_record(tick: int, throttle: Vector3, rotation_throttle: Vector3,
		autospin_toggle := false, autobreak_toggle := false, debug_all_stop := false) -> Dictionary:
	return {
		"tick": tick,
		"throttle": throttle,
		"rotation_throttle": rotation_throttle,
		"autospin_toggle": autospin_toggle,
		"autobreak_toggle": autobreak_toggle,
		"debug_all_stop": debug_all_stop,
	}


## Client: remembers [param record] and returns the packet to send.
func record(input_record: Dictionary) -> Array:
	_recent.append(input_record)
	if _recent.size() > REDUNDANCY:
		_recent.pop_front()
	return _recent.duplicate()


## Server: why [param packet] was refused ("" when accepted). Inputs already
## applied or queued are skipped; out-of-range values are clamped.
func receive(packet: Variant) -> String:
	if not packet is Array:
		return "not a list"
	if packet.size() > REDUNDANCY:
		return "too many inputs"
	var checked: Array[Dictionary] = []
	for item in packet:
		var r := _check(item)
		if r.is_empty():
			return "malformed input"
		checked.append(r)
	for r in checked:
		if r.tick > last_applied_tick and not _queue.has(r.tick):
			_queue[r.tick] = r
	while _queue.size() > MAX_QUEUE:
		_queue.erase(_queue.keys().min())
	return ""


## Server: the input for this tick. With nothing new queued, the last input
## holds (minus one-shot toggles) and last_applied_tick stays put.
func next() -> Dictionary:
	if _queue.is_empty():
		var held := _last.duplicate()
		for field in _BOOL_FIELDS:
			held[field] = false
		return held
	var tick: int = _queue.keys().min()
	_last = _queue[tick]
	_queue.erase(tick)
	last_applied_tick = tick
	return _last


## Server: inputs waiting to be applied.
func queued() -> int:
	return _queue.size()


## A clean copy of [param item] if it is a well-formed input record, else {}.
static func _check(item: Variant) -> Dictionary:
	if not item is Dictionary or not item.get("tick") is int:
		return {}
	var r := make_record(item.tick, Vector3.ZERO, Vector3.ZERO)
	for field in _VECTOR_FIELDS:
		var v: Variant = item.get(field)
		if not v is Vector3 or not v.is_finite():
			return {}
		r[field] = v.clamp(-Vector3.ONE, Vector3.ONE)
	for field in _BOOL_FIELDS:
		if not item.get(field) is bool:
			return {}
		r[field] = item[field]
	return r
