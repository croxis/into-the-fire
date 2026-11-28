class_name ObjectiveBoard
extends RefCounted
## Server: a world's objectives, how orders pass down a chain of command.
## Issuers post objectives (slots any eligible character may claim; filled
## once every slot is claimed) or assign them to one character. Characters
## claim, release, and the issuer completes or cancels. Part of WorldState, so
## saves keep it; it knows pilots and factions by ID only and needs no nodes.
##
## Every claim is checked here: when players can claim (they will send an
## objective ID), nothing they send is trusted.

## Emitted whenever [param objective] is posted, assigned or changes state or
## claims.
signal changed(objective: Objective)

## Where objective IDs come from (WorldState keeps this the world's own).
var ids: WorldIds

var _objectives := {}  # id -> Objective, in creation order.


func _init(world_ids: WorldIds) -> void:
	ids = world_ids


## Posts an objective with [param slots] for any character on
## [param faction_id]'s side, or a side below it, to claim.
func post(type: Objective.Type, issuer_id: int, faction_id: int, slots: int, params: Dictionary,
		description: String) -> Objective:
	var o := _make(type, issuer_id, faction_id, params, description)
	o.audience = Objective.Audience.POSTED
	o.slots = maxi(1, slots)
	return _add(o)


## Gives an objective to the one character [param assignee_id].
func assign(type: Objective.Type, issuer_id: int, assignee_id: int, faction_id: int,
		params: Dictionary, description: String) -> Objective:
	var o := _make(type, issuer_id, faction_id, params, description)
	o.audience = Objective.Audience.ASSIGNED
	o.assignee_id = assignee_id
	o.slots = 1
	return _add(o)


func get_objective(id: int) -> Objective:
	return _objectives.get(id)


func size() -> int:
	return _objectives.size()


## Why [param pilot_id], whose faction is [param pilot_faction], may not claim
## objective [param id], or "" when the claim is made.
func claim(id: int, pilot_id: int, pilot_faction: Faction, registry: FactionRegistry) -> String:
	var o := get_objective(id)
	if o == null:
		return "no objective %d" % id
	if o.is_closed():
		return "objective %d is %s" % [id, Objective.State.keys()[o.state].to_lower()]
	if pilot_id in o.claims:
		return "already claimed"
	if o.audience == Objective.Audience.ASSIGNED:
		if pilot_id != o.assignee_id:
			return "assigned to someone else"
	elif not _in_scope(o, pilot_faction, registry):
		return "not for that side"
	if o.open_slots() == 0:
		return "no slot left"
	o.claims.append(pilot_id)
	_update_state(o)
	changed.emit(o)
	return ""


## [param pilot_id] gives up objective [param id] (or can no longer do it:
## dead, logged out). A filled posting opens again.
func release(id: int, pilot_id: int) -> void:
	var o := get_objective(id)
	if o == null or not pilot_id in o.claims:
		return
	o.claims.erase(pilot_id)
	_update_state(o)
	changed.emit(o)


## Releases everything [param pilot_id] has claimed.
func release_all(pilot_id: int) -> void:
	for o in claimed_by(pilot_id):
		release(o.id, pilot_id)


func complete(id: int) -> void:
	_close(id, Objective.State.COMPLETED)


func cancel(id: int) -> void:
	_close(id, Objective.State.CANCELLED)


## Expires every objective whose expires_tick has come by [param tick].
func expire(tick: int) -> void:
	for o: Objective in _objectives.values():
		if o.expires_tick > 0 and tick >= o.expires_tick and not o.is_closed():
			_close(o.id, Objective.State.EXPIRED)


## The postings a character on [param faction]'s side could claim now.
func open_for(faction: Faction, registry: FactionRegistry) -> Array[Objective]:
	var out: Array[Objective] = []
	for o: Objective in _objectives.values():
		if o.audience == Objective.Audience.POSTED and o.state == Objective.State.OPEN \
				and _in_scope(o, faction, registry):
			out.append(o)
	return out


## The objectives assigned to [param pilot_id] that are not over.
func assigned_to(pilot_id: int) -> Array[Objective]:
	return _where(func(o: Objective) -> bool:
			return o.audience == Objective.Audience.ASSIGNED and o.assignee_id == pilot_id \
				and not o.is_closed())


## The objectives [param pilot_id] has claimed that are not over.
func claimed_by(pilot_id: int) -> Array[Objective]:
	return _where(func(o: Objective) -> bool: return pilot_id in o.claims and not o.is_closed())


## The objectives [param issuer_id] issued that are not over.
func issued_by(issuer_id: int) -> Array[Objective]:
	return _where(func(o: Objective) -> bool: return o.issuer_id == issuer_id and not o.is_closed())


func _make(type: Objective.Type, issuer_id: int, faction_id: int, params: Dictionary,
		description: String) -> Objective:
	var o := Objective.new()
	o.id = ids.next_objective()
	o.type = type
	o.issuer_id = issuer_id
	o.faction_id = faction_id
	o.params = params.duplicate(true)
	o.description = description
	return o


func _add(o: Objective) -> Objective:
	_objectives[o.id] = o
	changed.emit(o)
	return o


func _close(id: int, state: Objective.State) -> void:
	var o := get_objective(id)
	if o == null or o.is_closed():
		return
	o.state = state
	changed.emit(o)


static func _update_state(o: Objective) -> void:
	o.state = Objective.State.FILLED if o.open_slots() == 0 else Objective.State.OPEN


## Whether [param faction] is the objective's side or below it.
static func _in_scope(o: Objective, faction: Faction, registry: FactionRegistry) -> bool:
	var side := registry.get_by_id(o.faction_id)
	return faction != null and side != null and (faction == side or faction.is_a_parent(side))


func _where(test: Callable) -> Array[Objective]:
	var out: Array[Objective] = []
	for o: Objective in _objectives.values():
		if test.call(o):
			out.append(o)
	return out
