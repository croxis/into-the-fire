extends GutTest
## ContactBrackets: every ship the player's client knows in the viewed zone
## gets a bracket on the HUD that stays visible however far away it is (a
## Starfury 10 km out is less than a pixel), with its name and distance; one
## off screen gets an arrow at the edge pointing to it. Fog of war already
## decides which ships a client knows.

const SIZE := Vector2(1600, 900)

var viewport: SubViewport
var camera: Camera3D


func before_each() -> void:
	viewport = SubViewport.new()
	viewport.size = SIZE
	add_child_autofree(viewport)
	camera = Camera3D.new()
	viewport.add_child(camera)
	camera.current = true  # At the origin, looking down -Z.


func test_a_ship_ahead_is_bracketed_where_it_is() -> void:
	var mark := ContactBrackets.place(camera, Vector3(0, 0, -10000), SIZE)
	assert_true(mark.on_screen)
	assert_almost_eq(mark.position, SIZE / 2.0, Vector2.ONE * 1.0, "dead ahead: the middle")


func test_a_ship_behind_points_from_the_edge() -> void:
	var mark := ContactBrackets.place(camera, Vector3(0, 0, 10000), SIZE)
	assert_false(mark.on_screen, "behind the camera is never on screen")
	var right := ContactBrackets.place(camera, Vector3(5000, 0, 5000), SIZE)
	assert_false(right.on_screen)
	assert_almost_eq(right.position.x, SIZE.x - ContactBrackets.EDGE_MARGIN, 1.0, "behind and to the right: the right edge")
	assert_gt(cos(right.angle), 0.9, "pointing right")


func test_an_edge_arrow_stays_inside_the_screen() -> void:
	for p in [Vector3(-90000, 3000, -100), Vector3(0, 80000, -10), Vector3(100, -100, 9000)]:
		var mark := ContactBrackets.place(camera, p, SIZE)
		assert_between(mark.position.x, ContactBrackets.EDGE_MARGIN - 0.5, SIZE.x - ContactBrackets.EDGE_MARGIN + 0.5, str(p))
		assert_between(mark.position.y, ContactBrackets.EDGE_MARGIN - 0.5, SIZE.y - ContactBrackets.EDGE_MARGIN + 0.5, str(p))


func test_distance_reads_in_metres_then_kilometres() -> void:
	assert_eq(ContactBrackets.distance_text(850.0), "850 m")
	assert_eq(ContactBrackets.distance_text(12345.0), "12.3 km")
	assert_eq(ContactBrackets.distance_text(250000.0), "250 km")


func _world() -> Dictionary:
	var galaxy: Galaxy = preload("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)
	var ea := galaxy.factions.create("Earth Alliance")
	var b5 := galaxy.factions.create("Babylon 5", false, false, false, ea)
	var zeta := galaxy.factions.create("Zeta Wing", true, true, false, b5)
	var narn := galaxy.factions.create("Narn Regime")
	var system: System = preload("res://systems/system_template.tscn").instantiate()
	galaxy.zones.add_system(system)
	return {"galaxy": galaxy, "system": system, "ea": ea, "zeta": zeta, "narn": narn}


func _ship(w: Dictionary, faction: Faction, pilot := "") -> Ship:
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	(w.system as System).add_ship(ship)
	ship.faction_id = faction.faction_id
	if pilot:
		ship.spawn_crew(Character.pilot_data(pilot, faction.faction_id, 0, (w.galaxy as Galaxy).ids.next_pilot()))
	return ship


func test_sides_by_top_level_faction() -> void:
	var w := _world()
	var mine := _ship(w, w.zeta)
	assert_eq(ContactBrackets.side_of(_ship(w, w.ea), mine.faction), ContactBrackets.Side.OWN,
			"the side above my wing is my side")
	assert_eq(ContactBrackets.side_of(_ship(w, w.narn), mine.faction), ContactBrackets.Side.OTHER)
	assert_eq(ContactBrackets.side_of(_ship(w, w.narn), null), ContactBrackets.Side.OTHER, "no side of my own")


func test_every_other_ship_in_the_zone_is_a_contact() -> void:
	var w := _world()
	var mine := _ship(w, w.zeta)
	var other := _ship(w, w.zeta, "Alpha 2")
	var narn := _ship(w, w.narn)
	var contacts := ContactBrackets.contacts_in(w.system, mine)
	assert_eq(contacts.size(), 2, "not my own ship")
	assert_has(contacts, other)
	assert_has(contacts, narn)


func test_a_crewed_fighter_is_named_for_its_pilot() -> void:
	var w := _world()
	assert_eq(ContactBrackets.label_of(_ship(w, w.zeta, "Alpha 2")), "Alpha 2")
	var station: Ship = Content.instantiate(&"b5:hyperion")
	station.name = "EASS Hyperion"
	(w.system as System).add_ship(station)
	assert_eq(ContactBrackets.label_of(station), "EASS Hyperion")


func test_the_hud_layer_has_brackets() -> void:
	var w := _world()
	assert_not_null((w.galaxy as Galaxy).hud.get_node_or_null("ContactBrackets"))
