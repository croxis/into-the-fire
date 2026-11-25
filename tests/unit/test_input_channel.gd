extends GutTest
## InputChannel: a pilot's tick-stamped input, from their client to the server
## (netcode slice N3a). Packets are unreliable, so each repeats the last few
## inputs; the server checks everything and applies one input per tick, in order.

var client: InputChannel
var server: InputChannel


func before_each() -> void:
	client = InputChannel.new()
	server = InputChannel.new()


func _rec(tick: int, forward := -1.0) -> Dictionary:
	return InputChannel.make_record(tick, Vector3(0, 0, forward), Vector3.ZERO)


func test_packets_carry_the_latest_inputs_newest_last() -> void:
	var packet := []
	for tick in range(10, 16):
		packet = client.record(_rec(tick))
	assert_eq(packet.size(), InputChannel.REDUNDANCY)
	assert_eq(packet.map(func(r): return r.tick), [12, 13, 14, 15])


func test_the_server_applies_inputs_in_tick_order() -> void:
	server.receive(client.record(_rec(10, -0.1)))
	server.receive(client.record(_rec(11, -0.2)))
	server.receive(client.record(_rec(12, -0.3)))
	assert_eq(server.next().throttle, Vector3(0, 0, -0.1))
	assert_eq(server.last_applied_tick, 10)
	assert_eq(server.next().throttle, Vector3(0, 0, -0.2))
	assert_eq(server.last_applied_tick, 11)


func test_a_lost_packet_is_covered_by_the_next_one() -> void:
	server.receive(client.record(_rec(10)))
	client.record(_rec(11))  # This packet never arrives.
	server.receive(client.record(_rec(12)))  # But it repeats tick 11.
	assert_eq([server.next().tick, server.next().tick, server.next().tick], [10, 11, 12])


func test_repeated_and_old_inputs_are_ignored() -> void:
	client.record(_rec(10))
	var packet := client.record(_rec(11))
	server.receive(packet)
	server.receive(packet)  # Same packet twice.
	assert_eq(server.next().tick, 10)
	assert_eq(server.next().tick, 11)
	server.receive([_rec(9)])  # Older than what was applied.
	assert_eq(server.queued(), 0)


func test_with_no_new_input_the_last_one_holds() -> void:
	# A late packet must not cut the engines: keep the last throttle, but don't
	# repeat one-shot toggles or claim the tick was acknowledged.
	var toggled := InputChannel.make_record(10, Vector3(0, 0, -1), Vector3.ZERO, true, true)
	server.receive([toggled, _rec(11, -1.0)])
	server.next()
	server.next()
	var held := server.next()
	assert_eq(held.throttle, Vector3(0, 0, -1))
	assert_false(held.autospin_toggle)
	assert_false(held.autobreak_toggle)
	assert_eq(server.last_applied_tick, 11)


func test_before_any_input_the_pilot_holds_still() -> void:
	var nothing := server.next()
	assert_eq(nothing.throttle, Vector3.ZERO)
	assert_eq(server.last_applied_tick, -1)


# Untrusted packets ----------------------------------------------------------

func test_malformed_packets_are_refused() -> void:
	assert_ne(server.receive("hello"), "")
	assert_ne(server.receive([1, 2]), "")
	assert_ne(server.receive([{"tick": 1}]), "", "missing fields")
	var bad := _rec(1)
	bad.throttle = "fast"
	assert_ne(server.receive([bad]), "", "wrong type")
	assert_eq(server.queued(), 0)


func test_too_many_inputs_in_one_packet_are_refused() -> void:
	var packet := []
	for tick in InputChannel.REDUNDANCY + 1:
		packet.append(_rec(tick))
	assert_ne(server.receive(packet), "")


func test_out_of_range_input_is_clamped_and_nan_refused() -> void:
	server.receive([InputChannel.make_record(1, Vector3(0, 0, -50), Vector3(9, 0, 0)), _rec(2)])
	var applied := server.next()
	assert_eq(applied.throttle, Vector3(0, 0, -1))
	assert_eq(applied.rotation_throttle, Vector3(1, 0, 0))
	assert_ne(server.receive([InputChannel.make_record(3, Vector3(NAN, 0, 0), Vector3.ZERO)]), "")


