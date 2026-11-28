class_name HudLayer
extends CanvasLayer
## The local player's HUD, drawn in the main window above the viewed zone.
##
## Zone SubViewports don't render (see ZoneView), so 2D UI placed inside a ship
## would never be seen. HUDs live here instead, created client-side and only for
## the local player. Each one belongs to where the player is:
## - passenger: aboard a capital ship or space station (Launch).
## - console: sitting at a console. The console's [member Console.hud_scene],
##   so a turret and a pilot seat can look different.
## In-world 3D displays, like Starfury cockpit screens, stay in the ship.
##
## Each HUD belongs to a node (its ship or console) and goes away when that node
## leaves the tree, so a destroyed ship never leaves its HUD behind.
##
## XR will show this layer on a panel in front of the view (not done yet).

const PassengerHudScene := preload("res://ui/capital/capital_ui.tscn")


## One HUD on screen and the node it belongs to.
class Slot:
	var hud: Control
	var owner: Node


var _passenger := Slot.new()
var _console := Slot.new()

## The passenger HUD on screen, or null.
var passenger: Control:
	get:
		return _passenger.hud
## The console HUD on screen, or null.
var console_hud: Control:
	get:
		return _console.hud


func _init() -> void:
	name = "HudLayer"
	layer = 1  # Below the join menu (Galaxy's CanvasLayer is 2).
	add_child(ContactBrackets.new())  # Every other ship in view, at any range.


## Shows the passenger HUD for [param ship]. Pressing Launch calls
## [param on_launch]. Replaces any passenger HUD already shown.
func show_passenger(ship: Node, on_launch: Callable) -> void:
	var hud: Control = PassengerHudScene.instantiate()
	hud.request_launch.connect(on_launch)
	_show(_passenger, ship, hud)


## Hides the passenger HUD if it belongs to [param ship].
func hide_passenger(ship: Node) -> void:
	_hide(_passenger, ship)


## Shows [param scene] as the HUD for [param console], replacing any console
## HUD. A null scene (a console without a HUD) just clears the old one. If the
## HUD's root has bind_console(console), it is called before it is shown.
func show_console(console: Node, scene: PackedScene) -> void:
	if scene == null:
		_clear(_console)
		return
	var hud: Control = scene.instantiate()
	if hud.has_method("bind_console"):
		hud.bind_console(console)
	_show(_console, console, hud)


## Hides the console HUD if it belongs to [param console].
func hide_console(console: Node) -> void:
	_hide(_console, console)


func _show(slot: Slot, owner_node: Node, hud: Control) -> void:
	_clear(slot)
	slot.hud = hud
	slot.owner = owner_node
	add_child(hud)
	owner_node.tree_exiting.connect(_clear.bind(slot), CONNECT_ONE_SHOT)


func _hide(slot: Slot, owner_node: Node) -> void:
	if owner_node == slot.owner:
		_clear(slot)


func _clear(slot: Slot) -> void:
	if slot.owner and is_instance_valid(slot.owner):
		var on_exit := _clear.bind(slot)
		if slot.owner.tree_exiting.is_connected(on_exit):
			slot.owner.tree_exiting.disconnect(on_exit)
	slot.owner = null
	if slot.hud:
		slot.hud.queue_free()
		slot.hud = null
