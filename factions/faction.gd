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
var top_faction: Faction:
	get:
		if parent_faction:
			return parent_faction.top_faction
		return self

@export var doctrine: FactionDoctrine
## Kept out of its top-level faction's shared picture (fog of war): its ships
## and what they detect are seen by this faction and those below it, not by the
## rest of the side. One-way: it still sees the shared picture. Server only
## (not sent to clients); changed through FogOfWar.check_exclusion_change.
@export var excluded_from_picture := false

## The FactionRegistry this faction belongs to (set by the registry).
## Weak because the registry already holds the faction: two strong references to
## each other would form a cycle, and neither would ever be freed.
var registry: WeakRef

# Variables only needed by the server
var detected_ships: Array[Ship] = []:   # Make sure to include ships owned by the faction
	get:
		if parent_faction:
			return parent_faction.detected_ships
		else:
			return detected_ships

# For now just hold owned ships in the top level faction
# TODO: Have better ownership tracking
var owned_ships: Array[Ship] = []:
	get:
		if parent_faction:
			return parent_faction.owned_ships
		return owned_ships


func is_a_parent(possible_parent_faction: Faction) -> bool:
	var current_parent: Faction = parent_faction
	while current_parent:
		if current_parent == possible_parent_faction:
			return true
		current_parent = current_parent.parent_faction
	return false  # Reached the top of the tree.


## Direct child factions, found through the registry. Empty if this faction
## isn't in a registry.
func get_children() -> Array[Faction]:
	var r: FactionRegistry = registry.get_ref() if registry else null
	if r == null:
		var none: Array[Faction] = []
		return none
	return r.children_of(self)


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
	var f: Array[Faction] = []
	for child in get_children():
		if child.is_wing:
			f.append(child)
	return f


func add_member(pilot: Character) -> void:
	#TODO: Remove the pilot as leader of its old faction too.
	if pilot.faction and pilot.faction != self:
		pilot.faction.remove_member(pilot)
	pilot.faction_id = faction_id
	if pilot.pilot_id not in member_ids:
		member_ids.append(pilot.pilot_id)


func remove_member(pilot: Character) -> bool:
	member_ids.erase(pilot.pilot_id)
	pilot.faction_id = FactionRegistry.NO_FACTION
	return true


func _on_fleet_ship_detected(ship: Ship):
	if parent_faction:
		parent_faction._on_fleet_ship_detected(ship)
	elif ship not in detected_ships:
		detected_ships.append(ship)


func _on_fleet_ship_sensor_lost(ship: Ship):
	detected_ships.erase(ship)

func add_ship(ship: Ship) -> bool:
	if ship not in owned_ships:
		owned_ships.append(ship)
		return true
	return false

func remove_ship(ship: Ship) -> bool:
	if ship in owned_ships:
		owned_ships.erase(ship)
		return true
	return false
