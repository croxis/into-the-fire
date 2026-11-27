class_name FogOfWar
extends RefCounted
## Fog of war for one Galaxy (netcode N5b3, N5c; see network/CLAUDE.md). Each
## Galaxy owns one (Galaxy.fog). Server: works out what each client's player
## may know from their side's sensor pictures, and has Interest (Galaxy.interest)
## and each ship's ShipInterest spawn or despawn ships to match. Client: keeps
## the ghosts of lost contacts (Galaxy.contacts). The RPC itself,
## Galaxy._contact_lost, stays on the Galaxy: Godot routes RPCs by node path.

## Seconds between refreshes, besides the ones a change asks for.
const REFRESH_SECONDS := 0.5

var _galaxy: Galaxy
var _timer := 0.0


func _init(galaxy: Galaxy) -> void:
	_galaxy = galaxy


## Server, each frame: refresh every REFRESH_SECONDS.
func process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0:
		_timer = REFRESH_SECONDS
		refresh()


## Server: works out again which ships each client knows (Interest), from where
## each client's player and each ship is now. Runs every REFRESH_SECONDS, and
## at once when that changes: a client connects, a ship is launched (once it is
## in place: a ship's spawn goes with its place at that moment), a crew member
## boards (before any RPC to them: Godot refuses an RPC to a peer that can't
## see the node).
func refresh() -> void:
	var g := _galaxy
	var interest := g.interest
	var ships := {}
	for system in g.systems():
		for ship in system.get_ships():
			ships[ship] = system
	var peers := {}
	var pictures := {}  # One per top-level faction this refresh.
	for peer in g.multiplayer.get_peers():
		var player: Player = g.get_node("Players").find_player_by_netid(peer)
		var character := Galaxy.find_player_character(g.get_node("Systems"), player.player_id) \
				if player else null
		peers[peer] = view_of(character, pictures) if character else null
	var changes := interest.update(peers, ships)
	# Spawn or despawn on each client (N5a2). A leaving ship stops its unreliable
	# syncs now and is despawned at the next refresh (see Interest).
	for peer in changes:
		# Lost contact (still in the world, no longer known): the client leaves a
		# ghost where it was last seen (N5c). Freed ones go as "hidden" only.
		for ship: Ship in changes[peer]["leaving"]:
			g._contact_lost.rpc_id(peer, ship.ship_id, contact_data(ship, NetworkTime.tick))
		for key in ["leaving", "hidden"]:
			for ship in changes[peer][key]:  # Untyped: a hidden one may have been freed.
				if is_instance_valid(ship) and (ship as Ship).is_inside_tree():
					(ship as Ship).interest.update(peer, false, key == "hidden")
		for ship: Ship in changes[peer]["shown"]:
			ship.interest.update(peer, true)
	for peer in changes:
		Log.log(["Interest: peer ", peer, " now knows ", ships.keys().filter(
				func(s: Ship) -> bool: return interest.knows(peer, s)).size(), " ships (",
				changes[peer]["shown"].size(), " more, ", changes[peer]["leaving"].size(), " leaving, ",
				changes[peer]["hidden"].size(), " gone)"],
				Log.MessageType.INFO)
	g.interest_refreshed.emit()


## Server: what a client is told about [param ship] when its side loses contact
## (N5c), as last seen at server tick [param tick]. Stations are immobile: their
## ghosts don't drift or fade.
static func contact_data(ship: Ship, tick: int) -> Dictionary:
	var system := System.find_for(ship)
	return {
		"name": String(ship.name), "faction_id": ship.faction_id,
		"system": String(system.name) if system else "",
		"transform": ship.global_transform, "velocity": ship.linear_velocity,
		"immobile": ship.is_station, "tick": tick,
	}


