extends Control
## A stand-in console HUD for tests: remembers the console it was bound to.

var console: Node


func bind_console(c: Node) -> void:
	console = c


## A scene whose root is one of these.
static func scene() -> PackedScene:
	var root := Control.new()
	root.set_script(load("res://tests/unit/fake_console_hud.gd"))
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed
