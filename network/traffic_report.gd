class_name TrafficReport
extends RefCounted
## What this machine sends and receives over ENet, logged every
## REPORT_SECONDS (Network._process): bytes and packets a second, and each
## peer's round-trip time and packet loss. Measured before deciding whether
## the game needs its own replication layer. Bytes are ENet's, before DTLS
## adds its own (about 30 a packet).

const REPORT_SECONDS := 5.0

var _elapsed := 0.0


## Adds [param delta] seconds; once REPORT_SECONDS have passed, returns a
## report of [param peer]'s traffic since the last one (and starts counting
## again), else "". [param ids] are the peers to report on
## (multiplayer.get_peers(): every client on a server, 1 on a client).
func tick(peer: ENetMultiplayerPeer, delta: float, ids: Array = [1]) -> String:
	_elapsed += delta
	if _elapsed < REPORT_SECONDS or peer.host == null:
		return ""
	var seconds := _elapsed
	_elapsed = 0.0
	var peers: Array[Dictionary] = []
	for id: int in ids:
		var p := peer.get_peer(id)
		if p and p.get_state() == ENetPacketPeer.STATE_CONNECTED:
			peers.append({
				"id": id,
				"rtt_ms": p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
				"loss": p.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / ENetPacketPeer.PACKET_LOSS_SCALE,
			})
	var host := peer.host
	return describe(host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA),
			host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS),
			host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA),
			host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS), seconds, peers)


## The report line for totals over [param seconds]; [param peers] are
## {"id", "rtt_ms", "loss" (0 to 1)}. With more than one peer (a server) it
## also gives what it sends each, on average.
static func describe(sent_bytes: float, sent_packets: float, received_bytes: float,
		received_packets: float, seconds: float, peers: Array[Dictionary]) -> String:
	var line := "Traffic: sent %.1f kB/s (%d packets/s), received %.1f kB/s (%d packets/s)" % [
			sent_bytes / 1000.0 / seconds, roundi(sent_packets / seconds),
			received_bytes / 1000.0 / seconds, roundi(received_packets / seconds)]
	if peers.size() > 1:
		line += ", %.1f kB/s per peer" % (sent_bytes / 1000.0 / seconds / peers.size())
	for p in peers:
		line += "; peer %d: %d ms, %.1f%% loss" % [p["id"], roundi(p["rtt_ms"]), p["loss"] * 100.0]
	return line

