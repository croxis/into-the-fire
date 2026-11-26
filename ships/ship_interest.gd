class_name ShipInterest
extends RefCounted
## Server: which clients one ship exists on and is synced to (interest
## management, netcode N5a2). Each Ship owns one (Ship.interest); the world's
## Interest (Galaxy.interest) decides, this applies it to the ship's nodes.
##
## Godot spawns a node on a peer while the synchronizers rooted at that node are
## visible to it, and sends each synchronizer's data only to peers it is visible
## to, so every one in the ship, its helms' and its crew's too, gets a filter.
## Two kinds, for the two steps of leaving (see Interest): the ship's own and
## its crew's keep them spawned while the client still holds the ship; the rest
## (helms, Babylon 5's rotation) stop as soon as it stops knowing it, along with
## the snapshots.

## Who knows this ship, instead of Galaxy.interest (unit tests).
var override: Interest
## Clients that confirmed they have this ship (Ship._have_ship, sent from its
## _ready there): they get its snapshots and the syncs that aren't part of the
## spawn.
var confirmed: Dictionary[int, bool] = {}
## Synchronizers given a filter, and whether it is the "held" one (true: they
## keep a node spawned) or the "known" one.
var filtered: Dictionary[MultiplayerSynchronizer, bool] = {}

var _ship: Ship


func _init(ship: Ship) -> void:
	_ship = ship


## Gives every synchronizer under [param node] (the ship, or a crew member as
## it boards) its filter, once each. Their visibility is then updated only when
## Interest changes (update), not every frame.
func follow(node: Node) -> void:
	var syncs := node.find_children("*", "MultiplayerSynchronizer", true, false)
	if node is MultiplayerSynchronizer:
		syncs.append(node)
	for sync: MultiplayerSynchronizer in syncs:
		if filtered.has(sync):
			continue
		var root := sync.get_node_or_null(sync.root_path)
		var held := root == _ship or root is Character
		filtered[sync] = held
		sync.add_visibility_filter(is_held_by if held else is_known_to)
		sync.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE


## Whether client [param peer] is told about this ship and has confirmed it has
## it. Unreliable, its snapshots and other syncs would overtake the spawn itself.
func is_known_to(peer: int) -> bool:
	var s := source()
	return confirmed.has(peer) and (s == null or s.knows(peer, _ship))


## Whether this ship exists on client [param peer]'s machine (known, or
## leaving).
func is_held_by(peer: int) -> bool:
	var s := source()
	return s == null or s.holds(peer, _ship)


## The Interest that decides, or null for a ship on its own (tools): then every
## client knows it.
func source() -> Interest:
	if override:
		return override
	var g := _ship.galaxy if _ship.galaxy else Galaxy.find_for(_ship)
	return g.interest if g else null


## [param peer] has this ship now (Ship._have_ship).
func confirm(peer: int) -> void:
	confirmed[peer] = true


## The ship was despawned on [param peer]'s client, or it left.
func forget(peer: int) -> void:
	confirmed.erase(peer)


## The ship's synchronizers in the order to update them when a client starts
## ([param shown]) or stops knowing it: the ship's own first when shown, so it
## spawns before anything inside it, and last when hidden, after its crew have
## despawned (a client must never hold crew without their ship).
func synchronizers_in_order(shown: bool) -> Array[MultiplayerSynchronizer]:
	var root: MultiplayerSynchronizer = _ship.get_node("MultiplayerSynchronizer")
	var crew_node := _ship.get_node_or_null("Crew")
	var crew: Array[MultiplayerSynchronizer] = []
	var others: Array[MultiplayerSynchronizer] = []
	for sync: MultiplayerSynchronizer in _ship.find_children("*", "MultiplayerSynchronizer", true, false):
		if sync == root:
			continue
		if crew_node and crew_node.is_ancestor_of(sync):
			crew.append(sync)
		else:
			others.append(sync)
	var out: Array[MultiplayerSynchronizer] = []
	if shown:
		out.append(root)
		out.append_array(others)
		out.append_array(crew)
	else:
		out.append_array(crew)
		out.append_array(others)
		out.append(root)
	return out


## [param peer] now knows this ship, or no longer does ([param shown]); Godot
## spawns or despawns it there and starts or stops syncing. When it is
## [param despawned] there, the client's next copy must confirm itself again.
func update(peer: int, shown: bool, despawned := false) -> void:
	if despawned:
		forget(peer)
	for sync in synchronizers_in_order(shown):
		sync.update_visibility(peer)