## Client: what Galaxy._contact_lost brought: this player's side lost contact
## with [param ship_id] (it is about to be despawned here). Record it and put a
## ghost where it was.
func lost(ship_id: int, data: Dictionary) -> void:
	var g := _galaxy
	g.contacts.lost(ship_id, data)
	var system := g.get_node_or_null(NodePath("Systems/" + String(data.get("system", ""))))
	if not system is System:
		return
	var marker := GhostMarker.new()
	var clock := g.snapshot_clock
	marker.setup(g.contacts, ship_id, func() -> float:
			return clock.server_tick(SnapshotClock.local_now()))
	(system as System).add_ghost(marker)
	Log.log(["Lost contact with ", data.get("name", ship_id)], Log.MessageType.INFO)


## Client: ship [param ship_id] exists here again (Ship._ready): contact regained.
func regained(ship_id: int) -> void:
	var contacts := _galaxy.contacts
	if contacts.get_contact(ship_id).is_empty() or contacts.get_contact(ship_id)["in_contact"]:
		return
	contacts.regained(ship_id)
	Log.log(["Contact regained with ", contacts.get_contact(ship_id)["name"]], Log.MessageType.INFO)


## Server: what [param character]'s player may know (Interest.view): their
## system, the ship they are aboard, and their side's sensor picture (fog of
## war, N5b3): the top-level faction's shared picture, the pictures of excluded
## factions they belong to (one-way: covert wings see the shared one too), and
## what the ship they are aboard detects. [param pictures] caches pictures by
## top-level faction across one refresh.
func view_of(character: Character, pictures := {}) -> Dictionary:
	var faction := character.faction
	var top := faction.top_faction if faction else null
	var picture := {}
	if top:
		if not pictures.has(top):
			pictures[top] = pictures_of(top)
		var side: Dictionary = pictures[top]
		picture = (side["shared"] as Dictionary).duplicate()
		var f := faction
		while f:
			if side["groups"].has(f):
				picture.merge(side["groups"][f])
			f = f.parent_faction
	var aboard := character.current_ship
	if aboard:
		picture.merge(Interest.picture([aboard], {aboard: aboard.detected_ships}))
	return Interest.view(System.find_for(character), aboard, picture)


## Server: [param top]'s sensor pictures: "shared", every ship of its own (its
## factions all keep their ships on the top-level one) and what their sensors
## detect (Ship.detected_ships, from each system's sensor scan); and "groups",
## {excluded faction: picture} for the ships of each faction kept out of the
## shared one (its nearest excluded faction). Ships excluded on their own are in
## none: only their crew know them. TODO: sharing with other sides.
static func pictures_of(top: Faction) -> Dictionary:
	var shared: Array = []
	var groups := {}  # Excluded faction -> its ships.
	var detections := {}
	for ship in top.owned_ships:  # Untyped: a destroyed ship may be listed until freed.
		if not is_instance_valid(ship) or (ship as Ship).excluded_from_picture:
			continue
		detections[ship] = (ship as Ship).detected_ships
		var group := _excluded_group((ship as Ship).faction, top)
		if group:
			if not groups.has(group):
				groups[group] = []
			groups[group].append(ship)
		else:
			shared.append(ship)
	var out := {"shared": Interest.picture(shared, detections), "groups": {}}
	for group in groups:
		out["groups"][group] = Interest.picture(groups[group], detections)
	return out


## The nearest faction from [param faction] up to (not including) [param top]
## that is excluded from the shared picture, or null.
static func _excluded_group(faction: Faction, top: Faction) -> Faction:
	var f := faction
	while f and f != top:
		if f.excluded_from_picture:
			return f
		f = f.parent_faction
	return null


## Why [param requester] may not change whether [param target] (a Ship or a
## Faction) is kept out of its side's shared picture, or "": only the leader of
## the faction that owns the ship (for a faction: that faction), or of a
## faction above it, may. Nothing a client sends is trusted: call this first.
static func check_exclusion_change(requester: Character, target: Object) -> String:
	var faction: Faction = null
	if target is Ship:
		faction = (target as Ship).faction
	elif target is Faction:
		faction = target
	if faction == null:
		return "no faction owns that"
	var f := faction
	while f:
		if f.leader_id != 0 and f.leader_id == requester.pilot_id:
			return ""
		f = f.parent_faction
	return "%s doesn't lead %s or a faction above it" % [requester.name, faction.resource_name]
