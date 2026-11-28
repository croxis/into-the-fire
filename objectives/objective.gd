class_name Objective
extends RefCounted
## One order passed down from an issuer (a commander, NPC or player) to the
## characters below it: posted, with slots any eligible character may claim,
## or assigned to one character. Plain data (IDs, not nodes), so saves can keep
## it and it can be sent to clients. Changed only through its ObjectiveBoard.
##
## General objectives (capture a system, maximise trade) and specific ones (buy
## 50 food here, fly this route) are the same record; what differs is the type
## and whether any NPC has behaviour for it. First pass: PATROL only.

enum Type {
	CAPTURE,
	COLLECT,
	CUSTOM,
	DEFEND,
	DESTROY,
	DISABLE,
	DOCK,
	EXPLORE,
	FORMATION_CHANGE,
	LAUNCH,
	PATROL,
	REACH_LOCATION,
	REPAIR,
	RETREAT,
	TRADE,
}

## Who it is for: any eligible character (POSTED) or one character (ASSIGNED).
enum Audience { POSTED, ASSIGNED }

## OPEN: slots to claim. FILLED: every slot claimed, being carried out.
## COMPLETED, CANCELLED, EXPIRED: over, takes no claims.
enum State { OPEN, FILLED, COMPLETED, CANCELLED, EXPIRED }

var id := 0
var type := Type.CUSTOM
var description := ""
## Pilot ID of the issuer; 0 when the world itself issues it (a scenario).
var issuer_id := 0
## The side it belongs to. A posting is open to this faction and the factions
## below it (its wings), never to the sides above it.
var faction_id := FactionRegistry.NO_FACTION
var audience := Audience.POSTED
## ASSIGNED: the one pilot it is for.
var assignee_id := 0
## How many characters it wants (an assignment has 1).
var slots := 1
## Pilot IDs that have claimed it, in claim order.
var claims: Array[int] = []
## What to do, by type: PATROL has "route" (Array of Vector3, relative to the
## ship "anchor_ship_id" in its frame without scale: PatrolRoute.from_anchor)
## and "system" (the system's name).
var params := {}
var state := State.OPEN
## The server tick it expires at; 0 for never.
var expires_tick := 0


## True when it is over and takes no more claims.
func is_closed() -> bool:
	return state in [State.COMPLETED, State.CANCELLED, State.EXPIRED]


func open_slots() -> int:
	return maxi(0, slots - claims.size())


func _to_string() -> String:
	return "Objective %d (%s, %s, %d/%d)" % [id, Type.keys()[type], State.keys()[state],
			claims.size(), slots]
