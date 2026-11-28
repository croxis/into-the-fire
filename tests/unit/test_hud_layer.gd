extends GutTest
## HudLayer: the local player's HUD, drawn in the main window (zone slice 1b).
##
## A plain Node stands in for the ship: the layer only needs to know when the
## ship leaves the tree, and the launch request goes through a Callable.

var hud: HudLayer
var ship: Node
var launches := 0


func before_each() -> void:
	launches = 0
	hud = HudLayer.new()
	add_child_autofree(hud)
	ship = Node.new()
	add_child_autofree(ship)


func _launch() -> void:
	launches += 1


func _launch_button() -> Button:
	return hud.passenger.find_child("Launch", true, false) as Button


## The HUDs on screen: not the contact brackets, which are always there.
func _huds() -> Array:
	return hud.get_children().filter(func(c: Node) -> bool: return not c is ContactBrackets)


func test_starts_empty() -> void:
	assert_null(hud.passenger)
	assert_eq(_huds().size(), 0)


func test_show_passenger_adds_the_passenger_hud() -> void:
	hud.show_passenger(ship, _launch)
	assert_not_null(hud.passenger)
	assert_eq(hud.passenger.get_parent(), hud)
	assert_not_null(_launch_button())


func test_launch_button_requests_a_launch() -> void:
	hud.show_passenger(ship, _launch)
	_launch_button().pressed.emit()
	assert_eq(launches, 1)


func test_showing_again_replaces_the_hud() -> void:
	hud.show_passenger(ship, _launch)
	var other := Node.new()
	add_child_autofree(other)
	hud.show_passenger(other, _launch)
	await wait_process_frames(1)  # The old HUD is freed with queue_free.
	assert_eq(_huds().size(), 1)
	_launch_button().pressed.emit()
	assert_eq(launches, 1, "only the new HUD is connected")


func test_hide_passenger_removes_the_hud() -> void:
	hud.show_passenger(ship, _launch)
	hud.hide_passenger(ship)
	assert_null(hud.passenger)
	await wait_process_frames(1)
	assert_eq(_huds().size(), 0)


func test_hide_for_another_ship_keeps_the_hud() -> void:
	# A late "disable" from a ship the player already left must not hide the
	# HUD of the ship they are on now.
	hud.show_passenger(ship, _launch)
	var other := Node.new()
	add_child_autofree(other)
	hud.hide_passenger(other)
	assert_not_null(hud.passenger)


func test_ship_leaving_the_tree_removes_the_hud() -> void:
	hud.show_passenger(ship, _launch)
	remove_child(ship)
	assert_null(hud.passenger)
	ship.free()


# Console HUDs: one per console, shown while the local player sits there.

const FakeConsoleHud := preload("res://tests/unit/fake_console_hud.gd")


func console_hud_scene() -> PackedScene:
	return FakeConsoleHud.scene()


func test_show_console_adds_the_console_hud() -> void:
	hud.show_console(ship, console_hud_scene())
	assert_not_null(hud.console_hud)
	assert_eq(hud.console_hud.get_parent(), hud)
	assert_eq(hud.console_hud.console, ship, "the HUD is told which console it shows")


func test_console_without_a_hud_clears_the_old_one() -> void:
	# Moving from a console with a HUD to one without must not leave the old HUD up.
	hud.show_console(ship, console_hud_scene())
	var other := Node.new()
	add_child_autofree(other)
	hud.show_console(other, null)
	assert_null(hud.console_hud)


func test_hide_console_only_for_its_console() -> void:
	hud.show_console(ship, console_hud_scene())
	var other := Node.new()
	add_child_autofree(other)
	hud.hide_console(other)
	assert_not_null(hud.console_hud)
	hud.hide_console(ship)
	assert_null(hud.console_hud)


func test_console_leaving_the_tree_removes_its_hud() -> void:
	hud.show_console(ship, console_hud_scene())
	remove_child(ship)
	assert_null(hud.console_hud)
	ship.free()


func test_passenger_and_console_huds_are_independent() -> void:
	hud.show_passenger(ship, _launch)
	var console := Node.new()
	add_child_autofree(console)
	hud.show_console(console, console_hud_scene())
	hud.hide_console(console)
	assert_not_null(hud.passenger)
