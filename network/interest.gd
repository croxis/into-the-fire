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
## The rule (fog of war, N5b3): a client knows the ships in its player's
## faction's sensor picture that are in the player's system, and the ship the
## player is aboard. A top-level faction's picture is its own ships and what
## their sensors detect (picture); every faction under it shares it. A client
## without a character knows none (the join menu asks the server for spawn
## points, N5b2). Still to come: ghosts of lost contacts, ships left out of the
## picture, and sharing pictures between factions.

var _known: Dictionary = {}  # Peer -> {ship: true}.
var _leaving: Dictionary = {}  # Peer -> {ship: true}: still on the client, going.
var _viewpoints := {}  # Peer -> the ship its player is aboard.


## What a client's player can know (view): [param system], the system they are
## in; [param aboard], the ship they are on (or null); [param picture], their
## faction's sensor picture, {ship: true}.
static func view(system: Object, aboard: Object, picture: Dictionary) -> Dictionary:
	return {"system": system, "aboard": aboard, "picture": picture}


## A faction's sensor picture: its [param own] ships and every ship they detect,
## [param detections] being {ship: [ships it detects]}. {ship: true}.
static func picture(own: Array, detections: Dictionary) -> Dictionary:
	var out := {}
	for ship in own:
		if not is_instance_valid(ship):
			continue
		out[ship] = true
		for seen in detections.get(ship, []):
			if is_instance_valid(seen):
				out[seen] = true
	return out


## Works out who knows what now. [param peers]: each connected client's peer id
## and its player's view (null without a character). [param ships]: each ship
## in the world and its system. Returns, for each peer whose ships changed:
## {peer: {"shown": [...], "leaving": [...], "hidden": [...]}}: ships it knows
## now (new, or back while leaving), ships it stopped knowing (still on the
## client), and ships to despawn there.
func update(peers: Dictionary, ships: Dictionary) -> Dictionary:
	var changes := {}
	for peer in _known.keys():
		if not peers.has(peer):
			_known.erase(peer)
			_leaving.erase(peer)
	_viewpoints.clear()
	for peer in peers:
		if peers[peer] != null and peers[peer]["aboard"] != null:
			_viewpoints[peer] = peers[peer]["aboard"]
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


## The ship [param peer]'s player is aboard, from the last update, or null:
## where distances to other ships are measured from (interest tiers).
func viewpoint(peer: int) -> Object:
	return _viewpoints.get(peer)


## True when [param peer] is told about [param ship]: it gets its snapshots.
func knows(peer: int, ship: Object) -> bool:
	return _known.has(peer) and (_known[peer] as Dictionary).has(ship)


## True while [param ship] exists on [param peer]'s client: known, or leaving.
func holds(peer: int, ship: Object) -> bool:
	return knows(peer, ship) or (_leaving.has(peer) and (_leaving[peer] as Dictionary).has(ship))


## The peers known, in the order first seen.
func peers() -> Array:
	return _known.keys()


## The ships a client with [param seen] (a view, or null: no character yet)
## should know, of [param ships].
func _wanted(seen: Variant, ships: Dictionary) -> Dictionary:
	var out := {}
	if seen == null:
		return out
	var picture: Dictionary = seen["picture"]
	for ship in picture:
		if ships.has(ship) and ships[ship] == seen["system"]:
			out[ship] = true
	var aboard: Object = seen["aboard"]
	if aboard != null and ships.has(aboard):
		out[aboard] = true
	return out
