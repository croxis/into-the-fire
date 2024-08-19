class_name Pilot
extends Node

@export var faction: Faction
# If this is the player, set the id to 0 or more
# Cache the pilot ID in here
@export var _player_pilot_id: int
@export var multiplayer_id: int:
	set(id):
		multiplayer_id = id
		# Give authority over the player input to the appropriate peer.
		$InputsSync.set_multiplayer_authority(id)
		$PilotSync.set_multiplayer_authority(id)


func _to_string() -> String:
	return name
