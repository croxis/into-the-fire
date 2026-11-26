extends GutTest
## Babylon 5's rotating section turns with time, not frame by frame: its angle
## is worked out from the server tick, so the server and every client show the
## same angle for the same moment (a client at the moment it draws the station).
## Accumulated each frame on each machine, and synced once a second, the angles
## drifted apart, and a ship held by a launch arm was shown off its arm.

const DT := 1.0 / 60.0

## The rotation script (no class_name), loaded at run time rather than preloaded.
var ROTATION: Script


func before_all() -> void:
	ROTATION = load("res://ships/earth alliance/babylon 5/rotation.gd")


func test_the_angle_is_a_function_of_server_time() -> void:
	var a: float = ROTATION.angle_at(0.3, 0.75, 1234.5, DT)
	var b: float = ROTATION.angle_at(0.3, 0.75, 1234.5, DT)
	assert_eq(a, b, "the same tick, the same angle, on any machine")
	assert_almost_eq(ROTATION.angle_at(0.3, 0.75, 0.0, DT), 0.3, 1e-9, "where the scene puts it at tick 0")


func test_it_turns_at_its_rpm() -> void:
	# 0.75 turns a minute: once round in 80 s, 4800 ticks.
	var start: float = ROTATION.angle_at(0.0, 0.75, 0.0, DT)
	var quarter: float = ROTATION.angle_at(0.0, 0.75, 1200.0, DT)
	assert_almost_eq(absf(angle_difference(start, quarter)), PI / 2.0, 1e-6)
	var round_trip: float = ROTATION.angle_at(0.0, 0.75, 4800.0, DT)
	assert_almost_eq(angle_difference(start, round_trip), 0.0, 1e-6)


func test_the_angle_is_no_longer_synced() -> void:
	# Worked out from time on each machine: sending it would only snap it.
	var station: Node = autofree(Content.instantiate(&"b5:babylon_5"))
	var sync: MultiplayerSynchronizer = station.get_node("rotation/MultiplayerSynchronizer")
	var config := sync.replication_config
	for path in config.get_properties():
		assert_ne(String(path), ".:rotation")
	assert_true(config.has_property(NodePath(".:rpm")), "its speed still is")
	assert_true(config.property_get_spawn(NodePath(".:rpm")))
	assert_eq(config.property_get_replication_mode(NodePath(".:rpm")), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
