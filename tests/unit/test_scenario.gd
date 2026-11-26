extends GutTest
## Scenarios: a Resource describing the starting world, checked and built by
## ScenarioLoader.

const SYSTEM := &"t:system"
const SHIP := &"t:ship"

var content: ContentRegistry


func before_each() -> void:
	content = ContentRegistry.new()
	content.register(SYSTEM, &"system", "res://systems/test_system/test_system.tscn")
	content.register(SHIP, &"ship", "res://ships/Ship.tscn")
	content.register(&"b5:babylon_5", &"ship", "res://ships/earth alliance/babylon 5/babylon_5.tscn")


func _faction(faction_name: String, parent := "", wing := false, players := false) -> ScenarioFaction:
	var f := ScenarioFaction.new()
	f.name = faction_name
	f.parent = parent
	f.is_wing = wing
	f.accept_players = players
	return f


func _ship(ship_name: String, faction: String, id := SHIP) -> ScenarioShip:
	var s := ScenarioShip.new()
	s.content_id = id
	s.ship_name = ship_name
	s.system = SYSTEM
	s.faction = faction
	return s


func _crew(crew_name: String, faction := "", console := NodePath()) -> ScenarioCrew:
	var c := ScenarioCrew.new()
	c.name = crew_name
	c.faction = faction
	c.console = console
	return c


func _scenario() -> Scenario:
	var s := Scenario.new()
	s.factions.assign([_faction("Earth Alliance"), _faction("Babylon 5", "Earth Alliance"),
			_faction("Zeta Wing", "Babylon 5", true, true)])
	s.systems.assign([SYSTEM])
	return s


## A stand-in for a System: places ships as children, like System does.
func _fake_system() -> Node3D:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nfunc add_ship(s): add_child(s, true)\nfunc add_station(s): add_child(s, true)\n"
	script.reload()
	var system := Node3D.new()
	system.set_script(script)
	add_child_autofree(system)
	return system


## validate

func test_valid_scenario_has_no_errors() -> void:
	var s := _scenario()
	s.ships.assign([_ship("Hyperion", "Earth Alliance")])
	assert_eq(ScenarioLoader.validate(s, content), PackedStringArray())


func test_unknown_parent_faction() -> void:
	var s := _scenario()
	s.factions.append(_faction("Psi Corps", "Psi Corps HQ"))
	assert_eq(ScenarioLoader.validate(s, content).size(), 1)


func test_duplicate_faction_names() -> void:
	var s := _scenario()
	s.factions.append(_faction("Zeta Wing"))
	assert_eq(ScenarioLoader.validate(s, content).size(), 1)


func test_unknown_content_ids() -> void:
	var s := _scenario()
	s.systems.append(&"t:missing_system")
	s.ships.assign([_ship("Ghost", "Earth Alliance", &"t:missing_ship")])
	assert_eq(ScenarioLoader.validate(s, content).size(), 2)


func test_ship_in_a_system_not_listed() -> void:
	var s := _scenario()
	var ship := _ship("Lost", "Earth Alliance")
	ship.system = &"t:elsewhere"
	s.ships.assign([ship])
	assert_eq(ScenarioLoader.validate(s, content).size(), 1)


func test_unknown_factions_on_ships_and_crew() -> void:
	var s := _scenario()
	var ship := _ship("Narn cruiser", "Narn Regime")
	ship.crew.assign([_crew("G'Kar", "Narn Regime")])
	s.ships.assign([ship])
	assert_eq(ScenarioLoader.validate(s, content).size(), 2)


## build_factions

func test_build_factions_keeps_tree_and_flags() -> void:
	var s := _scenario()
	s.factions[1].doctrine = FactionDoctrine.new()
	s.factions[1].doctrine.minimum_patrol_fighters = 2
	var registry := ScenarioLoader.build_factions(s)

	assert_eq(registry.size(), 3)
	var zeta := registry.find_by_name("Zeta Wing")
	assert_true(zeta.is_wing)
	assert_true(zeta.accept_players)
	assert_eq(zeta.parent_faction, registry.find_by_name("Babylon 5"))
	assert_eq(registry.find_by_name("Babylon 5").doctrine.minimum_patrol_fighters, 2)
	assert_ne(registry.find_by_name("Babylon 5").doctrine, s.factions[1].doctrine,
			"a copy: the world must not change the scenario resource")


func test_exclusions_from_the_shared_picture_are_loaded() -> void:
	# Fog of war: covert wings and ships, set in the scenario.
	var s := _scenario()
	s.factions[2].excluded_from_picture = true  # Zeta Wing.
	var covert := _ship("Black Omega", "Zeta Wing")
	covert.excluded_from_picture = true
	s.ships.assign([_ship("Picket", "Zeta Wing"), covert])
	var registry := ScenarioLoader.build_factions(s)
	assert_true(registry.find_by_name("Zeta Wing").excluded_from_picture)
	assert_false(registry.find_by_name("Babylon 5").excluded_from_picture)
	var ships := ScenarioLoader.populate(s, content, registry, {SYSTEM: _fake_system()}, WorldIds.new(), 1)
	assert_false(ships[0].excluded_from_picture)
	assert_true(ships[1].excluded_from_picture)


func test_parent_may_be_listed_after_child() -> void:
	var s := Scenario.new()
	s.factions.assign([_faction("Zeta Wing", "Babylon 5", true), _faction("Babylon 5")])
	var registry := ScenarioLoader.build_factions(s)
	assert_eq(registry.find_by_name("Zeta Wing").parent_faction, registry.find_by_name("Babylon 5"))


