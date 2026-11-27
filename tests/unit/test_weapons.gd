extends GutTest
## Weapons netcode, slice W1: the trigger rides in the pilot's tick-stamped
## input, and guns fire on ticks, at most once per cooldown.

const Ticks := preload("res://tests/unit/ticks.gd")
const SystemScene := preload("res://systems/system_template.tscn")

var stepper: ZoneStepper


func before_each() -> void:
	stepper = ZoneStepper.new()
	add_child_autofree(stepper)


func _starfury() -> Ship:
	var system: System = SystemScene.instantiate()
	add_child_autofree(system)
	stepper.add_zone(system)
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(ship)
	return ship


func _weapons(ship: Ship) -> WeaponsCapability:
	return (ship.get_node("Consoles/Cockpit") as Console).get_capability(WeaponsCapability)


func _gun(ship: Ship) -> Gun:
	return ship.get_node("Guns").get_child(0) as Gun


func _remote_player_at_cockpit(ship: Ship) -> Character:
	var pilot: Character = ship.get_node("CrewMultiplayerSpawner").spawn(
			Character.pilot_data("Remote", 0, 99, 1))
	(ship.get_node("Consoles/Cockpit") as Console).occupy(pilot)
	pilot._player_pilot_id = 5
	return pilot


func test_the_trigger_survives_the_wire() -> void:
	var r := InputChannel.make_record(4, Vector3.ZERO, Vector3.ZERO, false, false, false, true)
	assert_true(r.fire_primary)
	var back: Array = InputChannel.decode(InputChannel.encode([r]))
	assert_true(back[0].fire_primary)
	assert_false(InputChannel.make_record(4, Vector3.ZERO, Vector3.ZERO).fire_primary, "off unless pressed")


func test_the_cockpit_weapons_reach_the_starfurys_guns() -> void:
	var ship := _starfury()
	assert_eq(_weapons(ship).system, ship.get_node("Guns"))


func test_a_gun_fires_once_per_cooldown() -> void:
	var gun := _gun(_starfury())
	var wait := gun.cooldown_ticks()
	assert_gt(wait, 0)
	assert_true(gun.fire_at(100))
	assert_false(gun.fire_at(101), "still cooling down")
	assert_false(gun.fire_at(100 + wait - 1))
	assert_true(gun.fire_at(100 + wait))


func test_a_remote_pilots_trigger_fires_the_guns_on_the_server() -> void:
	var ship := _starfury()
	var pilot := _remote_player_at_cockpit(ship)
	var gun := _gun(ship)
	watch_signals(gun)
	pilot.receive_inputs_from(99, [
			InputChannel.make_record(7, Vector3.ZERO, Vector3.ZERO, false, false, false, true),
			InputChannel.make_record(8, Vector3.ZERO, Vector3.ZERO, false, false, false, true)])
	await Ticks.run(1)
	assert_signal_emitted(gun, "fired")


func test_no_trigger_no_fire() -> void:
	var ship := _starfury()
	var pilot := _remote_player_at_cockpit(ship)
	var gun := _gun(ship)
	watch_signals(gun)
	pilot.receive_inputs_from(99, [InputChannel.make_record(7, Vector3.ZERO, Vector3.ZERO),
			InputChannel.make_record(8, Vector3.ZERO, Vector3.ZERO)])
	await Ticks.run(1)
	assert_signal_not_emitted(gun, "fired")
