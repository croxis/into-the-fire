class_name CrewOrders
extends RefCounted
## Server: crew taking orders, without nodes of its own (the crew and pilot
## trees' tasks call these). An idle NPC scores the open objectives it can do
## and claims the best (claim_best, utility); aboard a carrier with a patrol
## claimed it asks to launch, as a player would (launch_for_orders); at a
## fighter's helm it flies the patrol (fly_orders).
##
## First pass: PATROL only, for wing pilots. A character holds at most one
## claim; the ObjectiveBoard is where it is kept (by pilot ID), so it carries
## over when the pilot moves from carrier to fighter.

## How far away an objective may be before distance counts fully against it.
const FAR_KM := 50.0


## Whether [param character] has behaviour for [param objective].
static func can_do(character: Character, objective: Objective) -> bool:
	match objective.type:
		Objective.Type.PATROL:
			return character.faction != null and character.faction.is_wing
	return false


## The considerations an NPC weighs an objective by: nearer is better, and so
## is one with more of its slots still open.
static func considerations() -> Array[UtilityConsideration]:
	var near := UtilityConsideration.new()
	near.input = &"distance"
	near.curve = UtilityConsideration.falling(0.1)
	var open := UtilityConsideration.new()
	open.input = &"open_share"
	open.curve = UtilityConsideration.rising(0.5)
	open.weight = 0.5
	return [near, open]


## How much [param character] wants [param objective] (0..1; 0 when it can't).
static func score(character: Character, objective: Objective, galaxy: Galaxy) -> float:
	if not can_do(character, objective):
		return 0.0
	var inputs := {
		"distance": _distance_km(character, objective, galaxy) / FAR_KM,
		"open_share": float(objective.open_slots()) / maxf(1.0, objective.slots),
	}
	return UtilityScorer.score(considerations(), inputs)


## The objective [param character] has claimed, or claims now the best it can
## do (scored). Null when there is nothing for it.
static func claim_best(character: Character, galaxy: Galaxy) -> Objective:
	var board := galaxy.state.objectives
	var held := board.claimed_by(character.pilot_id)
	if not held.is_empty():
		return held[0]
	var best: Objective = null
	var best_score := 0.0
	var options: Array[Objective] = board.assigned_to(character.pilot_id)
	if character.faction:
		options.append_array(board.open_for(character.faction, galaxy.factions))
	for o in options:
		var s := score(character, o, galaxy)
		if s > best_score:
			best = o
			best_score = s
	if best == null:
		return null
	var refusal := board.claim(best.id, character.pilot_id, character.faction, galaxy.factions)
	if refusal:
		Log.log([character.name, " could not claim ", best, ": ", refusal], Log.MessageType.WARNING)
		return null
	Log.log([character.name, " took ", best, ": ", best.description], Log.MessageType.INFO)
	return best


## Aboard a carrier, with a claimed patrol: launch in a fighter (ShipLaunch,
## the same path as a player's). Returns why not ("" when launched).
static func launch_for_orders(character: Character, galaxy: Galaxy) -> String:
	var held := galaxy.state.objectives.claimed_by(character.pilot_id)
	if held.is_empty() or held[0].type != Objective.Type.PATROL:
		return "no patrol to fly"
	var carrier := character.current_ship
	if carrier == null or character.current_console != null:
		return "not a passenger"
	return ShipLaunch.launch(carrier, character, galaxy.ids)


## At a helm, with a claimed patrol: hand its route to the AI pilot, round the
## anchor ship (once; again only for a different objective). True when it is
## flying one.
static func fly_orders(character: Character, galaxy: Galaxy) -> bool:
	var held := galaxy.state.objectives.claimed_by(character.pilot_id)
	if held.is_empty() or held[0].type != Objective.Type.PATROL:
		return false
	var patrol := held[0]
	if character.get_meta(&"flying_objective", 0) == patrol.id and character.ai_pilot.has_orders():
		return true
	var anchor := _ship_by_id(galaxy, patrol.params.get("system", ""), patrol.params.get("anchor_ship_id", 0))
	if anchor == null:
		return false
	var route: Array[Vector3] = []
	route.assign(patrol.params.get("route", []))
	if route.is_empty():
		return false
	character.ai_pilot.follow(route, true, anchor)
	character.set_meta(&"flying_objective", patrol.id)
	Log.log([character.name, " flying ", patrol, " round ", anchor.name], Log.MessageType.INFO)
	return true


static func _distance_km(character: Character, objective: Objective, galaxy: Galaxy) -> float:
	var anchor := _ship_by_id(galaxy, objective.params.get("system", ""), objective.params.get("anchor_ship_id", 0))
	var here := character.current_ship
	if anchor == null or here == null:
		return FAR_KM
	if System.find_for(anchor) != System.find_for(here):
		return FAR_KM  # Another system: far, for now.
	return here.global_position.distance_to(anchor.global_position) / 1000.0


static func _ship_by_id(galaxy: Galaxy, system_name: String, ship_id: int) -> Ship:
	var system := galaxy.zones.get_system(system_name)
	if system == null:
		return null
	for s in system.get_ships():
		if s.ship_id == ship_id and not s.is_queued_for_deletion():
			return s
	return null
