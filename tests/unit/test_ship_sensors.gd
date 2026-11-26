extends GutTest
## Ship sensor detection and the system's periodic sensor scan.

const ShipScene := preload("res://ships/Ship.tscn")
const SystemScene := preload("res://systems/system_template.tscn")
const Ticks := preload("res://tests/unit/ticks.gd")


func _ship(at: Vector3) -> Ship:
	var s: Ship = ShipScene.instantiate()
	s.sensor = Sensor.new()  # Sensitivity 1.0: detects signal 1.0 at 1 km.
	add_child_autofree(s)
	s.global_position = at
	return s


func test_detects_ship_in_range() -> void:
	var a := _ship(Vector3.ZERO)
	var b := _ship(Vector3(500, 0, 0))  # Signal 4.0 at 0.5 km.
	assert_true(a.sensor_check(b))
	assert_has(a.detected_ships, b)


func test_repeated_checks_do_not_duplicate_contacts() -> void:
	var a := _ship(Vector3.ZERO)
	var b := _ship(Vector3(500, 0, 0))
	a.sensor_check(b)
	a.sensor_check(b)
	a.sensor_check(b)
	assert_eq(a.detected_ships.size(), 1)


func test_contact_lost_when_out_of_range() -> void:
	var a := _ship(Vector3.ZERO)
	var b := _ship(Vector3(500, 0, 0))
	a.sensor_check(b)
	b.global_position = Vector3(5000, 0, 0)  # Signal 0.04 at 5 km.
	assert_false(a.sensor_check(b))
	assert_does_not_have(a.detected_ships, b)


func test_a_more_sensitive_sensor_sees_further() -> void:
	# Higher sensitivity is better: sensitivity S picks up signals down to 1/S.
	# A Starfury's EM 2.0 at 5 km is 0.08: under 1, over 1/20.
	var a := _ship(Vector3.ZERO)
	var b := _ship(Vector3(5000, 0, 0))
	b.em_output = 2.0
	b.neutron_output = 0.0
	assert_false(a.sensor_check(b), "sensitivity 1: needs a signal of 1")
	a.sensor.em_sensitive = 20.0
	assert_true(a.sensor_check(b), "sensitivity 20: 0.05 is enough")


func test_each_signature_is_checked_against_its_own_sensitivity() -> void:
	var a := _ship(Vector3.ZERO)
	var b := _ship(Vector3(5000, 0, 0))
	b.em_output = 0.0
	b.neutron_output = 2.0
	a.sensor.em_sensitive = 20.0
	assert_false(a.sensor_check(b), "no EM to see")
	a.sensor.neutrino_sensitive = 20.0
	assert_true(a.sensor_check(b))


func test_a_ship_without_sensors_sees_nothing() -> void:
	var a := _ship(Vector3.ZERO)
	var b := _ship(Vector3(10, 0, 0))
	a.sensor = null
	assert_false(a.sensor_check(b))
	a.sensor = Sensor.new()
	a.sensor.em_sensitive = 0.0
	a.sensor.neutrino_sensitive = 0.0
	assert_false(a.sensor_check(b), "sensitivity 0: blind")


func test_a_ship_emits_its_base_output_to_begin_with() -> void:
	# Power use will vary it later; until then a Starfury emits what its scene
	# says (EM 2, neutrino 0.1), not the default 1.0.
	var fury: Ship = Content.instantiate(&"b5:aurora_starfury")
	add_child_autofree(fury)
	assert_eq(fury.em_output, fury.em_output_base)
	assert_eq(fury.neutron_output, fury.neutron_output_base)
	assert_ne(fury.em_output, 1.0, "the Starfury's own value, not the default")


func test_a_starfury_sees_a_capital_ship_well_before_it_is_close() -> void:
	# Its sensor suite (sensitivity 100) picks up EM 1, a capital ship's, out to
	# 10 km: with sensitivity 1 it was 1 km, gone in a moment at fighter speed.
	var fury: Ship = Content.instantiate(&"b5:aurora_starfury")
	add_child_autofree(fury)
	var capital := _ship(Vector3(9000, 0, 0))
	assert_true(fury.sensor_check(capital), "9 km")
	capital.global_position = Vector3(11000, 0, 0)
	assert_false(fury.sensor_check(capital), "11 km")


## Drives: what a ship's engines give off with thrust (DriveProfile). Chemical
## (most factions, Earth Alliance and Narn too): EM. Gravitic (Centauri,
## Minbari): gravimetric. Esoteric (Shadows, Vorlons): neutrinos.

func _drive(em := 0.0, gravimetric := 0.0, neutrino := 0.0) -> DriveProfile:
	var d: DriveProfile = DriveProfile.new()
	d.em_per_meganewton = em
	d.gravimetric_per_meganewton = gravimetric
	d.neutrino_per_meganewton = neutrino
	return d


