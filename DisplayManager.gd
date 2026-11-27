extends Node
## The player's graphics settings for the main window, which draws the viewed
## zone (ZoneView); zone SubViewports don't render, so they need none. Kept out
## of Galaxy: a world holds no rendering state (dedicated servers are headless).
## The one owner of these settings: the main menu changes them here.

## Render resolution setting; 0 means native (ZoneView.render_scale).
var render_resolution := Vector2i(0, 0)
var msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var taa := false


func _ready() -> void:
	# From the start, not only once a client joins: the title screen's render
	# warm-up (RenderWarmup) must build the pipelines for the settings the game
	# will draw with (MSAA changes them all), and a host never joins.
	msaa = PlayerConfig.get_config("graphics", "msaa", 0)
	taa = bool(PlayerConfig.get_config("graphics", "taa", 0))
	get_window().size_changed.connect(apply)  # The render scale follows the window.
	apply()


## Puts the settings on the main window.
func apply() -> void:
	var window := get_viewport()
	window.msaa_3d = msaa
	window.use_taa = taa
	window.scaling_3d_scale = ZoneView.render_scale(render_resolution, window.get_visible_rect().size)


func set_resolution(resolution: Vector2i) -> void:
	print_debug("DisplayManager: Setting render resolution: ", resolution)
	var interface = XRServer.find_interface("OpenXR")
	if interface and interface.is_initialized():
		return

	# If x is 0, use screen native
	if resolution.x == 0:
		resolution = DisplayServer.screen_get_size()

	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(resolution)

	get_viewport().size = resolution
	get_window().content_scale_size = Vector2i(0, 0)
	render_resolution = resolution
	apply()


func _on_main_menu_set_msaa(status: int) -> void:
	msaa = status as Viewport.MSAA
	apply()


func _on_main_menu_set_taa(status: bool) -> void:
	taa = status
	apply()
