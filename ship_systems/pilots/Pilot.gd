class_name Pilot
extends Node

@export var _faction_id: int
# If this is the player, set the id to 1 or more
@export var _player_pilot_id: int
@export var multiplayer_id: int
@export var pilot_id: int
static var next_id := 0
static var pilot_scene: PackedScene = load("res://ship_systems/pilots/Pilot.tscn")

static func new_pilot(name: String) -> Pilot:
	var new_pilot = pilot_scene.instantiate()
	new_pilot.name = name
	new_pilot.pilot_id = next_id
	next_id += 1
	return new_pilot


func set_multiplayer_id(id):
	multiplayer_id = id
	# Give authority over the player input to the appropriate peer.
	$InputsSync.set_multiplayer_authority(id)


func _to_string() -> String:
	return name
