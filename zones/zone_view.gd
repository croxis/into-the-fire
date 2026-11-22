class_name ZoneView
extends Node
## Draws the zone the local player is viewing in this node's window.
##
## Zones are SubViewports with their own World3D (design doc: zones). They are
## never put on screen themselves. Instead the window renders the zone's world
## directly: [method view] points the window's world_3d at it, and a camera rig
## in the window follows whichever camera is current inside the zone. Game code
## keeps choosing cameras in the zone (ship, console, RTS camera) as before.
##
## Why not show the SubViewport: a texture on screen breaks XR (the headset
## needs the main viewport), costs a second render target per zone, and hides
## the window's own HUD layers behind it.
##
## In XR the rig is an XROrigin3D placed at the zone camera, with an XRCamera3D
## that the headset moves relative to it.

## The zone being viewed, or null.
var zone: SubViewport

var _rig: Node3D  # A Camera3D (flat screen) or an XROrigin3D (XR).
var _rig_is_xr := false
var _window_world: World3D  # The window's own world, restored by clear().
var _saved_world := false


func _init() -> void:
	# Run after the zone's nodes, so the rig uses this frame's camera position.
	process_priority = 1000


## Shows [param new_zone] in this window.
func view(new_zone: SubViewport) -> void:
	var window := get_viewport()
	if not _saved_world:
		_window_world = window.world_3d
		_saved_world = true
	zone = new_zone
	# The window draws the zone now; rendering the SubViewport too would be wasted.
	zone.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# The window's camera hears the zone. A second listener would double every 3D sound.
	zone.audio_listener_enable_3d = false
	window.world_3d = zone.find_world_3d()
	follow()


## Stops viewing; the window gets its own world back.
func clear() -> void:
	if _rig:
		_rig.queue_free()
		remove_child(_rig)
		_rig = null
	zone = null
	if _saved_world:
		get_viewport().world_3d = _window_world
		_saved_world = false


## Moves the rig to the zone's current camera. Called every frame.
func follow() -> void:
	if zone == null:
		return
	_ensure_rig()
	_match_size()
	var source := zone.get_camera_3d()
	if source == null:
		return
	if _rig_is_xr:
		_rig.global_transform = source.global_transform
		var xr_camera := _rig.get_child(0) as XRCamera3D
		xr_camera.near = source.near
		xr_camera.far = source.far
	else:
		_copy_camera(source, _rig as Camera3D)


## Sends [param event] to the viewed zone, for zone nodes that read input
## events (the RTS camera). Ship controls poll Input and don't need this.
func forward(event: InputEvent) -> void:
	if zone:
		zone.push_input(event)


## The window's 3D render scale for a render resolution setting.
## A resolution of 0 means native.
static func render_scale(resolution: Vector2i, window_size: Vector2) -> float:
	if resolution.x <= 0 or window_size.x <= 0:
		return 1.0
	return clampf(resolution.x / window_size.x, 0.25, 2.0)


func _process(_delta: float) -> void:
	follow()


func _unhandled_input(event: InputEvent) -> void:
	# Only what the window's own UI didn't use reaches the zone.
	forward(event)


## Zone cameras project mouse positions with the zone's own size (RTS camera
## picking), so keep it equal to the window.
func _match_size() -> void:
	var size := Vector2i(get_viewport().get_visible_rect().size)
	if size.x > 0 and zone.size != size:
		zone.size = size


## Makes the rig match the window's mode (flat or XR), creating it if needed.
func _ensure_rig() -> void:
	var want_xr := get_viewport().use_xr
	if _rig and _rig_is_xr == want_xr:
		return
	if _rig:
		_rig.queue_free()
		remove_child(_rig)
	_rig_is_xr = want_xr
	if want_xr:
		var origin := XROrigin3D.new()
		origin.name = "XROrigin"
		var xr_camera := XRCamera3D.new()
		xr_camera.name = "XRCamera"
		origin.add_child(xr_camera)
		_rig = origin
		add_child(_rig)
		xr_camera.current = true
	else:
		var camera := Camera3D.new()
		camera.name = "ViewCamera"
		_rig = camera
		add_child(_rig)
		camera.current = true


static func _copy_camera(from: Camera3D, to: Camera3D) -> void:
	to.global_transform = from.global_transform
	to.projection = from.projection
	to.fov = from.fov
	to.size = from.size
	to.near = from.near
	to.far = from.far
	to.keep_aspect = from.keep_aspect
	to.h_offset = from.h_offset
	to.v_offset = from.v_offset
	to.cull_mask = from.cull_mask
	to.environment = from.environment
	to.attributes = from.attributes
