class_name ScenarioFaction
extends Resource
## One faction in a Scenario.

@export var name := ""
## The parent faction's name, or empty for a top-level faction.
@export var parent := ""
@export var is_wing := false
@export var accept_players := false
@export var accept_children := false
## AI settings for the faction. Copied into the world, so play never changes
## the scenario resource.
@export var doctrine: FactionDoctrine
