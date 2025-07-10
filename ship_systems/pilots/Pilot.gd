class_name Pilot
extends Node

# This getter setter chain is attempting to automagically assign the player the correct resource for
# network clients
@export var _faction_id: int:
	set(new_id):
		if faction and faction.faction_id == new_id:
			print_debug("_faction_id error", new_id, faction, faction.faction_id)
			return
		_faction_id = new_id
		# A zero value is no faction.
		if _faction_id:
			faction = Faction.factions[new_id]
@export var faction: Faction:
	set(new_faction):
		if faction:
			faction.remove_member(self)
		faction = new_faction
		_faction_id = faction.faction_id
		Logger.log(["Player gets new faction:", name, faction.resource_name], Logger.MessageType.INFO)
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
