class_name ScenarioCrew
extends Resource
## One NPC crew member aboard a ScenarioShip.

@export var name := ""
## Faction name. Empty means the ship's faction.
@export var faction := ""
## Console to sit at, relative to the ship (e.g. Consoles/StationCommand).
## Empty leaves the character as a passenger.
@export var console: NodePath
