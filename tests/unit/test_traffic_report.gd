extends GutTest
## TrafficReport: what a machine sends and receives, every 5 s, to measure
## before building a replication layer.

const PORT := 2299


func test_describes_rates_per_second() -> void:
	var line := TrafficReport.describe(50000, 500, 10000, 300, 5.0, [])
	assert_string_contains(line, "sent 10.0 kB/s (100 packets/s)")
	assert_string_contains(line, "received 2.0 kB/s (60 packets/s)")


func test_describes_each_peer() -> void:
	var peers: Array[Dictionary] = [{"id": 7, "rtt_ms": 52.0, "loss": 0.015}]
	var line := TrafficReport.describe(0, 0, 0, 0, 5.0, peers)
	assert_string_contains(line, "peer 7: 52 ms, 1.5% loss")


func test_a_server_reports_its_average_per_client() -> void:
	var peers: Array[Dictionary] = [{"id": 2, "rtt_ms": 1.0, "loss": 0.0}, {"id": 3, "rtt_ms": 1.0, "loss": 0.0}]
	assert_string_contains(TrafficReport.describe(100000, 0, 0, 0, 5.0, peers), "10.0 kB/s per peer")


func test_reports_only_every_five_seconds() -> void:
	var report := TrafficReport.new()
	var server := ENetMultiplayerPeer.new()
	server.create_server(PORT, 2)
	assert_eq(report.tick(server, 4.0, []), "")
	assert_ne(report.tick(server, 1.0, []), "", "due after 5 s")
	assert_eq(report.tick(server, 1.0, []), "", "and then not for another 5")
	server.close()


func test_counts_what_was_really_sent() -> void:
	var report := TrafficReport.new()
	var server := ENetMultiplayerPeer.new()
	server.create_server(PORT + 1, 2)
	var client := ENetMultiplayerPeer.new()
	client.create_client("127.0.0.1", PORT + 1)
	for i in 120:
		server.poll()
		client.poll()
		if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		await wait_physics_frames(1)
	var data := PackedByteArray()
	data.resize(1000)
	client.set_target_peer(1)
	for i in 50:  # 50 kB, so 10 kB/s over the 5 s report.
		client.put_packet(data)
	client.poll()
	var line := report.tick(client, TrafficReport.REPORT_SECONDS)
	var sent := line.get_slice("sent ", 1).to_float()
	assert_between(sent, 10.0, 11.0, "50 kB, plus ENet's headers and the handshake: " + line)
	assert_string_contains(line, "peer 1:", "a client reports the server")
	client.close()
	server.close()
