extends GutTest
## SnapshotClock: a client's estimate of the server's tick from when snapshots
## arrive, and the moment remote ships are drawn at, a little behind it
## (netcode slice N4c).

var clock: SnapshotClock


func before_each() -> void:
	clock = SnapshotClock.new()


func test_nothing_to_go_on_before_the_first_snapshot() -> void:
	assert_false(clock.has_estimate())


func test_the_first_snapshot_sets_the_clock() -> void:
	# Server tick 541 arrives when this client's own tick is 514 (it runs behind).
	clock.observe(541, 514.0)
	assert_true(clock.has_estimate())
	assert_almost_eq(clock.server_tick(514.0), 541.0, 1e-9)
	assert_almost_eq(clock.server_tick(520.5), 547.5, 1e-9, "and runs on with this client's ticks")
	assert_almost_eq(clock.render_tick(514.0), 541.0 - SnapshotClock.DELAY_TICKS, 1e-9)


func test_jitter_averages_out_and_the_drawn_moment_only_moves_forward() -> void:
	# Snapshots every 2 ticks, each arriving up to 0.9 ticks early or late (they
	# still arrive in order: the channel is ordered). Frames are drawn at every
	# quarter tick in between.
	var jitter: Array[float] = [0.0, 0.9, -0.6, 0.3, -0.9, 0.6, 0.0, -0.3]
	var last_drawn := -INF
	for i in 300:
		var tick := 100 + 2 * i
		clock.observe(tick, tick - 27.0 + jitter[i % jitter.size()])
		for quarter in 8:
			var frame: float = tick - 27.0 + 0.95 + quarter * 0.25  # After this arrival, before the next.
			var drawn := clock.render_tick(frame)
			assert_gt(drawn, last_drawn, "never back in time")
			last_drawn = drawn
	assert_almost_eq(clock.server_tick(1000.0), 1027.0, 0.5, "near the average arrival")


func test_a_big_jump_resets_the_clock() -> void:
	# netfox can recalibrate a client's tick in one go; follow at once.
	clock.observe(541, 514.0)
	clock.observe(543, 1516.0)
	assert_almost_eq(clock.server_tick(1516.0), 543.0, 1e-9)
