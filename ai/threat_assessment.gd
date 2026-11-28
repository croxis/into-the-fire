class_name ThreatAssessment
extends RefCounted
## How threatened a ship (a station, a capital ship) is: what its commander
## sizes its patrol by (CommanderPatrol.wanted_fighters, through doctrine).
##
## Always 0 in the first NPC AI pass: threat assessment is its own later pass.
## Planned (design doc, "NPC AI: first pass"): a memory of last known contacts
## from the side's sensors (fog of war) that decays over time, each hostile
## (faction relations below 0) weighted by its class and how close it is.


## The threat to [param ship]; 0 means none.
static func threat_to(_ship: Ship) -> float:
	return 0.0
