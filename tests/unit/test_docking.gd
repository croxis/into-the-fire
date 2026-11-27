extends GutTest
## Docking: a ship entering a carrier's dock area (server only) hands its crew
## to the carrier and is freed. The crew must come through the carrier's own
## CrewMultiplayerSpawner, as for respawns and launches: a reparented character
## is not tracked by any spawner, so clients would keep it on the freed ship
## (despawned with it) and never see it aboard the carrier.

var galaxy: Galaxy
var system: System


func before_each() -> void:
	galaxy = preload("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)
	system = preload("res://systems/system_template.tscn").instantiate()
	galaxy.zones.add_system(system)


func _fighter_with_pilot(pilot_name: String) -> Ship:
	var fighter: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(fighter)
	fighter.spawn_crew(Character.pilot_data(pilot_name, 0, 0, galaxy.ids.next_pilot()))
	return fighter


func _crew_names(ship: Ship) -> Array:
	return ship.get_crew().filter(func(c: Character) -> bool: return not c.is_queued_for_deletion()) \
			.map(func(c: Character) -> String: return String(c.name))


func test_docked_crew_are_spawned_aboard_not_moved() -> void:
	var carrier: Ship = Content.instantiate(&"b5:hyperion")
	system.add_ship(carrier)
	var fighter := _fighter_with_pilot("Alpha 1")
	var old_pilot: Character = fighter.get_crew()[0]
	carrier._on_area_3d_dock_body_entered(fighter)
	assert_has(_crew_names(carrier), "Alpha 1", "aboard the carrier")
	var aboard: Character = carrier.get_crew().filter(
			func(c: Character) -> bool: return String(c.name) == "Alpha 1")[0]
	assert_ne(aboard, old_pilot, "a new character from the carrier's spawner, not the old one moved")
	assert_eq(aboard.pilot_id, old_pilot.pilot_id, "the same pilot")
	assert_true(fighter.is_queued_for_deletion(), "the docked ship goes, and its crew with it")


func test_a_full_carrier_turns_a_ship_away() -> void:
	# The crew who didn't fit used to be freed with their ship.
	var carrier: Ship = Content.instantiate(&"b5:hyperion")
	system.add_ship(carrier)
	carrier.get_node("Crew").max_crew = carrier.get_crew().size()  # Full.
	var fighter := _fighter_with_pilot("Alpha 2")
	carrier._on_area_3d_dock_body_entered(fighter)
	assert_false(fighter.is_queued_for_deletion(), "it stays outside")
	assert_eq(_crew_names(fighter), ["Alpha 2"], "with its pilot")
	assert_does_not_have(_crew_names(carrier), "Alpha 2")
