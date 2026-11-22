extends GutTest
## ZoneView: the main window draws the viewed zone's world through a camera rig
## that follows the zone's active camera.
##
## A SubViewport stands in for the main window, so the test runner's own window
## is left alone.

var window: SubViewport
var zone: SubViewport
var zone_camera: Camera3D
var view: ZoneView


func before_each() -> void:
	window = SubViewport.new()
	window.size = Vector2i(640, 360)
	add_child_autofree(window)

	zone = SubViewport.new()
	zone.own_world_3d = true
	zone.audio_listener_enable_3d = true
	add_child_autofree(zone)
	zone_camera = _camera_in_zone(Vector3(100, 20, -5), 50.0)

	view = ZoneView.new()
	window.add_child(view)


func _camera_in_zone(at: Vector3, fov: float) -> Camera3D:
	var camera := Camera3D.new()
	zone.add_child(camera)
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.5, 0)), at)
	camera.fov = fov
	camera.near = 0.3
	camera.far = 30000.0
	camera.current = true
	return camera


func test_view_shows_the_zone_world() -> void:
	view.view(zone)
	assert_eq(window.world_3d, zone.find_world_3d())


func test_zone_matches_the_window_size() -> void:
	# Zone cameras project mouse rays (RTS camera) with the zone's size.
	view.view(zone)
	assert_eq(zone.size, window.size)
	window.size = Vector2i(800, 600)
	view.follow()
	assert_eq(zone.size, Vector2i(800, 600))


func test_zone_stops_rendering_and_listening() -> void:
	view.view(zone)
	assert_eq(zone.render_target_update_mode, SubViewport.UPDATE_DISABLED,
			"the main window draws it; rendering it again would be wasted")
	assert_false(zone.audio_listener_enable_3d, "otherwise 3D sounds play twice")


func test_rig_follows_the_zone_camera() -> void:
	view.view(zone)
	view.follow()
	var rig := window.get_camera_3d()
	assert_not_null(rig)
	assert_ne(rig, zone_camera, "the rig is the window's own camera")
	assert_true(rig.global_transform.is_equal_approx(zone_camera.global_transform))
	assert_eq(rig.fov, 50.0)
	assert_eq(rig.near, 0.3)
	assert_eq(rig.far, 30000.0)


func test_rig_follows_a_camera_switch() -> void:
	view.view(zone)
	var other := _camera_in_zone(Vector3(-40, 0, 0), 70.0)
	view.follow()
	assert_true(window.get_camera_3d().global_transform.is_equal_approx(other.global_transform))
	assert_eq(window.get_camera_3d().fov, 70.0)


func test_clear_gives_the_window_its_own_world_back() -> void:
	var own := window.find_world_3d()
	view.view(zone)
	view.clear()
	assert_eq(window.find_world_3d(), own)
	assert_null(view.zone)


func test_xr_uses_an_origin_at_the_zone_camera() -> void:
	window.use_xr = true
	view.view(zone)
	view.follow()
	var xr_camera := window.get_camera_3d()
	assert_true(xr_camera is XRCamera3D, "the headset drives the camera in XR")
	var origin := xr_camera.get_parent() as XROrigin3D
	assert_not_null(origin)
	assert_true(origin.global_transform.is_equal_approx(zone_camera.global_transform),
			"the player's head moves relative to the ship's camera position")


func test_input_is_forwarded_to_the_zone() -> void:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar got: Array = []\nfunc _unhandled_input(e): got.append(e)\n"
	script.reload()
	var listener := Node.new()
	listener.set_script(script)
	zone.add_child(listener)
	view.view(zone)

	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	view.forward(key)

	assert_eq(listener.got.size(), 1)


func test_render_scale() -> void:
	assert_eq(ZoneView.render_scale(Vector2i.ZERO, Vector2(1920, 1080)), 1.0, "0 means native")
	assert_eq(ZoneView.render_scale(Vector2i(960, 540), Vector2(1920, 1080)), 0.5)
	assert_eq(ZoneView.render_scale(Vector2i(100, 50), Vector2(1920, 1080)), 0.25, "clamped")
