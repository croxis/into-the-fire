extends GutTest
## A long frame on a client (boarding a ship, loading) delays handling a time
## sync reply: that sample's round trip looks like the whole frame and its
## offset is off by about half of it. netfox weighted it the most, so one stall
## pulled the client's tick clock away for seconds (12% slow, then fast): the
## server's input queue ran dry, then flooded. Samples far slower than the
## best are left out (ITF patch in addons/netfox/network-time-synchronizer.gd).

const Synchronizer := preload("res://addons/netfox/network-time-synchronizer.gd")


func _sample(rtt: float, offset: float) -> NetworkClockSample:
	# The delay split evenly each way; the server [param offset] ahead.
	var s := NetworkClockSample.new()
	s.ping_sent = 100.0
	s.ping_received = 100.0 + rtt / 2.0 + offset
	s.pong_sent = s.ping_received
	s.pong_received = 100.0 + rtt
	return s


## A reply that arrived at once but was handled only after a [param frame]
## second frame on the client.
func _stalled_sample(frame: float) -> NetworkClockSample:
	var s := NetworkClockSample.new()
	s.ping_sent = 100.0
	s.ping_received = 100.003
	s.pong_sent = s.ping_received
	s.pong_received = 100.006 + frame
	return s


func _disciplined(samples: Array[NetworkClockSample]) -> float:
	var sync: Node = Synchronizer.new()
	add_child_autofree(sync)
	sync._sample_buffer = _RingBuffer.new(8)
	for s in samples:
		sync._sample_buffer.push(s)
	var before: float = sync.get_time()
	sync._discipline_clock()
	return sync.get_time() - before  # How far the clock was moved.


func test_good_samples_leave_an_agreeing_clock_alone() -> void:
	var good: Array[NetworkClockSample] = []
	for i in 8:
		good.append(_sample(0.006, 0.0))
	assert_almost_eq(_disciplined(good), 0.0, 0.001)


func test_a_sample_from_a_stalled_frame_is_left_out() -> void:
	var samples: Array[NetworkClockSample] = []
	for i in 7:
		samples.append(_sample(0.006, 0.0))
	samples.append(_stalled_sample(0.667))  # The reply waited out a 667 ms frame.
	assert_lt(samples[7].get_offset(), -0.3, "on its own it says the clock is 330 ms off")
	assert_almost_eq(_disciplined(samples), 0.0, 0.002, "the clock stays put")


func test_ordinary_jitter_is_kept() -> void:
	# 75 ms each way, give or take 15: every sample counts.
	var samples: Array[NetworkClockSample] = []
	for rtt in [0.12, 0.13, 0.14, 0.15, 0.16, 0.17, 0.18, 0.15]:
		samples.append(_sample(rtt, 0.02))
	assert_gt(_disciplined(samples), 0.0005, "a real 20 ms offset still moves it")
