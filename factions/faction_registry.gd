class_name FactionRegistry
extends RefCounted
## All factions in one game world, and the IDs that identify them.
##
## Galaxy owns one registry per world ([member Galaxy.factions]). Only the server
## creates or changes factions; clients get a copy through [method to_data] and
## [method from_data]. Because it is a plain object, a new game or a loaded save
## replaces the whole set at once, and each unit test can make its own.
##
## ID 0 means "no faction" and is never assigned, so an unset faction_id (which
## defaults to 0) can't silently put a ship or character into a real faction.

const NO_FACTION := 0

## id (int) -> Faction
var _factions := {}
var _next_id := 1


## Creates a faction with the next free ID.
func create(faction_name: String, is_wing := false, accept_players := false,
		accept_children := false, parent: Faction = null) -> Faction:
	var f := Faction.new()
	f.resource_name = faction_name
	f.is_wing = is_wing
	f.accept_players = accept_players
	f.accept_children = accept_children
	f.parent_faction = parent
	f.active = true
	_add(f, _next_id)
	Log.log(["Faction created:", f.faction_id, faction_name], Log.MessageType.INFO)
	return f


## The faction with [param id], or null for [constant NO_FACTION] or an unknown ID.
func get_by_id(id: int) -> Faction:
	return _factions.get(id)


## The first faction named [param faction_name], or null.
func find_by_name(faction_name: String) -> Faction:
	for f: Faction in _factions.values():
		if f.resource_name == faction_name:
			return f
	return null


func has_id(id: int) -> bool:
	return _factions.has(id)


func size() -> int:
	return _factions.size()


## All factions, in ID order.
func all() -> Array[Faction]:
	var result: Array[Faction] = []
	var ids := _factions.keys()
	ids.sort()
	for id in ids:
		result.append(_factions[id])
	return result


## Factions with no parent, in ID order.
func top_level() -> Array[Faction]:
	return all().filter(func(f: Faction) -> bool: return f.parent_faction == null)


## Direct children of [param parent], in ID order.
func children_of(parent: Faction) -> Array[Faction]:
	return all().filter(func(f: Faction) -> bool: return f.parent_faction == parent)


## Plain data describing every faction, safe to send over the network or save.
##
## Doctrine is left out: it is AI configuration that only the server uses.
## Server-only runtime lists (owned and detected ships) are left out too.
func to_data() -> Dictionary:
	var list: Array[Dictionary] = []
	for f in all():
		list.append({
			"id": f.faction_id,
			"name": f.resource_name,
			"parent_id": f.parent_faction.faction_id if f.parent_faction else NO_FACTION,
			"is_wing": f.is_wing,
			"accept_players": f.accept_players,
			"accept_children": f.accept_children,
			"active": f.active,
			"leader_id": f.leader_id,
			"member_ids": f.member_ids.duplicate(),
			"relations": f.relations.duplicate(),
		})
	return {"next_id": _next_id, "factions": list}


## Builds a registry from [method to_data] output. IDs are kept as they were.
static func from_data(data: Dictionary) -> FactionRegistry:
	var registry := FactionRegistry.new()
	var list: Array = data.get("factions", [])
	# Two passes, so a parent listed after its child still links up.
	for entry: Dictionary in list:
		var f := Faction.new()
		f.resource_name = entry.get("name", "")
		f.is_wing = entry.get("is_wing", false)
		f.accept_players = entry.get("accept_players", false)
		f.accept_children = entry.get("accept_children", false)
		f.active = entry.get("active", true)
		f.leader_id = entry.get("leader_id", 0)
		f.member_ids.assign(entry.get("member_ids", []))
		f.relations = entry.get("relations", {}).duplicate()
		registry._add(f, entry["id"])
	for entry: Dictionary in list:
		var parent_id: int = entry.get("parent_id", NO_FACTION)
		if parent_id != NO_FACTION:
			registry.get_by_id(entry["id"]).parent_faction = registry.get_by_id(parent_id)
	# Never hand out an ID that is already taken, whatever next_id says.
	var highest := 0
	for id: int in registry._factions:
		highest = maxi(highest, id)
	registry._next_id = maxi(int(data.get("next_id", 1)), highest + 1)
	return registry


func _add(f: Faction, id: int) -> void:
	f.faction_id = id
	f.registry = weakref(self)
	_factions[id] = f
	_next_id = maxi(_next_id, id + 1)
