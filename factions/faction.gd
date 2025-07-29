extends Resource
class_name Faction
@export_category("Faction Data")

@export var relations := {} # These are $Factions: +-10 scale
@export var accept_players := false
@export var accept_children := false
@export var is_wing := false
@export var faction_id: int
@export var member_ids: Array[int] = []
@export var leader_id: int
@export var active := true

# Reference to a parent guild resource to represent hierarchy (can be null)
@export var parent_faction: Faction = null

static var _next_id := 0
static var factions := {}

# Variables only needed by the server
var detected_ships := []  # Make sure to include ships owned by the faction

@rpc("authority", "call_local", "reliable")
static func new_faction(name: String, is_wing: bool, accept_players: bool, accept_children: bool) -> Faction:
	var new_faction = Faction.new()
	new_faction.resource_name = name
	new_faction.is_wing = is_wing
	new_faction.accept_players = accept_players
	new_faction.accept_children = accept_children
	new_faction.faction_id = _next_id
	new_faction.active = true
	factions[new_faction.faction_id] = new_faction
	_next_id += 1
	Logger.log(["Faction created:", new_faction.faction_id, new_faction.resource_name], Logger.MessageType.INFO)
	return new_faction


static func get_faction(faction_name: String) -> Faction:
	for faction in factions.values():
		if faction.resource_name == faction_name:
			return faction
	Logger.log(["Faction not found:", faction_name], Logger.MessageType.WARNING)
	return null


func get_children() -> Array[Faction]:
	var children: Array[Faction] = []
	for faction in factions.values():
		if faction.parent_faction and faction.parent_faction.faction_id == faction_id:
			children.append(faction)
	return children


# Example method to calculate inherited standings from parent guild
func get_inherited_standings() -> Dictionary:
	var inherited = {}
	if parent_faction and parent_faction is Faction:
		inherited = parent_faction.get_inherited_standings()
	# Merge own standings with inherited, prioritizing own values
	for key in relations.keys():
		inherited[key] = relations[key]
	return inherited


func get_wings() -> Array[Faction]:
	var factions: Array[Faction] = []
	for child in get_children():
		if child.typeof(Faction):
			if child.is_wing:
				factions.append(child)
	return factions


func add_member(pilot: Pilot) -> void:
	#TODO: Check and remove if pilot is in another faction, remove from faction and leader
	if pilot.faction:
		pilot.faction.remove_member(pilot)
	pilot.faction = self
	member_ids.append(pilot.pilot_id)


func remove_member(pilot: Pilot) -> bool:
	member_ids.erase(pilot.pilot_id)
	pilot.faction = null
	pilot._faction_id = 0
	return true


func _on_fleet_ship_detected(ship: Ship):
	return


func _on_fleet_ship_sensor_lost(ship: Ship):
	return
