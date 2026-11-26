extends GutTest
## Ship sensor detection and the system's periodic sensor scan.

const ShipScene := preload("res://ships/Ship.tscn")
const SystemScene := preload("res://systems/system_template.tscn")


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


func test_system_sensor_scan_timer_runs_on_server() -> void:
	var system: System = SystemScene.instantiate()
	add_child_autofree(system)
	assert_true(system.ship_scan_timer.is_inside_tree(), "timer must be in the tree to fire")
	assert_false(system.ship_scan_timer.is_stopped(), "timer should be running")
