extends GutTest
## Weapons netcode, slice W4: favour the shooter. A player's client says how
## far behind its own tick it was showing other ships; the server checks that
## player's shots against where targets were then (capped at 250 ms).

const Ticks := preload("res://tests/unit/ticks.gd")
const SystemScene := preload("res://systems/system_template.tscn")

var stepper: ZoneStepper
var system: System


func before_each() -> void:
	stepper = ZoneStepper.new()
	add_child_autofree(stepper)
	system = SystemScene.instantiate()
	add_child_autofree(system)
	stepper.add_zone(system)


func _starfury(at: Vector3) -> Ship:
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(ship)
	ship.place(Transform3D(Basis(), at))  # Into physics now: a set position reaches it next frame.
	return ship


func _record(tick: int, view_ticks: int, fire := true) -> Dictionary:
	return InputChannel.make_record(tick, Vector3.ZERO, Vector3.ZERO, false, false, false, fire, view_ticks)


func test_the_view_delay_survives_the_wire() -> void:
	var back: Array = InputChannel.decode(InputChannel.encode([_record(5, 11)]))
	assert_eq(back[0].view_ticks, 11)


func test_a_view_delay_out_of_range_is_clamped() -> void:
	var bad := _record(1, 0)
	bad.view_ticks = 9000
	assert_eq(InputChannel._check(bad).view_ticks, 255)
	bad.view_ticks = -4
	assert_eq(InputChannel._check(bad).view_ticks, 0)
	bad.view_ticks = "soon"
	assert_eq(InputChannel._check(bad), {}, "not a number: refused")


func test_the_rewind_is_from_the_servers_tick_to_what_the_shooter_saw() -> void:
	# Applied at server tick 10, input from client tick 7, which was showing
	# other ships 5 ticks behind itself (server tick 2): 8 ticks back.
	assert_eq(system.shots.rewind_for(10, 7, 5), 8)
	assert_eq(system.shots.rewind_for(100, 90, 60), 15, "capped at 250 ms by default")
	assert_eq(system.shots.rewind_for(10, 12, 0), 0, "never forward")


func test_a_remote_pilots_shot_carries_its_rewind() -> void:
	var ship := _starfury(Vector3.ZERO)
	var pilot: Character = ship.get_node("CrewMultiplayerSpawner").spawn(Character.pilot_data("Remote", 0, 99, 1))
	(ship.get_node("Consoles/Cockpit") as Console).occupy(pilot)
	pilot._player_pilot_id = 5
	pilot.receive_inputs_from(99, [_record(7, 5), _record(8, 5)])
	await Ticks.run(1, 10)
	assert_eq(system.shots.count(), ship.get_node("Guns").get_child_count())
	assert_eq(system.shots.all()[0].rewind_ticks, system.shots.rewind_for(10, 7, 5))


func test_a_rewound_shot_hits_where_the_target_was() -> void:
	var target := _starfury(Vector3(0, 0, -100))
	await Ticks.run(5, 1)  # Ticks 1-5: the target sits in the line of fire.
	target.place(Transform3D(Basis(), Vector3(500, 0, -100)))
	await Ticks.run(10, 6)  # Ticks 6-15: it has moved away.
	var health := target.health
	var shot := Shot.new(Vector3(0, 0, -60), Vector3(0, 0, -3000), 15, 20.0)
	shot.rewind_ticks = 12  # The shooter saw tick 3-4: the target still there.
	system.shots.add(shot)
	await Ticks.run(3, 16)
	assert_lt(target.health, health, "hit where the shooter saw it")


func test_without_rewind_the_same_shot_misses() -> void:
	var target := _starfury(Vector3(0, 0, -100))
	await Ticks.run(5, 1)
	target.place(Transform3D(Basis(), Vector3(500, 0, -100)))
	await Ticks.run(10, 6)
	var health := target.health
	system.shots.add(Shot.new(Vector3(0, 0, -60), Vector3(0, 0, -3000), 15, 20.0))
	await Ticks.run(3, 16)
	assert_eq(target.health, health, "the target isn't there any more")


