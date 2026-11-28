extends GutTest
## ObjectiveBoard: how orders pass from an issuer (a commander, NPC or player)
## to the characters below it. An objective is posted, with slots any eligible
## character may claim (filled once every slot is claimed), or assigned to one
## character. World data: the board lives in WorldState. Pilots are known by
## pilot ID, factions by faction ID, so the board needs no nodes.

var registry: FactionRegistry
var board: ObjectiveBoard
var b5: Faction
var zeta: Faction
var narn: Faction

const COMMANDER := 1  # Pilot IDs.
const ALPHA_1 := 11
const ALPHA_2 := 12
const ALPHA_3 := 13
const NARN_PILOT := 21


func before_each() -> void:
	registry = FactionRegistry.new()
	var ea := registry.create("Earth Alliance")
	b5 = registry.create("Babylon 5", false, false, false, ea)
	zeta = registry.create("Zeta Wing", true, true, false, b5)
	narn = registry.create("Narn Regime")
	board = ObjectiveBoard.new(WorldIds.new())


func _patrol(slots := 2) -> Objective:
	return board.post(Objective.Type.PATROL, COMMANDER, b5.faction_id, slots,
			{"route": [Vector3(1000, 0, 0), Vector3(0, 0, 1000)]}, "Patrol near Babylon 5")


func test_a_posting_is_open_to_its_side_and_the_wings_below_it() -> void:
	var patrol := _patrol()
	assert_eq(patrol.state, Objective.State.OPEN)
	assert_has(board.open_for(zeta, registry), patrol, "a wing under Babylon 5")
	assert_has(board.open_for(b5, registry), patrol)
	assert_does_not_have(board.open_for(narn, registry), patrol, "another side")
	assert_does_not_have(board.open_for(registry.find_by_name("Earth Alliance"), registry), patrol,
			"not the side above the issuer's")


func test_claims_fill_a_posting_and_releases_reopen_it() -> void:
	var patrol := _patrol(2)
	assert_eq(board.claim(patrol.id, ALPHA_1, zeta, registry), "")
	assert_eq(patrol.state, Objective.State.OPEN, "one slot left")
	assert_eq(board.claim(patrol.id, ALPHA_2, zeta, registry), "")
	assert_eq(patrol.state, Objective.State.FILLED)
	assert_does_not_have(board.open_for(zeta, registry), patrol, "nothing left to claim")
	assert_ne(board.claim(patrol.id, ALPHA_3, zeta, registry), "", "no slot for a third")
	board.release(patrol.id, ALPHA_1)
	assert_eq(patrol.state, Objective.State.OPEN, "a slot again")
	assert_eq(patrol.claims, [ALPHA_2])


func test_claims_are_checked() -> void:
	var patrol := _patrol()
	assert_ne(board.claim(patrol.id, NARN_PILOT, narn, registry), "", "not their side")
	assert_eq(board.claim(patrol.id, ALPHA_1, zeta, registry), "")
	assert_ne(board.claim(patrol.id, ALPHA_1, zeta, registry), "", "already claimed")
	assert_ne(board.claim(9999, ALPHA_1, zeta, registry), "", "no such objective")


func test_an_assignment_is_for_its_assignee_only() -> void:
	var order := board.assign(Objective.Type.PATROL, COMMANDER, ALPHA_3, b5.faction_id,
			{"route": [Vector3.ZERO]}, "Fly this route")
	assert_eq(board.assigned_to(ALPHA_3), [order])
	assert_does_not_have(board.open_for(zeta, registry), order, "not a posting")
	assert_ne(board.claim(order.id, ALPHA_1, zeta, registry), "", "someone else")
	assert_eq(board.claim(order.id, ALPHA_3, zeta, registry), "")
	assert_eq(order.state, Objective.State.FILLED)


func test_what_a_pilot_has_claimed() -> void:
	var first := _patrol(3)
	var second := _patrol(3)
	board.claim(first.id, ALPHA_1, zeta, registry)
	board.claim(second.id, ALPHA_1, zeta, registry)
	assert_eq(board.claimed_by(ALPHA_1), [first, second])
	board.release_all(ALPHA_1)  # E.g. the pilot died.
	assert_eq(board.claimed_by(ALPHA_1), [])


func test_completed_and_cancelled_objectives_take_no_claims() -> void:
	var done := _patrol()
	board.complete(done.id)
	assert_eq(done.state, Objective.State.COMPLETED)
	var dropped := _patrol()
	board.cancel(dropped.id)
	assert_eq(dropped.state, Objective.State.CANCELLED)
	for o in [done, dropped]:
		assert_ne(board.claim(o.id, ALPHA_1, zeta, registry), "")
		assert_does_not_have(board.open_for(zeta, registry), o)


func test_objectives_expire() -> void:
	var patrol := _patrol()
	patrol.expires_tick = 100
	board.expire(99)
	assert_eq(patrol.state, Objective.State.OPEN)
	board.expire(100)
	assert_eq(patrol.state, Objective.State.EXPIRED)


func test_an_issuer_sees_what_it_issued() -> void:
	var patrol := _patrol()
	board.post(Objective.Type.PATROL, 2, b5.faction_id, 1, {}, "Someone else's")
	assert_eq(board.issued_by(COMMANDER), [patrol])


func test_changes_are_announced() -> void:
	# For what comes later: replication to players, the commander noticing a
	# posting filled, saves.
	watch_signals(board)
	var patrol := _patrol()
	assert_signal_emitted_with_parameters(board, "changed", [patrol])
	board.claim(patrol.id, ALPHA_1, zeta, registry)
	assert_signal_emit_count(board, "changed", 2)


func test_ids_come_from_the_world() -> void:
	var ids := WorldIds.new()
	var a := ObjectiveBoard.new(ids)
	var b := ObjectiveBoard.new(ids)
	var first := a.post(Objective.Type.PATROL, COMMANDER, b5.faction_id, 1, {}, "")
	var second := b.post(Objective.Type.PATROL, COMMANDER, b5.faction_id, 1, {}, "")
	assert_ne(first.id, second.id, "never reused within a world")
	assert_eq(first.id, 1)


func test_the_world_state_holds_a_board() -> void:
	var state := WorldState.new()
	assert_not_null(state.objectives)
	var o := state.objectives.post(Objective.Type.PATROL, COMMANDER, 2, 1, {}, "")
	assert_eq(o.id, 1, "from the world's own IDs")


func test_a_new_id_counter_reaches_the_board() -> void:
	# WorldBuilder gives a new world a fresh WorldIds.
	var state := WorldState.new()
	state.ids = WorldIds.new()
	assert_eq(state.objectives.ids, state.ids)