func test_the_queue_has_a_limit() -> void:
	for tick in InputChannel.MAX_QUEUE + 10:
		server.receive([_rec(tick)])
	assert_eq(server.queued(), InputChannel.MAX_QUEUE, "oldest dropped, so a flood can't grow it")


# Where a character's input comes from ---------------------------------------

func test_input_source_for_every_case() -> void:
	var S := Character.InputSource
	# A remote player, seen on the server: their tick-stamped channel.
	assert_eq(Character.input_source(true, true, false), S.CHANNEL)
	# The pilot's own client: read locally, fly with it, and send it.
	assert_eq(Character.input_source(false, true, true), S.LOCAL_AND_SEND)
	# The host's own player, NPCs, and other players seen on a client: local values.
	assert_eq(Character.input_source(true, true, true), S.LOCAL)
	assert_eq(Character.input_source(true, false, false), S.LOCAL)
	assert_eq(Character.input_source(false, false, false), S.LOCAL)
	assert_eq(Character.input_source(false, true, false), S.LOCAL)


# Jitter buffer ----------------------------------------------------------------
# Packets arrive in clumps, not one per tick. If the server used inputs the
# moment they came, it would often find none and hold the last one for a step
# the client never made: a correction each time. It keeps a small cushion.

func test_the_server_waits_for_a_cushion_before_starting() -> void:
	server.receive([_rec(10)])
	assert_eq(server.last_applied_tick, -1, "one input isn't a cushion yet")
	server.next()
	assert_eq(server.last_applied_tick, -1)
	server.receive([_rec(10), _rec(11)])
	assert_eq(server.next().tick, 10)


func test_a_backlog_is_skipped_down_to_the_cushion() -> void:
	# A burst (say the client caught up after a stall) leaves inputs waiting;
	# applying one per tick would keep the server that far behind for good.
	var burst := []
	for tick in range(10, 20):
		burst.append(_rec(tick))
	for i in range(0, burst.size(), InputChannel.REDUNDANCY):
		server.receive(burst.slice(i, i + InputChannel.REDUNDANCY))
	server.next()
	assert_eq(server.queued(), InputChannel.JITTER_BUFFER, "back to the cushion")
	assert_gt(server.skipped_ticks, 0, "counted, since each skip is a correction")
	assert_eq(server.last_applied_tick, 19 - InputChannel.JITTER_BUFFER)


# Adaptive cushion -------------------------------------------------------------
# Each hold or skip is a one-tick jump on the pilot's screen (speed x 1/60 s).
# A jittery link runs dry often, so the cushion grows; a steady one shrinks it
# back, since every tick of cushion shows the ship that much later to others.

## Runs the server [param ticks] ticks, feeding it [param per] new inputs every
## [param per] ticks (so clumps of that size). Returns the next tick to feed.
func _feed(from_tick: int, ticks: int, per := 1) -> int:
	var tick := from_tick
	for i in ticks:
		if i % per == 0:
			var packet := []
			for j in per:
				packet.append(_rec(tick))
				tick += 1
			server.receive(packet)
		server.next()
	return tick


## Uses up every queued input, then one tick more: the server runs dry.
func _run_dry() -> void:
	while server.queued() > 0:
		server.next()
	server.next()


func test_running_dry_grows_the_cushion() -> void:
	server.receive([_rec(10), _rec(11)])
	server.next()
	server.next()
	server.next()  # Dry.
	assert_eq(server.cushion, InputChannel.JITTER_BUFFER + 1)
	server.receive([_rec(12), _rec(13)])
	server.next()
	assert_eq(server.last_applied_tick, 11, "waits for the bigger cushion")
	server.receive([_rec(14)])
	assert_eq(server.next().tick, 12)


func test_the_cushion_has_a_ceiling() -> void:
	var tick := 0
	for i in InputChannel.MAX_CUSHION + 5:
		var inputs := []  # Exactly a cushion's worth, so the server starts.
		for j in server.cushion:
			inputs.append(_rec(tick))
			tick += 1
		for k in range(0, inputs.size(), InputChannel.REDUNDANCY):
			server.receive(inputs.slice(k, k + InputChannel.REDUNDANCY))
		_run_dry()
	assert_eq(server.cushion, InputChannel.MAX_CUSHION)


