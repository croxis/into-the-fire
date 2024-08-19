class_name Pilot
extends Node

@export var _faction_name: String
# If this is the player, set the id to 0 or more
# Cache the pilot ID in here
@export var _player_pilot_id: int
@export var multiplayer_id: int:
	set(id):
		multiplayer_id = id
		# Give authority over the player input to the appropriate peer.
		$InputsSync.set_multiplayer_authority(id)
		$PilotSync.set_multiplayer_authority(id)


func set_faction(faction: Faction):
	_faction_name = faction.name


func _to_string() -> String:
	return name
