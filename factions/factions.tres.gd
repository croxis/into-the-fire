extends Node

@export var faction_id_counter := 1
var factions := {} # {id: Faction}

#TODO: Move this all into a static function inside faction?

func _ready() -> void:
	#TODO: When loading from a save, the counter should update to n+1 of the highest id in the save
	# OR what would be smarter is also saving the id counter
	var ea := create_faction("Earth Alliance", false, false, false)
	var b5 := create_faction("Babylon 5", false, false, false)
	b5.parent_faction = ea
	var wing := create_faction("Alpha Wing", true, true, false)
	wing.parent_faction = b5
	wing = create_faction("Beta Wing", true, true, false)
	wing.parent_faction = b5
	wing = create_faction("Gamma Wing", true, true, false)
	wing.parent_faction = b5
	wing = create_faction("Delta Wing", true, true, false)
	wing.parent_faction = b5


@rpc("authority", "call_local", "reliable")
func create_faction(name: String, is_wing: bool, accept_players: bool, accept_children: bool) -> Faction:
	var new_faction = Faction.new()
	new_faction.resource_name = name
	new_faction.is_wing = is_wing
	new_faction.accept_players = accept_players
	new_faction.accept_children = accept_children
	new_faction.faction_id = faction_id_counter
	new_faction.active = true
	factions[new_faction.faction_id] = new_faction
	faction_id_counter += 1
	return new_faction


func get_faction(faction_name: String) -> Faction:
	for faction in factions.values():
		if faction.resource_name == faction_name:
			return faction
	Log.log(["Faction not found:", faction_name], Log.MessageType.WARNING)
	return null
		
