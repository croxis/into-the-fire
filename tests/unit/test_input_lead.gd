extends GutTest
## InputLead: the pilot's client steers how far ahead of server time it runs, so
## its inputs reach the server's queue just in time (time dilation). The server
## reports how many of its inputs are queued (after using one), and its
## cushion; the client keeps the queue one over the cushion, clear of running dry
## (a hold) and of a backlog skip, by changing its lead a little at a time.

const DT := 1.0 / 60.0

var lead: InputLead


func before_each() -> void:
	lead = InputLead.new(DT)


func _feed(queued: int, cushion: int, ticks: int) -> void:
	for i in ticks:
		lead.observe(queued, cushion, DT)


func test_a_short_queue_means_run_further_ahead() -> void:
	_feed(1, 3, 60)  # Wants 4.
	assert_gt(lead.lead_seconds, 0.0)


func test_a_long_queue_means_run_less_far_ahead() -> void:
	lead.lead_seconds = 0.2
	_feed(8, 3, 60)
	assert_lt(lead.lead_seconds, 0.2)


func test_at_the_target_the_lead_holds_still() -> void:
	lead.lead_seconds = 0.1
	_feed(3 + InputLead.MARGIN, 3, 120)
	assert_almost_eq(lead.lead_seconds, 0.1, 1e-6)


func test_the_lead_changes_slowly_enough_not_to_be_felt() -> void:
	# At most MAX_RATE seconds of lead per second: the client's ticks run at
	# most that much faster or slower than real time.
	_feed(0, 8, 60)  # As far from the target as it gets, for one second.
	assert_almost_eq(lead.lead_seconds, InputLead.MAX_RATE, 1e-6)
	assert_lt(InputLead.MAX_RATE, 0.03, "under 3% faster")


func test_jitter_in_the_reported_queue_is_smoothed() -> void:
	# Depths bouncing around the target barely move the lead.
	lead.lead_seconds = 0.1
	for i in 600:
		lead.observe(3 + InputLead.MARGIN + (1 if i % 2 == 0 else -1), 3, DT)
	assert_almost_eq(lead.lead_seconds, 0.1, 0.005)


func test_a_queue_deeper_than_needed_is_drained_by_running_behind() -> void:
	# The queue's depth with no lead is whatever it was when the server first
	# filled its cushion: often deeper than needed, each input 17 ms more delay.
	_feed(6, 2, 600)
	assert_lt(lead.lead_seconds, 0.0, "behind netfox's server time")


func test_the_lead_stays_within_bounds() -> void:
	_feed(8, 3, 60000)
	assert_eq(lead.lead_seconds, -InputLead.MAX_LEAD, "a flooded queue doesn't run it away")
	_feed(0, 8, 60000)
	assert_eq(lead.lead_seconds, InputLead.MAX_LEAD, "nor a stalled server")
