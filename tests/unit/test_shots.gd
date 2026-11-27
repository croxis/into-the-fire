extends GutTest
## Weapons netcode, slice W2: shots fly on ticks in a straight line, and the
## server checks each tick's stretch of their path against hulls.

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


func _gun(ship: Ship) -> Gun:
	return ship.get_node("Guns").get_child(0) as Gun


func test_a_shot_flies_in_a_straight_line_on_ticks() -> void:
	var shot := Shot.new(Vector3(1, 2, 3), Vector3(0, 0, -600), 100, 20.0)
	assert_eq(shot.position_at(100), Vector3(1, 2, 3))
	assert_almost_eq(shot.position_at(160), Vector3(1, 2, -597), Vector3.ONE * 1e-6, "600 m/s for a second")
	assert_almost_eq(shot.position_at(130.5), Vector3(1, 2, -302), Vector3.ONE * 1e-6, "between ticks too")


func test_a_gun_fires_a_shot_forward_from_its_muzzle() -> void:
	var ship := _starfury(Vector3.ZERO)
	ship.linear_velocity = Vector3(0, 0, -100)
	var gun := _gun(ship)
	gun.fire_at(10)
	assert_eq(system.shots.count(), 1)
	var shot: Shot = system.shots.all()[0]
	assert_eq(shot.origin, gun.global_position)
	var forward := -ship.global_basis.z  # The ship's forward: its pilot camera looks along -z.
	assert_almost_eq(shot.velocity.normalized(), (forward * gun.speed + ship.linear_velocity).normalized(),
			Vector3.ONE * 1e-3, "out of the ship's nose, keeping the ship's own velocity")
	assert_eq(shot.shooter, ship)


func test_a_shot_hits_a_ship_in_its_path() -> void:
	var shooter := _starfury(Vector3.ZERO)
	var target := _starfury(Vector3(_gun(shooter).global_position.x, _gun(shooter).global_position.y, -300))
	var gun := _gun(shooter)
	gun.speed = 3000.0  # 50 m a tick: there in about 6 ticks.
	var health := target.health
	await Ticks.run(1)  # Let the physics space know both hulls.
	gun.fire_at(1)
	await Ticks.run(12, 2)
	assert_lt(target.health, health, "hit")
	assert_eq(system.shots.count(), 0, "a shot that hits is gone")


func test_a_shot_never_hits_its_own_ship() -> void:
	var shooter := _starfury(Vector3.ZERO)
	var health := shooter.health
	await Ticks.run(1)
	_gun(shooter).fire_at(1)
	await Ticks.run(5, 2)
	assert_eq(shooter.health, health)
	assert_eq(system.shots.count(), 1, "still flying")


func test_a_shot_expires() -> void:
	var shot := Shot.new(Vector3.ZERO, Vector3(0, 0, -10), 0, 20.0)
	system.shots.add(shot)
	system.shots.step(Shot.LIFETIME_TICKS - 1)
	assert_eq(system.shots.count(), 1)
	system.shots.step(Shot.LIFETIME_TICKS)
	assert_eq(system.shots.count(), 0)


func test_damage_falls_off_with_time_in_flight() -> void:
	var shot := Shot.new(Vector3.ZERO, Vector3.ZERO, 0, 20.0)
	assert_eq(shot.damage_at(0), 20.0)
	assert_lt(shot.damage_at(300), 20.0, "as the old bolts did: damage / (1 + 0.2 x seconds)")
	assert_almost_eq(shot.damage_at(300), 20.0 / 2.0, 1e-6)


func test_only_the_server_decides_hits() -> void:
	var field := ShotField.new(system, false)  # A client's: draws shots, never hits.
	var shooter := _starfury(Vector3.ZERO)
	var target := _starfury(Vector3(0, 0, -100))
	var health := target.health
	field.add(Shot.new(Vector3(0, 0, -50), Vector3(0, 0, -3000), 0, 20.0, shooter))
	await Ticks.run(1)
	field.step(1)
	field.step(2)
	assert_eq(target.health, health)
