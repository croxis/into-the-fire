class_name Interest
extends RefCounted
## Server: which ships each client is told about (netcode slice N5, interest
## management). No nodes or networking: Galaxy says where each client and each
## ship is, and asks who knows what.
##
## A client is only sent what it should know: snapshots go only for ships it
## knows (N5a1), and later a ship it doesn't know won't exist on it at all
## (N5a2, spawn and despawn). That saves bandwidth, and is what fog of war needs:
## a client that is never told about a ship can't show it, even if modified.
##
## The rule for now: a client knows the ships in its player's system, and a
## client without a character yet knows the ships where it could spawn (the join
## menu lists them). Fog of war will replace it with the sensor picture of the
## player's faction (see the fog-of-war design: signatures, sensors, sharing).

var _known: Dictionary = {}  # Peer -> {ship: true}.


## Works out who knows what now. [param peers]: each connected client's peer id
## and the system its player is in (null without a character). [param ships]:
## each ship and its system. [param spawn_systems]: the systems a client without
## a character knows. Returns, for each peer whose ships changed, the ships it
## now knows and those it no longer does: {peer: {"shown": [...], "hidden": [...]}}.
func update(peers: Dictionary, ships: Dictionary, spawn_systems: Array) -> Dictionary:
	var changes := {}
	for peer in _known.keys():
		if not peers.has(peer):
			_known.erase(peer)
	for peer in peers:
		var wanted := _wanted(peers[peer], ships, spawn_systems)
		var before: Dictionary = _known.get(peer, {})
		var shown := wanted.keys().filter(func(s: Object) -> bool: return not before.has(s))
		var hidden := before.keys().filter(func(s: Object) -> bool: return not wanted.has(s))
		if shown or hidden:
			changes[peer] = {"shown": shown, "hidden": hidden}
		_known[peer] = wanted
	return changes


## True when [param peer] is told about [param ship].
func knows(peer: int, ship: Object) -> bool:
	return _known.has(peer) and (_known[peer] as Dictionary).has(ship)


## The peers known, in the order first seen.
func peers() -> Array:
	return _known.keys()


## The ships a client in [param system] (null: no character yet) should know.
func _wanted(system: Object, ships: Dictionary, spawn_systems: Array) -> Dictionary:
	var out := {}
	for ship in ships:
		var at: Object = ships[ship]
		var seen := at == system if system != null else at in spawn_systems
		if seen:
			out[ship] = true
	return out
