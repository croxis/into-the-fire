extends GutTest
## SpawnService: where a world's players come in (first spawn, rejoin) and
## where crews go when their ship is destroyed (RespawnRules). Server rules;
## clients only ask (request_spawn, request_spawn_points). Offline, this
## machine is the server.

var galaxy: Galaxy
var system: System
var zeta: Faction
var b5: Faction


func before_each() -> void:
	galaxy = preload("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)
	var ea := galaxy.factions.create("Earth Alliance")
	b5 = galaxy.factions.create("Babylon 5", false, false, false, ea)
	zeta = galaxy.factions.create("Zeta Wing", true, true, false, b5)
	system = preload("res://systems/system_template.tscn").instantiate()
	system.name = "epsilon"
	galaxy.zones.add_system(system)


func _ship(id: StringName, faction: Faction, x := 0.0) -> Ship:
	var ship: Ship = Content.instantiate(id)
	system.add_ship(ship)
	ship.faction_id = faction.faction_id
	ship.position = Vector3(x, 0, 0)
	return ship


func _crew_of(ship: Ship) -> Array:
	return ship.get_crew().filter(func(c: Character) -> bool: return not c.is_queued_for_deletion())


func test_spawn_points_list_each_system_with_any() -> void:
	_ship(&"b5:hyperion", b5).has_spawn_points = true
	var points: Dictionary = galaxy.spawns.spawn_points(zeta)
	assert_eq(points.keys(), ["epsilon"])


func test_no_system_named_means_the_first_with_spawn_points() -> void:
	# A test player (--faction) doesn't know the scenario's system names.
	var points := {"sol": ["Hyperion"], "epsilon": ["Babylon 5"]}
	assert_eq(SpawnService.resolve_spawn_point(points, "", ""), ["sol", "Hyperion"])
	assert_eq(SpawnService.resolve_spawn_point(points, "epsilon", ""), ["epsilon", "Babylon 5"])
	assert_eq(SpawnService.resolve_spawn_point(points, "epsilon", "Babylon 5"), ["epsilon", "Babylon 5"])
	assert_eq(SpawnService.resolve_spawn_point({}, "", ""), [], "nowhere to spawn")
	assert_eq(SpawnService.resolve_spawn_point(points, "epsilon", "Hyperion"), [], "not offered there")


func test_a_destroyed_ships_crew_respawn_on_the_nearest_carrier() -> void:
	var carrier := _ship(&"b5:hyperion", b5, 1000)
	carrier.is_capital = true
	var fighter := _ship(&"b5:aurora_starfury", zeta)
	var before := _crew_of(carrier).size()
	fighter.spawn_crew(Character.pilot_data("Alpha 1", zeta.faction_id, 0, galaxy.ids.next_pilot()))
	fighter.destroy()
	assert_eq(_crew_of(carrier).size(), before + 1, "the pilot is aboard the carrier again")


func test_with_no_respawn_the_crew_stay_dead() -> void:
	galaxy.spawns.rules = RespawnRules.new()
	galaxy.spawns.rules.mode = RespawnRules.Mode.NONE
	var carrier := _ship(&"b5:hyperion", b5, 1000)
	carrier.is_capital = true
	var fighter := _ship(&"b5:aurora_starfury", zeta)
	var before := _crew_of(carrier).size()
	fighter.spawn_crew(Character.pilot_data("Alpha 1", zeta.faction_id, 0, galaxy.ids.next_pilot()))
	fighter.destroy()
	assert_eq(_crew_of(carrier).size(), before)
