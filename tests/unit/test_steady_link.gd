extends GutTest
## ENet's packet throttle is congestion control for bulk traffic: after one
## round trip spikes (a client's long frame boarding a ship, the host spawning
## something) it drops a share of unreliable packets on purpose and recovers
## over seconds. Our streams are small and carry their own redundancy, so it
## only cost pilots inputs: holds, then skips, at every launch. Links are kept
## steady: the throttle never slows.

const Network := preload("res://network/network.gd")


func test_a_steady_link_never_throttles() -> void:
	var server := ENetConnection.new()
	server.create_host_bound("127.0.0.1", 2274)
	var client := ENetConnection.new()
	client.create_host()
	var to_server := client.connect_to_host("127.0.0.1", 2274)
	Network.steady(to_server)
	assert_eq(to_server.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_DECELERATION), 0.0, "never slows")
	assert_eq(to_server.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_ACCELERATION),
			float(ENetPacketPeer.PACKET_THROTTLE_SCALE), "back to full at once")
	client.destroy()
	server.destroy()