func test_a_steady_link_shrinks_the_cushion_back() -> void:
	var tick := _feed(0, 4)
	_run_dry()  # Cushion 3.
	tick = _feed(tick, 10)
	var skipped := server.skipped_ticks
	_feed(tick, InputChannel.SHRINK_AFTER)
	assert_eq(server.cushion, InputChannel.JITTER_BUFFER)
	assert_eq(server.skipped_ticks, skipped + 1, "one input dropped to get there")


func test_a_clumpy_link_keeps_its_cushion() -> void:
	# Inputs in threes: the queue gets down to one before each clump, so one
	# tick less cushion would run dry.
	var tick := _feed(0, 4)
	_run_dry()  # Cushion 3.
	_feed(tick, InputChannel.SHRINK_AFTER * 2, 3)
	assert_eq(server.cushion, InputChannel.JITTER_BUFFER + 1)
	assert_eq(server.held_ticks, 1, "only the one dry spell")


func test_it_never_shrinks_below_the_minimum() -> void:
	_feed(0, InputChannel.SHRINK_AFTER * 2)
	assert_eq(server.cushion, InputChannel.JITTER_BUFFER)
	assert_eq(server.skipped_ticks, 0)


func test_running_dry_soon_after_a_shrink_makes_the_next_wait_longer() -> void:
	# Otherwise a link on the edge would bounce between two sizes, paying a
	# skip to shrink and a hold to grow back every few seconds.
	var tick := _feed(0, 4)
	_run_dry()  # Cushion 3.
	tick = _feed(tick, InputChannel.SHRINK_AFTER + 10)
	assert_eq(server.cushion, InputChannel.JITTER_BUFFER, "shrank")
	_run_dry()  # Too soon: back to 3, and the next shrink waits twice as long.
	assert_eq(server.shrink_after, InputChannel.SHRINK_AFTER * 2)
	tick = _feed(tick + 10, InputChannel.SHRINK_AFTER + 10)
	assert_eq(server.cushion, InputChannel.JITTER_BUFFER + 1, "still waiting")
	_feed(tick, InputChannel.SHRINK_AFTER)
	assert_eq(server.cushion, InputChannel.JITTER_BUFFER)


func test_the_wait_has_a_ceiling() -> void:
	var tick := 0
	for i in 10:
		tick = _feed(tick, 4)
		_run_dry()
		tick = _feed(tick + 10, server.shrink_after + 10)
	assert_eq(server.shrink_after, InputChannel.MAX_SHRINK_AFTER)


# Toggles survive skips ---------------------------------------------------------
# A skipped input still happened on the pilot's client: dropping its autospin or
# autobreak toggle would leave the server flying with the other setting for good.

func test_a_skipped_toggle_is_carried_to_the_next_input() -> void:
	var burst := []
	for tick in range(10, 20):
		burst.append(_rec(tick))
	burst[0] = InputChannel.make_record(10, Vector3.ZERO, Vector3.ZERO, true)  # Autospin pressed.
	for i in range(0, burst.size(), InputChannel.REDUNDANCY):
		server.receive(burst.slice(i, i + InputChannel.REDUNDANCY))
	var applied := server.next()  # Skips 10 and others to catch up.
	assert_gt(server.skipped_ticks, 0)
	assert_true(applied.autospin_toggle, "the toggle from tick 10 comes with it")
	assert_false(server.next().autospin_toggle, "once")


func test_two_skipped_toggles_cancel_out() -> void:
	var burst := []
	for tick in range(10, 20):
		burst.append(_rec(tick))
	burst[0] = InputChannel.make_record(10, Vector3.ZERO, Vector3.ZERO, false, true)
	burst[1] = InputChannel.make_record(11, Vector3.ZERO, Vector3.ZERO, false, true)
	for i in range(0, burst.size(), InputChannel.REDUNDANCY):
		server.receive(burst.slice(i, i + InputChannel.REDUNDANCY))
	assert_false(server.next().autobreak_toggle, "pressed twice: back as it was")


func test_a_toggle_dropped_by_a_flood_is_kept() -> void:
	server.receive([InputChannel.make_record(0, Vector3.ZERO, Vector3.ZERO, true)])
	for tick in range(1, InputChannel.MAX_QUEUE + 5):
		server.receive([_rec(tick)])
	assert_true(server.next().autospin_toggle)
