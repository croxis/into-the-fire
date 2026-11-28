extends GutTest
## Crew taking orders (server): an idle NPC scores the open objectives it can
## carry out and claims the best (utility); aboard a carrier with a patrol
## claimed it asks to launch, as a player would; at a fighter's helm it flies
## its patrol with its AI pilot. First pass: PATROL, for wing pilots.

var galaxy: Galaxy
var system: System
var b5: Faction
var zeta: Faction


func before_each() -> void:
	galaxy = preload("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)
	var ea := galaxy.factions.create("Earth Alliance")
	b5 = galaxy.factions.create("Babylon 5", false, false, false, ea)
	zeta = galaxy.factions.create("Zeta Wing", true, true, false, b5)
	system = preload("res://systems/system_template.tscn").instantiate()
	system.name = "epsilon"
	galaxy.zones.add_system(system)


func _carrier(x := 0.0) -> Ship:
	var hyperion: Ship = Content.instantiate(&"b5:hyperion")
	hyperion.ship_id = galaxy.ids.next_ship()
	system.add_ship(hyperion)
	hyperion.faction_id = b5.faction_id
	hyperion.position = Vector3(x, 0, 0)
	return hyperion


func _aboard(ship: Ship, pilot_name: String, faction: Faction) -> Character:
	return ship.spawn_crew(Character.pilot_data(pilot_name, faction.faction_id, 0, galaxy.ids.next_pilot()))


func _patrol(anchor: Ship, slots := 3) -> Objective:
	return CommanderPatrol.keep_patrol_posted(galaxy.state.objectives, 99, anchor, slots, 20000.0)


# Choosing ------------------------------------------------------------------

func test_a_wing_pilot_can_patrol_and_station_staff_cannot() -> void:
	var carrier := _carrier()
	var patrol := _patrol(carrier)
	assert_true(CrewOrders.can_do(_aboard(carrier, "Alpha 1", zeta), patrol))
	assert_false(CrewOrders.can_do(_aboard(carrier, "Ivanova", b5), patrol), "not a fighter pilot")


func test_utility_prefers_the_nearer_patrol() -> void:
	var here := _carrier(0)
	var far := _carrier(40000)
	var near_patrol := _patrol(here)
	var far_patrol := _patrol(far)
	var pilot := _aboard(here, "Alpha 1", zeta)
	assert_gt(CrewOrders.score(pilot, near_patrol, galaxy), CrewOrders.score(pilot, far_patrol, galaxy))
	assert_eq(CrewOrders.claim_best(pilot, galaxy), near_patrol)
	assert_has(near_patrol.claims, pilot.pilot_id)


func test_a_pilot_holds_one_claim_at_a_time() -> void:
	var carrier := _carrier()
	var first := _patrol(carrier)
	var pilot := _aboard(carrier, "Alpha 1", zeta)
	assert_eq(CrewOrders.claim_best(pilot, galaxy), first)
	assert_eq(CrewOrders.claim_best(pilot, galaxy), first, "keeps what it has")
	assert_eq(first.claims.size(), 1)


func test_nothing_to_claim_for_staff() -> void:
	var carrier := _carrier()
	_patrol(carrier)
	assert_null(CrewOrders.claim_best(_aboard(carrier, "Ivanova", b5), galaxy))


func test_utility_scores_from_curves() -> void:
	var near := UtilityConsideration.new()
	near.input = &"distance"
	near.curve = UtilityConsideration.falling(0.2)  # 1 at 0, 0.2 at the far end.
	assert_almost_eq(UtilityScorer.score([near], {"distance": 0.0}), 1.0, 0.01)
	assert_almost_eq(UtilityScorer.score([near], {"distance": 1.0}), 0.2, 0.01)
	assert_almost_eq(UtilityScorer.score([near], {"distance": 4.0}), 0.2, 0.01, "inputs clamp to 0..1")
	var weak := UtilityConsideration.new()
	weak.input = &"distance"
	weak.curve = UtilityConsideration.falling(0.0)
	weak.weight = 0.5
	assert_almost_eq(UtilityScorer.score([weak], {"distance": 1.0}), 0.5, 0.01, "a weight softens it")
	assert_almost_eq(UtilityScorer.score([near, near], {"distance": 1.0}), 0.04, 0.01, "multiplied")


# Launching -----------------------------------------------------------------

func test_an_npc_launches_like_a_player() -> void:
	var carrier := _carrier()
	var pilot := _aboard(carrier, "Alpha 1", zeta)
	var staff := _aboard(carrier, "Ivanova", b5)
	var pilot_id := pilot.pilot_id
	assert_eq(ShipLaunch.launch(carrier, pilot, galaxy.ids), "")
	assert_true(pilot.is_queued_for_deletion(), "the passenger leaves the carrier")
	assert_has(carrier.get_crew(), staff, "the right passenger: not anyone with player ID 0")
	var fighters := system.get_ships().filter(func(s: Ship) -> bool: return s != carrier)
	assert_eq(fighters.size(), 1)
	var seated: Character = fighters[0].get_crew()[0]
	assert_eq(seated.pilot_id, pilot_id, "the same pilot, at the fighter's controls")
	assert_not_null(seated.current_console)


func test_a_claimed_patrol_launches_the_pilot() -> void:
	var carrier := _carrier()
	_patrol(carrier)
	var pilot := _aboard(carrier, "Alpha 1", zeta)
	CrewOrders.claim_best(pilot, galaxy)
	assert_eq(CrewOrders.launch_for_orders(pilot, galaxy), "")
	assert_eq(system.get_ships().size(), 2, "a fighter is out")


func test_no_launch_without_orders() -> void:
	var carrier := _carrier()
	var pilot := _aboard(carrier, "Alpha 1", zeta)
	assert_ne(CrewOrders.launch_for_orders(pilot, galaxy), "")
	assert_eq(system.get_ships().size(), 1)


# Flying --------------------------------------------------------------------

func test_a_pilot_flies_its_patrol_round_the_anchor() -> void:
	var carrier := _carrier()
	var patrol := _patrol(carrier)
	var pilot := _aboard(carrier, "Alpha 1", zeta)
	CrewOrders.claim_best(pilot, galaxy)
	ShipLaunch.launch(carrier, pilot, galaxy.ids)
	var fighter: Ship = system.get_ships().filter(func(s: Ship) -> bool: return s != carrier)[0]
	var seated: Character = fighter.get_crew()[0]
	assert_true(CrewOrders.fly_orders(seated, galaxy))
	assert_true(seated.ai_pilot.has_orders())
	var first: Vector3 = PatrolRoute.from_anchor(carrier, patrol.params.route)[0]
	assert_almost_eq(seated.ai_pilot.current_target(), first, Vector3.ONE * 0.01, "the route, round the carrier")


func test_the_playtest_launches_three_zeta_pilots_on_patrol() -> void:
	# The whole first pass, without ticks: Babylon 5's commander posts a patrol
	# of 3; the three Zeta Wing pilots aboard claim it, launch and take their
	# fighters' helms with orders; the station's own staff stay aboard.
	var world: Galaxy = preload("res://Galaxy.tscn").instantiate()
	add_child_autofree(world)
	assert_true(world.start_new_world())
	for i in 20:
		await wait_physics_frames(30)  # The crew think once a second.
		if _patrol_fighters(world).size() >= 3:
			break
	var fighters := _patrol_fighters(world)
	assert_eq(fighters.size(), 3, "three fighters out")
	# Each new pilot's tree thinks a second after taking the helm.
	for i in 6:
		await wait_physics_frames(30)
		if fighters.all(func(f: Ship) -> bool: return f.get_crew()[0].ai_pilot.has_orders()):
			break
	var postings := world.state.objectives.issued_by(_commander_id(world))
	assert_eq(postings.size(), 1)
	if postings.size() == 1:
		assert_eq(postings[0].state, Objective.State.FILLED)
	for fighter in fighters:
		var pilot: Character = fighter.get_crew()[0]
		assert_eq(pilot.faction.resource_name, "Zeta Wing")
		assert_true(pilot.ai_pilot.has_orders(), "%s is flying the patrol" % pilot.name)
	var b5_ship: Ship = world.zones.systems()[0].get_ships().filter(
			func(s: Ship) -> bool: return s.name == &"Babylon 5")[0]
	var staff := b5_ship.get_crew().filter(func(c: Character) -> bool: return not c.is_queued_for_deletion())
	assert_eq(staff.size(), 2, "the commander and Lt Commendar Eekvonova stay aboard")


func _patrol_fighters(world: Galaxy) -> Array:
	var out := []
	for s in world.zones.systems()[0].get_ships():
		if not s.is_station and not s.is_capital and not s.get_crew().is_empty():
			out.append(s)
	return out


func _commander_id(world: Galaxy) -> int:
	for s in world.zones.systems()[0].get_ships():
		for c in s.get_crew():
			if c.current_console and c.current_console.get_capability(CommandCapability):
				return c.pilot_id
	return -1
