class_name ScenarioShip
extends Resource
## One ship or station in a Scenario.

## Content ID of the ship scene, e.g. b5:hyperion.
@export var content_id: StringName
## Node name in the world. Empty keeps the scene's own name.
@export var ship_name := ""
## Content ID of the system it starts in. Must be listed in Scenario.systems.
@export var system: StringName
@export var position := Vector3.ZERO
## Owning faction's name, or empty for no faction.
@export var faction := ""
@export var crew: Array[ScenarioCrew] = []
