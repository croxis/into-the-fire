class_name CommanderPatrol
extends RefCounted
## Server: a commander's patrol, without nodes of its own (the commander tree's
## tasks call these). From the threat to its ship, doctrine says how many
## fighters it wants out (wanted_fighters); it counts its side's fighters
## already out within the patrol radius (fighters_out) and keeps one patrol
## posting with enough slots for the rest (keep_patrol_posted).
##
## First pass: it only adds fighters. A posting never loses slots and is never
## cancelled, since nothing can recall a fighter until docking exists.


## How many fighters [param doctrine] wants out at [param threat].
static func wanted_fighters(doctrine: FactionDoctrine, threat: float) -> int:
	if doctrine == null:
		return 0
	return doctrine.minimum_patrol_fighters + ceili(threat * doctrine.fighters_per_threat)


## The fighters on [param anchor]'s side (its faction or a wing below it) out in
## its system within [param radius] metres of it: crewed ships that are
## neither stations nor capital ships.
static func fighters_out(anchor: Ship, radius: float) -> Array[Ship]:
	var out: Array[Ship] = []
	var system := System.find_for(anchor)
	var side := anchor.faction
	if system == null or side == null:
		return out
	for ship in system.get_ships():
		if ship == anchor or ship.is_queued_for_deletion() or ship.is_station or ship.is_capital:
			continue
		var f := ship.faction
		if f == null or not (f == side or f.is_a_parent(side)):
			continue
		if ship.global_position.distance_to(anchor.global_position) > radius:
			continue
		if _crew_ids(ship).is_empty():
			continue
		out.append(ship)
	return out


## Keeps one patrol posting by [param issuer_id] round [param anchor] with
## slots for [param wanted] fighters, less those out already that hold no
## claim on it. Posts it when it is needed and there is none; adds slots when
## more are wanted; never removes any. Returns the posting, or null when none
## is needed or posted.
static func keep_patrol_posted(board: ObjectiveBoard, issuer_id: int, anchor: Ship, wanted: int,
		radius: float) -> Objective:
	var posting := _posting_of(board, issuer_id, anchor)
	var unclaimed_out := 0
	for ship in fighters_out(anchor, radius):
		if posting == null or not _crew_ids(ship).any(func(id: int) -> bool: return id in posting.claims):
			unclaimed_out += 1
	var slots := wanted - unclaimed_out
	if posting == null:
		if slots <= 0:
			return null
		var system := System.find_for(anchor)
		posting = board.post(Objective.Type.PATROL, issuer_id, anchor.faction_id, slots, {
			"route": PatrolRoute.pick(anchor, radius),
			"anchor_ship_id": anchor.ship_id,
			"system": String(system.name) if system else "",
		}, "Patrol within %d km of %s" % [roundi(radius / 1000.0), anchor.name])
		Log.log([anchor.name, " posted ", posting, ": ", posting.description], Log.MessageType.INFO)
		return posting
	if slots > posting.slots:
		board.set_slots(posting.id, slots)
		Log.log([anchor.name, " wants more on patrol: ", posting], Log.MessageType.INFO)
	return posting


## The open or filled patrol [param issuer_id] posted round [param anchor].
static func _posting_of(board: ObjectiveBoard, issuer_id: int, anchor: Ship) -> Objective:
	for o in board.issued_by(issuer_id):
		if o.type == Objective.Type.PATROL and o.audience == Objective.Audience.POSTED \
				and o.params.get("anchor_ship_id") == anchor.ship_id:
			return o
	return null


static func _crew_ids(ship: Ship) -> Array[int]:
	var ids: Array[int] = []
	for c in ship.get_crew():
		if not c.is_queued_for_deletion():
			ids.append(c.pilot_id)
	return ids


## The character a commander tree runs for: [param agent] or the nearest
## node above it that is one (a console's BTPlayer sits inside its brain).
static func character_of(agent: Node) -> Character:
	var n := agent
	while n and not n is Character:
		n = n.get_parent()
	return n as Character
