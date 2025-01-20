class_name Pilot
extends Node

@export var _faction_name: String
# If this is the player, set the id to 1 or more
@export var _player_pilot_id: int
@export var multiplayer_id: int


func set_multiplayer_id(id):
	multiplayer_id = id
	# Give authority over the player input to the appropriate peer.
	$InputsSync.set_multiplayer_authority(id)


func _to_string() -> String:
	return name
