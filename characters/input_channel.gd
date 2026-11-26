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
## The smallest cushion: inputs the server waits for before using them, and
## rebuilds after running dry. Packets arrive in clumps, not one per tick;
## without a cushion the server would often find no input and hold the last one
## for a step the client never made, and the pilot would see a correction each
## time. Two ticks (33 ms) the pilot doesn't feel: their client shows their
## input at once.
const JITTER_BUFFER := 2
## The largest cushion (133 ms). Past this, a link is too bad for more delay to help.
const MAX_CUSHION := 8
## Ticks (5 s) without running dry before the cushion may first shrink by one.
## Running dry soon after a shrink doubles the wait, up to MAX_SHRINK_AFTER
## (40 s): otherwise a link on the edge would bounce between two sizes, paying a
## skip to shrink and a hold to grow back every few seconds.
const SHRINK_AFTER := 300
const MAX_SHRINK_AFTER := SHRINK_AFTER * 8
## More inputs waiting than the cushion plus this and the server skips the
## oldest, back to the cushion: a safety net, for a burst after a stall or a
## client not steering its lead, which would otherwise keep the server that many
## ticks behind the pilot for good. A smaller excess is the client's to drain,
## by easing off its lead (time dilation, InputLead): each skip is a correction.
const BACKLOG_SLACK := 8
const _VECTOR_FIELDS: Array[String] = ["throttle", "rotation_throttle"]
const _BOOL_FIELDS: Array[String] = ["autospin_toggle", "autobreak_toggle", "debug_all_stop"]
## One-shot presses that switch a setting: a dropped one is carried to the next
## input used (two cancel out), or the server would fly with the other setting
## for good while the pilot's client flies with theirs.
const _TOGGLE_FIELDS: Array[String] = ["autospin_toggle", "autobreak_toggle"]

## Server: the client tick of the last input handed out by next(), -1 before any.
var last_applied_tick := -1

var _recent: Array[Dictionary] = []  # Client: the latest records, oldest first.
var _queue: Dictionary[int, Dictionary] = {}  # Server: tick -> record.
var _last: Dictionary = make_record(-1, Vector3.ZERO, Vector3.ZERO)  # Server.
var _buffering := true  # Server: waiting for the cushion.
var _carried: Dictionary = {}  # Server: field -> true, presses from dropped inputs still to apply.
## Server: the cushion now, between JITTER_BUFFER and MAX_CUSHION. Each hold or
## skip is a one-tick jump on the pilot's screen, so a link that runs dry gets a
## tick more; a steady one gives it back, since every tick of cushion also shows
## the ship that much later to everyone else.
var cushion := JITTER_BUFFER
var _steady_ticks := 0  # Server: ticks since the cushion last changed.
var _fewest_queued := MAX_QUEUE  # Server: the lowest queue seen in that time.
## Server: steady ticks needed before shrinking, from SHRINK_AFTER up.
var shrink_after := SHRINK_AFTER
var _ticks_since_shrink := MAX_SHRINK_AFTER  # Server: any ticks, held or not.
## Server: ticks next() held the last input since started (no new input ready).
## Each one is a step the client didn't make, so a correction on their screen.
var held_ticks := 0
## Server: inputs skipped to catch up with a backlog. Also a correction each.
var skipped_ticks := 0


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
		_drop(_queue.keys().min())
	return ""


## Server: the input for this tick. With nothing new queued (or the cushion
## still filling), the last input holds (minus one-shot toggles) and
## last_applied_tick stays put.
func next() -> Dictionary:
	_ticks_since_shrink += 1
	if _queue.is_empty():
		if not _buffering:  # Ran dry: too small for this link.
			if _ticks_since_shrink < shrink_after:
				shrink_after = mini(shrink_after * 2, MAX_SHRINK_AFTER)
			_set_cushion(cushion + 1)
		_buffering = true
	elif _buffering and _queue.size() >= cushion:
		_buffering = false
	if _buffering:
		if last_applied_tick >= 0:
			held_ticks += 1
		var held := _last.duplicate()
		for field in _BOOL_FIELDS:
			held[field] = false
		return held
	_fewest_queued = mini(_fewest_queued, _queue.size())
	_steady_ticks += 1
	# Never below 2 in a while: one tick less cushion still wouldn't run dry. No
	# input is dropped to get there: the client's lead drains the queue down to
	# the new cushion (InputLead).
	if _steady_ticks >= shrink_after and cushion > JITTER_BUFFER and _fewest_queued >= 2:
		_set_cushion(cushion - 1)
		_ticks_since_shrink = 0
	elif _steady_ticks >= shrink_after:
		_set_cushion(cushion)  # Start a new window.
	var tick: int = _queue.keys().min()
	_last = _with_carried(_queue[tick])
	_queue.erase(tick)
	last_applied_tick = tick
	return _last


## Server, once per tick loop, after its ticks: skips a backlog over the cushion
## plus BACKLOG_SLACK, back to the cushion. Not in next(): a server that fell a
## little behind runs several ticks in one frame, with what arrived meanwhile
## already queued, and the first of them would take that for a backlog.
func trim_backlog() -> void:
	if _queue.size() > cushion + BACKLOG_SLACK:
		while _queue.size() > cushion + 1:
			_skip_oldest()


func _set_cushion(size: int) -> void:
	cushion = clampi(size, JITTER_BUFFER, MAX_CUSHION)
	_steady_ticks = 0
	_fewest_queued = MAX_QUEUE


func _skip_oldest() -> void:
	_drop(_queue.keys().min())
	skipped_ticks += 1


## Removes the input for [param tick] unused, keeping its presses for later.
func _drop(tick: int) -> void:
	var r: Dictionary = _queue[tick]
	for field in _TOGGLE_FIELDS:
		if r[field]:
			_carried[field] = not _carried.get(field, false)
	if r.debug_all_stop:
		_carried["debug_all_stop"] = true  # A stop, not a switch: once is enough.
	_queue.erase(tick)


## [param r] with the presses of dropped inputs added (a copy when any).
func _with_carried(r: Dictionary) -> Dictionary:
	if _carried.is_empty():
		return r
	var out := r.duplicate()
	for field in _TOGGLE_FIELDS:
		out[field] = out[field] != _carried.get(field, false)
	out.debug_all_stop = out.debug_all_stop or _carried.get("debug_all_stop", false)
	_carried.clear()
	return out


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