func test_a_rewound_shot_misses_where_the_target_was_not() -> void:
	var target := _starfury(Vector3(500, 0, -100))
	await Ticks.run(5, 1)  # The target was away when the shooter saw it...
	target.place(Transform3D(Basis(), Vector3(0, 0, -100)))
	await Ticks.run(10, 6)  # ...and is in the line of fire only now.
	var health := target.health
	var shot := Shot.new(Vector3(0, 0, -60), Vector3(0, 0, -3000), 15, 20.0)
	shot.rewind_ticks = 12
	system.shots.add(shot)
	await Ticks.run(3, 16)
	assert_eq(target.health, health, "the shooter couldn't have aimed at it there")


func test_a_rewound_wide_bolt_hits_beside_its_line() -> void:
	var target := _starfury(Vector3(0, 0, -100))
	var beside := target.visual_radius() + 2.0
	await Ticks.run(5, 1)
	target.place(Transform3D(Basis(), Vector3(500, 0, -100)))
	await Ticks.run(10, 6)
	var health := target.health
	var shot := Shot.new(Vector3(beside, 0, -60), Vector3(0, 0, -3000), 15, 20.0)
	shot.radius = beside + target.visual_radius()
	shot.rewind_ticks = 12
	system.shots.add(shot)
	await Ticks.run(3, 16)
	assert_lt(target.health, health, "its size counts where the shooter saw the target too")


func test_the_rewind_cap_is_the_servers_to_set() -> void:
	assert_eq(ShotField.ticks_for_ms(250), 15)
	assert_eq(ShotField.ticks_for_ms(400), 24)
	system.shots.max_rewind_ticks = 24
	assert_eq(system.shots.rewind_for(100, 90, 60), 24)


func test_a_longer_cap_keeps_enough_history() -> void:
	system.shots.max_rewind_ticks = 30
	var target := _starfury(Vector3(0, 0, -100))
	await Ticks.run(5, 1)  # Ticks 1-5: in the line of fire.
	target.place(Transform3D(Basis(), Vector3(500, 0, -100)))
	await Ticks.run(25, 6)  # Ticks 6-30: moved away.
	var health := target.health
	var shot := Shot.new(Vector3(0, 0, -60), Vector3(0, 0, -3000), 30, 20.0)
	shot.rewind_ticks = 27  # The shooter saw tick 3-4.
	system.shots.add(shot)
	await Ticks.run(3, 31)
	assert_lt(target.health, health, "hit where the shooter saw it, 27 ticks back")


func test_servers_can_set_the_rewind_cap() -> void:
	var options := LaunchOptions.parse(PackedStringArray(["--server", "--max-rewind=400"]))
	assert_eq(options.max_rewind_ms, 400)
	assert_eq(LaunchOptions.parse(PackedStringArray(["--server"])).max_rewind_ms, 250, "250 ms by default")
	var bad := LaunchOptions.parse(PackedStringArray(["--server", "--max-rewind=soon"]))
	assert_eq(bad.max_rewind_ms, 250)
	assert_true("--max-rewind=soon" in bad.unknown)
	assert_true("--max-rewind=5000" in LaunchOptions.parse(PackedStringArray(["--server", "--max-rewind=5000"])).unknown,
			"over a second is refused")


func test_galaxy_gives_its_systems_the_cap() -> void:
	var galaxy: Galaxy = preload("res://Galaxy.tscn").instantiate()
	galaxy.max_rewind_ticks = 24
	add_child_autofree(galaxy)
	var other: System = SystemScene.instantiate()
	galaxy.get_node("Systems").add_child(other)
	assert_eq(other.shots.max_rewind_ticks, 24)


func test_a_destroyed_ship_leaves_the_history() -> void:
	var ship := _starfury(Vector3(0, 0, -100))
	system.shots.record_history(1)
	assert_true(system.shots._history.size() > 0)
	ship.free()  # Destroyed in a fight.
	system.shots.record_history(2)
	assert_eq(system.shots._history.size(), 0, "forgotten, without errors")