func test_ships_have_chemical_drives_by_default() -> void:
	var fury: Ship = Content.instantiate(&"b5:aurora_starfury")
	add_child_autofree(fury)
	assert_not_null(fury.drive)
	assert_gt(fury.drive.em_per_meganewton, 0.0, "chemical: EM with thrust")
	assert_eq(fury.drive.gravimetric_per_meganewton, 0.0)
	assert_eq(fury.drive.neutrino_per_meganewton, 0.0)


func test_todays_ships_give_off_no_neutrinos() -> void:
	# Neutrinos are for esoteric ships (Shadows, Vorlons), none of them yet.
	for id in [&"b5:aurora_starfury", &"b5:hyperion", &"b5:babylon_5"]:
		var s: Ship = Content.instantiate(id)
		add_child_autofree(s)
		assert_eq(s.neutron_output, 0.0, String(id))


func test_thrust_raises_what_the_drive_gives_off() -> void:
	var a := _ship(Vector3.ZERO)
	a.em_output_base = 2.0
	a.drive = _drive(0.8)
	assert_eq(a.emissions_for(0.0), Vector3(2.0, 0.0, 0.0), "idle: the base (EM, neutrino, gravimetric)")
	assert_almost_eq(a.emissions_for(5e6), Vector3(6.0, 0.0, 0.0), Vector3.ONE * 1e-9, "5 MN: 4 more EM")
	a.drive = _drive(0.0, 0.5)
	assert_almost_eq(a.emissions_for(4e6), Vector3(2.0, 0.0, 2.0), Vector3.ONE * 1e-9, "gravitic: gravimetric")
	a.drive = _drive(0.0, 0.0, 0.25)
	assert_almost_eq(a.emissions_for(4e6), Vector3(2.0, 1.0, 0.0), Vector3.ONE * 1e-9, "esoteric: neutrinos")


func test_a_burning_starfury_is_louder_than_a_coasting_one() -> void:
	var fury: Ship = Content.instantiate(&"b5:aurora_starfury")
	add_child_autofree(fury)
	var helm := (fury.get_node("Consoles/Cockpit") as Console).get_capability(HelmCapability)
	await Ticks.run(1)
	var coasting := fury.em_output
	helm.throttle = Vector3(0, 0, -1)
	await Ticks.run(1, 1)
	assert_gt(fury.em_output, coasting + 1.0, "full forward thrust")


func test_gravimetric_signatures_are_detected() -> void:
	var a := _ship(Vector3.ZERO)
	var b := _ship(Vector3(5000, 0, 0))
	b.em_output = 0.0
	b.neutron_output = 0.0
	b.gravimetric_output = 2.0
	a.sensor.visual_acuity_degrees = 0.0
	assert_false(a.sensor_check(b), "sensitivity 1: 0.08 isn't enough")
	a.sensor.gravametric_sensitive = 20.0
	assert_true(a.sensor_check(b))


## Visual detection: a ship is seen when it looks bigger than the sensor's
## visual acuity (degrees), whatever it emits.

func _silent_ball(at: Vector3, radius: float) -> Ship:
	var ship := _ship(at)
	ship.em_output = 0.0
	ship.neutron_output = 0.0
	var body := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = radius
	body.shape = ball
	ship.add_child(body)
	return ship


func test_a_ships_size_comes_from_its_own_collision_shapes() -> void:
	# Not the areas it carries (docks, escort range): only what it is made of.
	var ball := _silent_ball(Vector3.ZERO, 50.0)
	var dock := Area3D.new()
	var reach := CollisionShape3D.new()
	var big := SphereShape3D.new()
	big.radius = 500.0
	reach.shape = big
	dock.add_child(reach)
	ball.add_child(dock)
	assert_almost_eq(ball.visual_radius(), 50.0, 1e-6, "the 500 m area isn't counted")


func test_a_ship_is_seen_once_it_looks_big_enough() -> void:
	# Radius 50 m at 1 degree: seen out to 50 / tan(0.5 deg), about 5.7 km.
	var a := _ship(Vector3.ZERO)
	var b := _silent_ball(Vector3(5000, 0, 0), 50.0)
	assert_true(a.sensor_check(b), "5 km: over 1 degree")
	b.global_position = Vector3(6500, 0, 0)
	assert_false(a.sensor_check(b), "6.5 km: under")
	a.sensor.visual_acuity_degrees = 0.5
	assert_true(a.sensor_check(b), "sharper optics see further")
	a.sensor.visual_acuity_degrees = 0.0
	b.global_position = Vector3(10, 0, 0)
	assert_false(a.sensor_check(b), "acuity 0: no visual sensor")


func test_a_real_starfury_has_a_size() -> void:
	var fury: Ship = Content.instantiate(&"b5:aurora_starfury")
	add_child_autofree(fury)
	assert_between(fury.visual_radius(), 3.0, 30.0, "a fighter, metres across")


func test_system_sensor_scan_timer_runs_on_server() -> void:
	var system: System = SystemScene.instantiate()
	add_child_autofree(system)
	assert_true(system.ship_scan_timer.is_inside_tree(), "timer must be in the tree to fire")
	assert_false(system.ship_scan_timer.is_stopped(), "timer should be running")
