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


func test_system_sensor_scan_timer_runs_on_server() -> void:
	var system: System = SystemScene.instantiate()
	add_child_autofree(system)
	assert_true(system.ship_scan_timer.is_inside_tree(), "timer must be in the tree to fire")
	assert_false(system.ship_scan_timer.is_stopped(), "timer should be running")
