extends GutTest
## Interest tiers: how often the server sends a ship's snapshots to a client
## depends on how far that ship is from the ship the client's player is aboard:
## every tick pair (30 Hz) nearby, less often further out, so a crowded system
## costs less bandwidth. Clients draw a distant ship between sparser snapshots,
## and past the newest for a little, as for a lost one.

var interest: Interest


func before_each() -> void:
	interest = Interest.new()


func test_nearby_ships_go_at_full_rate_and_distant_ones_less_often() -> void:
	assert_eq(ShipSnapshots.interval_for(1000.0), ShipSnapshots.INTERVAL_TICKS, "1 km: 30 a second")
	assert_eq(ShipSnapshots.interval_for(10000.0), ShipSnapshots.MID_TICKS, "10 km")
	assert_eq(ShipSnapshots.interval_for(100000.0), ShipSnapshots.FAR_TICKS, "100 km")
	assert_lt(ShipSnapshots.INTERVAL_TICKS, ShipSnapshots.MID_TICKS)
	assert_lt(ShipSnapshots.MID_TICKS, ShipSnapshots.FAR_TICKS)
	assert_between(60.0 / ShipSnapshots.FAR_TICKS, 2.0, 5.0, "far: 2 to 5 a second, as designed")


func test_each_client_gets_its_own_pace() -> void:
	# The same ship near one player and far from another.
	var ship: Ship = autofree(Content.instantiate(&"b5:aurora_starfury"))
	var snapshots := ShipSnapshots.new(ship)
	var near_sends := 0
	var far_sends := 0
	for tick in range(0, 96, ShipSnapshots.INTERVAL_TICKS):
		if snapshots.due_for(7, tick, ShipSnapshots.INTERVAL_TICKS):
			near_sends += 1
		if snapshots.due_for(8, tick, ShipSnapshots.FAR_TICKS):
			far_sends += 1
	assert_eq(near_sends, 48)
	assert_eq(far_sends, 96 / ShipSnapshots.FAR_TICKS)


func test_interest_remembers_the_ship_each_player_is_aboard() -> void:
	# Distances are measured from there.
	var system := RefCounted.new()
	var aboard := RefCounted.new()
	interest.update({7: Interest.view(system, aboard, {})}, {aboard: system})
	assert_eq(interest.viewpoint(7), aboard)
	assert_null(interest.viewpoint(9), "unknown client")
	interest.update({7: null}, {aboard: system})
	assert_null(interest.viewpoint(7), "no character, no viewpoint")
