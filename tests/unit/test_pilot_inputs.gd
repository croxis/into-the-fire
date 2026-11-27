extends GutTest
## Pilots' inputs go to the Galaxy, which always exists, and the server finds
## the sender's pilot there. Sent to the pilot's Character node, inputs still
## in flight when its ship was destroyed (crew freed, the pilot respawned
## elsewhere) found no node: an engine error for each packet.

const Ticks := preload("res://tests/unit/ticks.gd")
const SystemScene := preload("res://systems/system_template.tscn")

var galaxy: Galaxy
var system: System


func before_each() -> void:
	galaxy = preload("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)
	system = SystemScene.instantiate()
	galaxy.get_node("Systems").add_child(system)


func _pilot(peer: int, player_id: int) -> Character:
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(ship)
	var pilot: Character = ship.get_node("CrewMultiplayerSpawner").spawn(
			Character.pilot_data("Remote %d" % peer, 0, peer, player_id))
	(ship.get_node("Consoles/Cockpit") as Console).occupy(pilot)
	pilot._player_pilot_id = player_id
	return pilot


func _packet(tick: int) -> PackedByteArray:
	return InputChannel.encode([InputChannel.make_record(tick, Vector3(0, 0, -1), Vector3.ZERO)])


func test_inputs_reach_the_senders_pilot() -> void:
	var mine := _pilot(99, 5)
	var theirs := _pilot(77, 6)
	assert_eq(galaxy.inputs_from(99, _packet(7)), "")
	assert_eq(mine.input_channel.queued(), 1)
	assert_eq(theirs.input_channel.queued(), 0, "only the sender's own pilot")


func test_inputs_from_a_peer_with_no_pilot_are_dropped() -> void:
	assert_eq(galaxy.inputs_from(55, _packet(7)), "no pilot", "not spawned yet")


func test_inputs_still_in_flight_when_the_pilot_dies_are_dropped() -> void:
	var pilot := _pilot(99, 5)
	pilot.get_parent().get_parent().free()  # Its ship destroyed, crew and all.
	assert_eq(galaxy.inputs_from(99, _packet(8)), "no pilot")


func test_a_rejoined_player_is_found_by_their_new_peer() -> void:
	var pilot := _pilot(99, 5)
	pilot.pilot_rejoined(123)
	assert_eq(galaxy.inputs_from(99, _packet(7)), "no pilot", "the old connection")
	assert_eq(galaxy.inputs_from(123, _packet(7)), "")
	assert_eq(pilot.input_channel.queued(), 1)
