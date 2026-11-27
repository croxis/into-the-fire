class_name RenderWarmup
extends Node
## Draws every ship scene once, in this window, while the title screen shows,
## so the renderer's first-use work happens then and not when a client first
## sees a station (a ~670 ms frame boarding Babylon 5, which used to start the
## launch input stall too: characters/CLAUDE.md).
##
## It has to be this window: render pipelines are built for the window's own
## render settings (its framebuffer formats, MSAA, scaling), so a separate
## viewport could build different ones. And each ship is drawn from its own
## passenger camera, the view a player boards into: from far away nothing is in
## range of the sun's shadows or the ships' own lights, and those passes need
## pipelines of their own. A loading cover hides it: the window really draws
## the ships those frames, and the first takes about a second. Machines that
## don't render (dedicated servers, tests) skip it (entry.gd).

signal finished

## Frames each ship is drawn for: the first builds most pipelines; the next
## pick up what that frame found it needed (shadows, specialisations).
const FRAMES_PER_SHIP := 2
## Ships are this far apart, so each view shows mostly its own ship.
const SPACING := 20000.0

var _zone: SubViewport
var _cover: CanvasLayer
var _camera: Camera3D
var _window_world: World3D
var _previous_camera: Camera3D
var _ships: Array[Node3D] = []
var _frame := -1


func _process(_delta: float) -> void:
	if _frame < 0:
		if Content.ships_preloaded():
			_begin()
		return
	_frame += 1
	if _frame >= _ships.size() * FRAMES_PER_SHIP:
		_end()
		return
	_look_at_ship(_ships[_frame / FRAMES_PER_SHIP])


func _begin() -> void:
	_frame = 0
	var window := get_viewport()
	_cover = _make_cover()
	add_child(_cover)
	_zone = Content.instantiate(&"b5:test_system") as SubViewport
	_zone.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_zone.audio_listener_enable_3d = false
	add_child(_zone)
	var ids := Content.registry.ids(&"ship")
	for i in ids.size():
		var ship := Content.instantiate(ids[i]) as Node3D
		ship.position = Vector3(i * SPACING, 0, 0)
		_zone.add_child(ship)
		_ships.append(ship)
	_window_world = window.world_3d
	_previous_camera = window.get_camera_3d()
	window.world_3d = _zone.find_world_3d()
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.make_current()
	_look_at_ship(_ships[0])
	Log.log(["Render warm-up: drawing ", ids.size(), " ships"], Log.MessageType.INFO)


## Puts the warm-up camera where [param ship]'s passenger camera is (a ship
## without one is looked at from 300 m off its nose).
func _look_at_ship(ship: Node3D) -> void:
	var view: Camera3D = ship.get("passenger_camera") as Camera3D
	if view:
		_camera.global_transform = view.global_transform
		_camera.fov = view.fov
	else:
		_camera.global_transform = Transform3D(Basis(), ship.global_position + Vector3(0, 0, -300)) \
				.looking_at(ship.global_position)
	_camera.near = 0.3
	_camera.far = 30000.0


func _end() -> void:
	var w0 := get_viewport()
	var window := get_viewport()
	window.world_3d = _window_world
	_camera.queue_free()
	if _previous_camera and is_instance_valid(_previous_camera):
		_previous_camera.make_current()
	_zone.queue_free()
	_cover.queue_free()
	set_process(false)
	Log.log(["Render warm-up done"], Log.MessageType.INFO)
	finished.emit()


## A black "Loading" screen over everything (the 3D is still drawn under it).
static func _make_cover() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 128
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(black)
	var label := Label.new()
	label.text = "Loading"
	label.set_anchors_preset(Control.PRESET_CENTER)
	layer.add_child(label)
	return layer
