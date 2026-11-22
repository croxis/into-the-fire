class_name Scenario
extends Resource
## The starting state of a world: factions, the systems to load, and the ships
## and crew in them. Listed in the content registry (kind "scenario") and turned
## into the world by ScenarioLoader on the server.
##
## Scenarios are text resources (.tres) so they can be reviewed, merged and
## shipped by mods. They describe the same records a save holds (design doc:
## saves), so a save is a scenario's records plus everything changed since.
##
## Things refer to each other by name (factions) or content ID (systems, ships),
## never by node path, so a scenario survives scenes being edited.

@export var title := ""
## In creation order. A faction's parent may be listed before or after it.
@export var factions: Array[ScenarioFaction] = []
## Content IDs of the systems to load, e.g. b5:test_system.
@export var systems: Array[StringName] = []
@export var ships: Array[ScenarioShip] = []
