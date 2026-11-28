extends GutTest
## The commander's patrol: from the threat to its ship (0 for now), doctrine
## says how many fighters it wants out; it counts its side's fighters already
## out within the patrol radius and keeps one patrol posting with enough slots
## for the rest. In this pass it only ever adds fighters (no recall without
## docking).

var galaxy: Galaxy
var system: System
var b5: Faction
var zeta: Faction
var narn: Faction


func before_each() -> void:
	galaxy = preload("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)
	var ea := galaxy.factions.create("Earth Alliance")
	b5 = galaxy.factions.create("Babylon 5", false, false, false, ea)
	zeta = galaxy.factions.create("Zeta Wing", true, true, false, b5)
	narn = galaxy.factions.create("Narn Regime")
	system = preload("res://systems/system_template.tscn").instantiate()
	system.name = "epsilon"
	galaxy.zones.add_system(system)


func _ship(id: StringName, faction: Faction, x := 0.0, pilot := "") -> Ship:
	var ship: Ship = Content.instantiate(id)
	ship.ship_id = galaxy.ids.next_ship()
	system.add_ship(ship)
	ship.faction_id = faction.faction_id
	ship.position = Vector3(x, 0, 0)
	if pilot:
		ship.spawn_crew(Character.pilot_data(pilot, faction.faction_id, 0, galaxy.ids.next_pilot()))
	return ship


func _doctrine(minimum: int, per_threat := 0) -> FactionDoctrine:
	var d := FactionDoctrine.new()
	d.minimum_patrol_fighters = minimum
	d.fighters_per_threat = per_threat
	return d


func test_doctrine_says_how_many_fighters_to_want() -> void:
	assert_eq(CommanderPatrol.wanted_fighters(_doctrine(3), 0.0), 3, "at no threat, the minimum")
	assert_eq(CommanderPatrol.wanted_fighters(_doctrine(3, 2), 1.5), 6, "more with threat, rounded up")
	assert_eq(CommanderPatrol.wanted_fighters(null, 0.0), 0, "no doctrine, no patrol")


func test_no_threat_yet() -> void:
	var station := _ship(&"b5:hyperion", b5)
	assert_eq(ThreatAssessment.threat_to(station), 0.0, "threat assessment is a later pass")


func test_fighters_out_are_own_side_crewed_fighters_in_the_radius() -> void:
	var anchor := _ship(&"b5:hyperion", b5)
	anchor.is_capital = true
	var near := _ship(&"b5:aurora_starfury", zeta, 5000, "Alpha 1")
	_ship(&"b5:aurora_starfury", zeta, 25000, "Alpha 2")  # Too far out.
	_ship(&"b5:aurora_starfury", zeta, 3000)  # Nobody aboard.
	_ship(&"b5:aurora_starfury", narn, 4000, "Narn 1")  # Not our side.
	var other_capital := _ship(&"b5:hyperion", b5, 6000)
	other_capital.is_capital = true
	assert_eq(CommanderPatrol.fighters_out(anchor, 20000.0), [near])


func test_a_patrol_is_posted_for_the_fighters_missing() -> void:
	var anchor := _ship(&"b5:hyperion", b5)
	anchor.is_capital = true
	_ship(&"b5:aurora_starfury", zeta, 5000, "Alpha 1")
	var board := galaxy.state.objectives
	var posting := CommanderPatrol.keep_patrol_posted(board, 7, anchor, 3, 20000.0)
	assert_not_null(posting)
	assert_eq(posting.type, Objective.Type.PATROL)
	assert_eq(posting.audience, Objective.Audience.POSTED)
	assert_eq(posting.faction_id, b5.faction_id, "for the station's side and its wings")
	assert_eq(posting.issuer_id, 7)
	assert_eq(posting.slots, 2, "3 wanted, 1 already out")
	assert_eq(posting.params.anchor_ship_id, anchor.ship_id)
	assert_eq(posting.params.system, "epsilon")
	assert_eq(posting.params.route, PatrolRoute.pick(anchor, 20000.0), "the Hyperion's own route")
	assert_has(board.open_for(zeta, galaxy.factions), posting)


func test_the_commander_keeps_one_posting() -> void:
	var anchor := _ship(&"b5:hyperion", b5)
	var board := galaxy.state.objectives
	var first := CommanderPatrol.keep_patrol_posted(board, 7, anchor, 3, 20000.0)
	var again := CommanderPatrol.keep_patrol_posted(board, 7, anchor, 3, 20000.0)
	assert_eq(again, first)
	assert_eq(board.issued_by(7).size(), 1)


func test_claimed_slots_count_whether_or_not_their_fighters_are_out_yet() -> void:
	var anchor := _ship(&"b5:hyperion", b5)
	var board := galaxy.state.objectives
	var posting := CommanderPatrol.keep_patrol_posted(board, 7, anchor, 3, 20000.0)
	var pilot_id := galaxy.ids.next_pilot()
	board.claim(posting.id, pilot_id, zeta, galaxy.factions)
	# The claimant has launched and is out: still one of the three, not a fourth.
	var out := _ship(&"b5:aurora_starfury", zeta, 5000)
	out.spawn_crew(Character.pilot_data("Alpha 1", zeta.faction_id, 0, pilot_id))
	CommanderPatrol.keep_patrol_posted(board, 7, anchor, 3, 20000.0)
	assert_eq(posting.slots, 3)


func test_more_wanted_adds_slots_fewer_wanted_recalls_nobody() -> void:
	var anchor := _ship(&"b5:hyperion", b5)
	var board := galaxy.state.objectives
	var posting := CommanderPatrol.keep_patrol_posted(board, 7, anchor, 3, 20000.0)
	CommanderPatrol.keep_patrol_posted(board, 7, anchor, 5, 20000.0)
	assert_eq(posting.slots, 5)
	CommanderPatrol.keep_patrol_posted(board, 7, anchor, 1, 20000.0)
	assert_eq(posting.slots, 5, "only adds in this pass")
	assert_false(posting.is_closed())


func test_nothing_is_posted_when_enough_are_out() -> void:
	var anchor := _ship(&"b5:hyperion", b5)
	_ship(&"b5:aurora_starfury", zeta, 5000, "Alpha 1")
	assert_null(CommanderPatrol.keep_patrol_posted(galaxy.state.objectives, 7, anchor, 1, 20000.0))
	assert_eq(galaxy.state.objectives.size(), 0)


func test_the_babylon_5_commander_posts_a_patrol_from_the_playtest() -> void:
	# The whole chain: the scenario seats Commendar Eclair at StationCommand, its
	# Command capability runs the commander tree, and the tree posts a patrol of
	# 3 on Babylon 5's own Inner route.
	var world: Galaxy = preload("res://Galaxy.tscn").instantiate()
	add_child_autofree(world)
	assert_true(world.start_new_world())
	await wait_physics_frames(3)
	var postings := world.state.objectives.open_for(world.factions.find_by_name("Zeta Wing"), world.factions)
	assert_eq(postings.size(), 1, "one patrol posting")
	if postings.is_empty():
		return
	var patrol := postings[0]
	assert_eq(patrol.type, Objective.Type.PATROL)
	assert_eq(patrol.slots, 3, "3 fighters at no threat")
	assert_eq(patrol.params.route.size(), 5, "Babylon 5's Inner route")
	await wait_physics_frames(3)
	assert_eq(world.state.objectives.size(), 1, "still one, a second later or not")
