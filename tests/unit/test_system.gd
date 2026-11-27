extends GutTest
## A star system is a zone: a SubViewport with its own World3D, and its ships,
## bolts and spawners directly under it (zone slice 2).

const ShipScene := preload("res://ships/Ship.tscn")
const SystemScene := preload("res://systems/system_template.tscn")
const TestSystemScene := preload("res://systems/test_system/test_system.tscn")


func _system(scene: PackedScene = SystemScene) -> System:
	var system: System = scene.instantiate()
	add_child_autofree(system)
	return system


func test_system_is_a_zone_with_its_own_world() -> void:
	var system := _system()
	assert_true(system is SubViewport)
	assert_true(system.own_world_3d)
	assert_ne(system.find_world_3d(), get_viewport().find_world_3d())


func test_zone_parts_sit_under_the_root() -> void:
	var system := _system()
	for part in ["ships", "bolts", "ShipSpawner", "BoltSpawner", "StarField", "RTSCameras"]:
		assert_true(system.has_node(part), part)


func test_test_system_keeps_its_scenery() -> void:
	# The playtest system adds lights, an environment and music on top of the template.
	var system := _system(TestSystemScene)
	for part in ["WorldEnvironment", "DirectionalLight3D", "AudioStreamPlayer", "RTSCameras/RtsCamera"]:
		assert_true(system.has_node(part), part)


func test_add_ship_places_it_in_ships() -> void:
	var system := _system()
	var ship: Ship = ShipScene.instantiate()
	system.add_ship(ship)
	assert_eq(ship.get_parent(), system.get_node("ships"))
	assert_has(system.get_ships(), ship)


func test_ship_finds_its_system() -> void:
	var system := _system()
	var ship: Ship = ShipScene.instantiate()
	system.add_ship(ship)
	assert_eq(ship.get_current_system(), system)
	assert_eq(System.find_for(ship), system)


func test_find_for_outside_a_system_is_null() -> void:
	var node := Node3D.new()
	add_child_autofree(node)
	assert_null(System.find_for(node))


func test_a_gun_puts_its_bolt_in_the_system() -> void:
	# Gun.fire finds the system's bolts node by a relative path
	# (Gun > Guns > ship > ships > system), so it depends on the system layout.
	var system := _system()
	var ship: Ship = ShipScene.instantiate()
	system.add_ship(ship)
	var gun: Gun = preload("res://ship_systems/weapons/Gun.tscn").instantiate()
	gun.bolt_resource = preload("res://ship_systems/weapons/effects/bolt/Bolt.tscn")
	ship.get_node("Guns").add_child(gun)
	ship.get_node("Guns").fire()
	assert_eq(system.get_node("bolts").get_child_count(), 1)


## Spawn points and respawns: the ships in a system where a side's players can
## spawn, and where a destroyed ship's crew go.

func _playtest_tree(registry: FactionRegistry) -> Dictionary:
	var ea := registry.create("Earth Alliance")
	var b5 := registry.create("Babylon 5", false, false, false, ea)
	var zeta := registry.create("Zeta Wing", true, true, false, b5)
	return {"ea": ea, "b5": b5, "zeta": zeta}


func _ship_in(system: System, registry: FactionRegistry, faction: Faction, ship_name := "",
		x := 0.0) -> Ship:
	var ship: Ship = ShipScene.instantiate()
	if ship_name:
		ship.name = ship_name
	ship.faction_registry = registry
	system.add_ship(ship)
	ship.faction_id = faction.faction_id
	ship.position = Vector3(x, 0, 0)
	return ship


func _pilot(registry: FactionRegistry, faction: Faction) -> Character:
	var pilot: Character = autofree(preload("res://characters/character.tscn").instantiate())
	pilot.faction_registry = registry
	faction.add_member(pilot)
	return pilot


func test_spawn_points_are_on_the_players_own_side() -> void:
	var registry := FactionRegistry.new()
	var t := _playtest_tree(registry)
	var narn := registry.create("Narn Regime")
	var system := _system()
	_ship_in(system, registry, t.b5, "Babylon5").has_spawn_points = true
	_ship_in(system, registry, t.ea, "Hyperion").has_spawn_points = true
	_ship_in(system, registry, narn, "Gquan").has_spawn_points = true
	_ship_in(system, registry, t.zeta, "Starfury")
	assert_eq(system.spawn_points_for(t.zeta), ["Babylon5", "Hyperion"],
			"own side (the wing's parents too), with launch bays; nothing about the Narn")
	assert_eq(system.spawn_points_for(narn), ["Gquan"])


func test_galaxy_spawn_points_list_each_system_with_any() -> void:
	var galaxy: Galaxy = load("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)
	var t := _playtest_tree(galaxy.factions)
	var narn := galaxy.factions.create("Narn Regime")
	var by_name := {}
	for system_name in ["epsilon", "sol", "narn"]:
		var system: System = SystemScene.instantiate()
		system.name = system_name
		galaxy.get_node("Systems").add_child(system)
		by_name[system_name] = system
	_ship_in(by_name.epsilon, galaxy.factions, t.b5, "Babylon5").has_spawn_points = true
	_ship_in(by_name.sol, galaxy.factions, t.ea, "Hyperion").has_spawn_points = true
	_ship_in(by_name.narn, galaxy.factions, narn, "KhaRi").has_spawn_points = true
	assert_eq(galaxy.systems().size(), 3)
	assert_eq(galaxy._spawn_points(t.zeta), {"epsilon": ["Babylon5"], "sol": ["Hyperion"]},
			"no entry for a system with nowhere to spawn")


func test_respawn_skips_the_destroyed_ship() -> void:
	var registry := FactionRegistry.new()
	var t := _playtest_tree(registry)
	var system := _system()
	var dying := _ship_in(system, registry, t.b5, "", 0)
	dying.is_capital = true
	var hyperion := _ship_in(system, registry, t.ea, "", 5800)
	hyperion.is_capital = true
	assert_eq(system.nearest_carrier_for(_pilot(registry, t.zeta), dying), hyperion,
			"the destroyed ship is still listed until it is freed")


func test_respawn_picks_nearest_own_side_capital() -> void:
	var registry := FactionRegistry.new()
	var t := _playtest_tree(registry)
	var narn := registry.create("Narn Regime")
	var system := _system()
	var dying := _ship_in(system, registry, t.zeta, "", 0)
	var pilot := _pilot(registry, t.zeta)
	assert_null(system.nearest_carrier_for(pilot, dying), "no capital ship here")
	_ship_in(system, registry, narn, "", 10).is_capital = true
	_ship_in(system, registry, t.zeta, "", 5)  # A fighter.
	assert_null(system.nearest_carrier_for(pilot, dying), "only a hostile capital and a fighter")
	_ship_in(system, registry, t.ea, "", 9000).is_capital = true
	var near := _ship_in(system, registry, t.b5, "", 1000)
	near.is_capital = true
	assert_eq(system.nearest_carrier_for(pilot, dying), near)


func test_a_ghost_replaces_an_older_one_of_the_same_ship() -> void:
	var system := _system()
	var contacts := ContactLog.new(1.0 / 60.0)
	contacts.lost(9, {"name": "Raider", "faction_id": 7, "system": "s", "velocity": Vector3.ZERO,
			"transform": Transform3D(), "immobile": false, "tick": 0})
	for i in 2:
		var marker := GhostMarker.new()
		marker.setup(contacts, 9, func() -> float: return 0.0)
		system.add_ghost(marker)
	var ghosts := system.get_node("Ghosts")
	assert_eq(ghosts.get_child_count(), 1)
	assert_eq(ghosts.get_child(0).name, &"Ghost9")
