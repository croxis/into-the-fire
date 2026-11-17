extends ConsoleCapability

class_name CommandCapability

@export var ship: Ship = null


## Returns the ships of subordinant wings in the escort sphere
func get_subordinate_ships_in_escort_range() -> Array[Ship]:
	var ships: Array[Ship] = []
	if ship:
		var escort: Area3D = ship.get_node("EscortRange") as Area3D
		var objects: = escort.get_overlapping_bodies()
		for o in objects:
			if o is not Ship:
				continue
			var s: Ship = o as Ship
			var factions: Array[Faction] = ship.faction.get_wings()
			if s.faction in factions:
				ships.append(s)
	return ships
