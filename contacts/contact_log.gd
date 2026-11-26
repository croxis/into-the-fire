class_name ContactLog
extends RefCounted
## Client: the ships this player's side has lost contact with, and where to draw
## their ghosts (netcode slice N5c, fog of war). No nodes or networking: Galaxy
## records what the server says (lost, regained) and ghost markers ask it where
## to be and how faded.
##
## A ghost drifts on the ship's last known course (dead reckoning: the server
## doesn't say where it really is) and fades over fade_seconds. Stations and
## other immobile objects leave a permanent ghost where they were. A contact
## stays on record after its ghost fades, with when it was last seen, for the
## UI to come.

## How long a lost contact's ghost takes to fade out. A client setting (fleet
## management may set it later).
var fade_seconds := 30.0

var _tick_seconds: float
var _contacts := {}  # ship_id -> Dictionary.


func _init(tick_seconds: float) -> void:
	_tick_seconds = tick_seconds


## The server says contact with ship [param ship_id] was lost. [param data]:
## "name", "faction_id", "system" (name), "transform", "velocity", "immobile",
## and "tick", the server tick it was last seen at.
func lost(ship_id: int, data: Dictionary) -> void:
	var c := data.duplicate()
	c["last_seen_tick"] = data["tick"]
	c["in_contact"] = false
	_contacts[ship_id] = c


## Ship [param ship_id] is in contact again (it exists here once more): its
## ghost goes.
func regained(ship_id: int) -> void:
	if _contacts.has(ship_id):
		_contacts[ship_id]["in_contact"] = true


## The record for [param ship_id], or {} if this client never lost it.
func get_contact(ship_id: int) -> Dictionary:
	return _contacts.get(ship_id, {})


## Ships with a ghost to draw at server tick [param now].
func ghosts(now: float) -> Array[int]:
	var out: Array[int] = []
	for ship_id: int in _contacts:
		if ghost_alpha(ship_id, now) > 0.0:
			out.append(ship_id)
	return out


## Where [param ship_id]'s ghost is at server tick [param now]: carried on at
## its last velocity, or where it was for an immobile one.
func ghost_position(ship_id: int, now: float) -> Vector3:
	var c: Dictionary = _contacts[ship_id]
	var at: Vector3 = (c["transform"] as Transform3D).origin
	if c["immobile"]:
		return at
	return at + (c["velocity"] as Vector3) * (now - c["last_seen_tick"]) * _tick_seconds


## How visible [param ship_id]'s ghost is at server tick [param now]: 1 when
## just lost, 0 once faded (or in contact again); immobile ones stay at 1.
func ghost_alpha(ship_id: int, now: float) -> float:
	var c: Dictionary = _contacts.get(ship_id, {})
	if c.is_empty() or c["in_contact"]:
		return 0.0
	if c["immobile"]:
		return 1.0
	if fade_seconds <= 0.0:
		return 0.0
	var elapsed: float = (now - c["last_seen_tick"]) * _tick_seconds
	return clampf(1.0 - elapsed / fade_seconds, 0.0, 1.0)
