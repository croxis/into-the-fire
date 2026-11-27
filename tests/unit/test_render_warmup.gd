extends GutTest
## The title screen's render warm-up (RenderWarmup) draws every ship once in
## the window, so a client's first look at a station doesn't cost a ~670 ms
## frame, and then gives the window back as it was.


func test_the_warmup_gives_the_window_back() -> void:
	var window := get_viewport()
	var world := window.world_3d
	var warmup := RenderWarmup.new()
	add_child_autofree(warmup)
	await wait_until(func() -> bool: return Content.ships_preloaded(), 30.0)
	watch_signals(warmup)
	await wait_for_signal(warmup.finished, 5.0)
	assert_signal_emitted(warmup, "finished")
	assert_eq(window.world_3d, world, "its own world again")
	await wait_physics_frames(1)
	assert_eq(warmup.get_child_count(), 0, "the copy of the system, the camera and the cover are gone")


func test_graphics_settings_apply_from_the_start() -> void:
	# Not only when a client joins: the warm-up must build pipelines for the
	# settings the game draws with (MSAA changes them all), and hosts never join.
	var window := get_viewport()
	var before := [window.msaa_3d, window.use_taa]
	window.msaa_3d = Viewport.MSAA_DISABLED
	window.use_taa = false
	var galaxy: Galaxy = preload("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)  # Reads the player's settings, whatever they are.
	assert_eq(window.msaa_3d, galaxy.msaa as Viewport.MSAA)
	assert_eq(window.use_taa, bool(galaxy.taa))
	window.msaa_3d = before[0]
	window.use_taa = before[1]