## populate

func test_populate_places_ships_with_ids_and_factions() -> void:
	var s := _scenario()
	var hyperion := _ship("EASS Hyperion", "Earth Alliance")
	hyperion.position = Vector3(5800, 0, 0)
	s.ships.assign([_ship("Picket", "Zeta Wing"), hyperion])
	var registry := ScenarioLoader.build_factions(s)
	var system := _fake_system()
	var ids := WorldIds.new()

	var ships := ScenarioLoader.populate(s, content, registry, {SYSTEM: system}, ids, 1)

	assert_eq(ships.size(), 2)
	assert_eq(ships[1].get_parent(), system)
	assert_eq(String(ships[1].name), "EASS Hyperion")
	assert_eq(ships[1].position, Vector3(5800, 0, 0))
	assert_eq(ships[1].faction_id, registry.find_by_name("Earth Alliance").faction_id)
	assert_eq([ships[0].ship_id, ships[1].ship_id], [1, 2], "IDs come from the world")


func test_populate_spawns_crew_in_their_factions() -> void:
	var s := _scenario()
	var ship := _ship("Picket", "Zeta Wing")
	ship.crew.assign([_crew("Karren Waffer")])
	s.ships.assign([ship])
	var registry := ScenarioLoader.build_factions(s)
	var ids := WorldIds.new()

	var placed := ScenarioLoader.populate(s, content, registry, {SYSTEM: _fake_system()}, ids, 1)

	var crew := placed[0].get_crew()
	assert_eq(crew.size(), 1)
	assert_eq(String(crew[0].name), "Karren Waffer")
	var zeta := registry.find_by_name("Zeta Wing")
	assert_eq(crew[0].faction_id, zeta.faction_id, "no crew faction: the ship's")
	assert_has(zeta.member_ids, crew[0].pilot_id)
	assert_eq(crew[0].pilot_id, 1, "pilot IDs come from the world too")


func test_populate_seats_crew_at_their_console() -> void:
	var s := _scenario()
	var station := _ship("Babylon 5", "Babylon 5", &"b5:babylon_5")
	station.crew.assign([_crew("Commander", "", NodePath("Consoles/StationCommand"))])
	s.ships.assign([station])
	var registry := ScenarioLoader.build_factions(s)

	var placed := ScenarioLoader.populate(s, content, registry, {SYSTEM: _fake_system()}, WorldIds.new(), 1)

	var console: Console = placed[0].get_node("Consoles/StationCommand")
	assert_eq(String(console.occupant.name), "Commander")


## Scenes to load before building

func test_scene_paths_are_systems_then_each_ship_once() -> void:
	var s := _scenario()
	s.ships.assign([_ship("A", "Babylon 5"), _ship("Station", "Babylon 5", &"b5:babylon_5"),
			_ship("B", "Babylon 5")])
	assert_eq(ScenarioLoader.scene_paths(s, content), PackedStringArray([
			"res://systems/test_system/test_system.tscn",
			"res://ships/Ship.tscn",
			"res://ships/earth alliance/babylon 5/babylon_5.tscn"]))


func test_scene_paths_skip_unknown_content() -> void:
	var s := _scenario()
	s.ships.assign([_ship("A", "Babylon 5", &"t:nothing")])
	assert_eq(ScenarioLoader.scene_paths(s, content),
			PackedStringArray(["res://systems/test_system/test_system.tscn"]))


## The shipped playtest scenario

func test_playtest_scenario_is_valid() -> void:
	var registry := ContentRegistry.new()
	registry.load_manifest("res://content/babylon5.cfg")
	var playtest := load(registry.path_of(&"b5:playtest")) as Scenario
	assert_not_null(playtest)
	assert_eq(ScenarioLoader.validate(playtest, registry), PackedStringArray())


func test_world_ids_start_at_one_and_never_repeat() -> void:
	var ids := WorldIds.new()
	assert_eq([ids.next_ship(), ids.next_ship(), ids.next_pilot()], [1, 2, 1])


func test_playtest_has_an_enemy_its_players_cannot_see_at_first() -> void:
	# Fog of war (netcode N5b3) needs something to hide: a ship of another
	# top-level faction, out of every Earth Alliance sensor's range at the start.
	var registry := ContentRegistry.new()
	registry.load_manifest("res://content/babylon5.cfg")
	var playtest := load(registry.path_of(&"b5:playtest")) as Scenario
	var tops := {}  # Faction name -> its top-level faction's name.
	for f in playtest.factions:
		tops[f.name] = f.parent
	var top_of := func(name: String) -> String:
		while tops.get(name, "") != "":
			name = tops[name]
		return name
	var ours: Array[ScenarioShip] = []
	var enemies: Array[ScenarioShip] = []
	for s in playtest.ships:
		if top_of.call(s.faction) == "Earth Alliance":
			ours.append(s)
		else:
			enemies.append(s)
	assert_false(enemies.is_empty(), "an enemy")
	# The real ships at their places: every signature, and how big they look.
	for enemy in enemies:
		var target: Ship = load(registry.path_of(enemy.content_id)).instantiate()
		add_child_autofree(target)
		target.global_position = enemy.position
		for own in ours:
			var watcher: Ship = load(registry.path_of(own.content_id)).instantiate()
			add_child_autofree(watcher)
			watcher.global_position = own.position
			assert_false(watcher.sensor_check(target), "%s can't see %s" % [own.content_id, enemy.ship_name])
