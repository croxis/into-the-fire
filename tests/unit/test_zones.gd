extends GutTest
## Zones: the one owner that knows which zones (star systems for now) a world
## has and who is in each. It hands each zone to the ZoneStepper as it arrives
## (from setup on the server, from the spawner on clients).

const SystemScene := preload("res://systems/system_template.tscn")

var galaxy: Galaxy


func before_each() -> void:
	galaxy = preload("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)


func test_a_zone_added_is_stepped_by_the_world() -> void:
	var system := SystemScene.instantiate() as System
	galaxy.zones.add_system(system)
	assert_has(galaxy.zones.systems(), system)
	assert_true(galaxy.zone_stepper.has_zone(system))


func test_zones_get_the_worlds_rewind_cap() -> void:
	galaxy.max_rewind_ticks = 7
	var system := SystemScene.instantiate() as System
	galaxy.zones.add_system(system)
	assert_eq(system.shots.max_rewind_ticks, 7)


func test_systems_are_found_by_name_and_only_among_the_zones() -> void:
	var system := SystemScene.instantiate() as System
	galaxy.zones.add_system(system)
	assert_eq(galaxy.zones.get_system(String(system.name)), system)
	# Names can come from clients: a path must not reach other nodes.
	for name in ["", "..", "../Players", "Narn", String(system.name) + "/ships"]:
		assert_null(galaxy.zones.get_system(name), name)


func test_a_system_is_found_by_its_content_id() -> void:
	var system := Content.instantiate(&"b5:test_system") as System
	galaxy.zones.add_system(system)
	assert_eq(galaxy.zones.system_for_content(&"b5:test_system"), system)


func test_a_players_character_is_found_in_any_zone() -> void:
	var system := SystemScene.instantiate() as System
	galaxy.zones.add_system(system)
	assert_null(galaxy.zones.player_character(3))
	var carrier: Ship = Content.instantiate(&"b5:hyperion")
	system.add_ship(carrier)
	var pilot := carrier.spawn_crew(Character.pilot_data("Player 3", 0, 1, 3, 3))
	assert_eq(galaxy.zones.player_character(3), pilot)
	assert_has(galaxy.zones.characters_of_peer(1), pilot)
	assert_eq(galaxy.zones.characters_of_peer(2).size(), 0)
