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
	var packet := client.record(_rec(10))
	server.receive(packet)
	server.receive(packet)  # Same packet twice.
	assert_eq(server.next().tick, 10)
	server.receive([_rec(9)])  # Older than what was applied.
	assert_eq(server.queued(), 0)


func test_with_no_new_input_the_last_one_holds() -> void:
	# A late packet must not cut the engines: keep the last throttle, but don't
	# repeat one-shot toggles or claim the tick was acknowledged.
	var toggled := InputChannel.make_record(10, Vector3(0, 0, -1), Vector3.ZERO, true, true)
	server.receive([toggled])
	server.next()
	var held := server.next()
	assert_eq(held.throttle, Vector3(0, 0, -1))
	assert_false(held.autospin_toggle)
	assert_false(held.autobreak_toggle)
	assert_eq(server.last_applied_tick, 10)


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
	server.receive([InputChannel.make_record(1, Vector3(0, 0, -50), Vector3(9, 0, 0))])
	var applied := server.next()
	assert_eq(applied.throttle, Vector3(0, 0, -1))
	assert_eq(applied.rotation_throttle, Vector3(1, 0, 0))
	assert_ne(server.receive([InputChannel.make_record(2, Vector3(NAN, 0, 0), Vector3.ZERO)]), "")


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
