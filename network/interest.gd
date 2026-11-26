class_name Interest
extends RefCounted
## Server: which ships each client is told about (netcode slice N5, interest
## management). No nodes or networking: Galaxy says where each client and each
## ship is, and asks who knows what.
##
## A client is only sent what it should know: snapshots go only for ships it
## knows (N5a1), and a ship it doesn't know doesn't exist on it at all (N5a2,
## spawn and despawn). That saves bandwidth, and is what fog of war needs: a
## client that is never told about a ship can't show it, even if modified.
##
## A ship a client stops knowing leaves in two steps. First it is "leaving":
## snapshots and the ship's unreliable syncs stop ([method knows] is false), but
## the client still has it ([method holds]). One update later it is despawned.
## In between, anything sent just before has arrived: unreliable packets can
## overtake the reliable despawn, and would find no ship.
##
## The rule for now: a client knows the ships in its player's system, and a
## client without a character knows none (the join menu asks the server for
## spawn points, N5b2). Fog of war will replace it with the sensor picture of
## the player's faction (see the fog-of-war design: signatures, sensors, sharing).

var _known: Dictionary = {}  # Peer -> {ship: true}.
var _leaving: Dictionary = {}  # Peer -> {ship: true}: still on the client, going.


## Works out who knows what now. [param peers]: each connected client's peer id
## and the system its player is in (null without a character). [param ships]:
## each ship and its system. Returns, for each peer whose ships changed:
## {peer: {"shown": [...], "leaving": [...], "hidden": [...]}}: ships it knows
## now (new, or back while leaving), ships it stopped knowing (still on the
## client), and ships to despawn there.
func update(peers: Dictionary, ships: Dictionary) -> Dictionary:
	var changes := {}
	for peer in _known.keys():
		if not peers.has(peer):
			_known.erase(peer)
			_leaving.erase(peer)
	for peer in peers:
		var wanted := _wanted(peers[peer], ships)
		var known: Dictionary = _known.get(peer, {})
		var was_leaving: Dictionary = _leaving.get(peer, {})
		var shown := wanted.keys().filter(func(s: Object) -> bool: return not known.has(s))
		var leaving := {}
		for ship in known:
			if not wanted.has(ship) and ships.has(ship):
				leaving[ship] = true
		# Gone from the world (freed) goes at once: there is nothing left to hold.
		var hidden := known.keys().filter(func(s: Object) -> bool: return not ships.has(s))
		for ship in was_leaving:
			if not wanted.has(ship):
				hidden.append(ship)
		if shown or leaving or hidden:
			changes[peer] = {"shown": shown, "leaving": leaving.keys(), "hidden": hidden}
		_known[peer] = wanted
		_leaving[peer] = leaving
	return changes


## True when [param peer] is told about [param ship]: it gets its snapshots.
func knows(peer: int, ship: Object) -> bool:
	return _known.has(peer) and (_known[peer] as Dictionary).has(ship)


## True while [param ship] exists on [param peer]'s client: known, or leaving.
func holds(peer: int, ship: Object) -> bool:
	return knows(peer, ship) or (_leaving.has(peer) and (_leaving[peer] as Dictionary).has(ship))


## The peers known, in the order first seen.
func peers() -> Array:
	return _known.keys()


## The ships a client in [param system] (null: no character yet) should know.
func _wanted(system: Object, ships: Dictionary) -> Dictionary:
	var out := {}
	if system == null:
		return out
	for ship in ships:
		if ships[ship] == system:
			out[ship] = true
	return out
