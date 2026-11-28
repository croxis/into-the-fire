extends RefCounted
## Runs netfox ticks by hand, so a test decides exactly how many happen.
##
## The game simulates on NetworkTime's signals (netcode slice N2): characters
## hand input to helms in before_tick, ships fly in on_tick, ZoneStepper steps
## zone physics in after_tick. NetworkTime itself isn't running in tests.
##
## A physics frame passes after each tick, as in the game: the engine's own
## physics step is what frees Jolt's finished jobs (the stepping patch's
## space_step doesn't), so many ticks in a row would fill Jolt's job pool.

const DT := 1.0 / 60.0


##
## [param per_frame] ticks between physics frames: more makes long flights
## quicker to test (as when a game frame runs several ticks); keep it small,
## since Jolt's jobs are only freed by the engine's own step.
static func run(count: int, first_tick := 0, per_frame := 1) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i in count:
		NetworkTime.before_tick.emit(DT, first_tick + i)
		NetworkTime.on_tick.emit(DT, first_tick + i)
		NetworkTime.after_tick.emit(DT, first_tick + i)
		if (i + 1) % per_frame == 0 or i == count - 1:
			await tree.physics_frame


## Marks the known Jolt job pool warning (zones/CLAUDE.md) handled among
## [param errors] (GutTest.get_errors()), and nothing else. Long flights run by
## hand fill the pool, since the stepping patch's space_step doesn't free
## finished jobs; Jolt waits and goes on. Remove once godot-custom's patch
## frees them.
static func excuse_jolt_job_pool(errors: Array) -> void:
	for e in errors:
		if str(e.code).contains("Jolt Physics job system exceeded the maximum number of jobs"):
			e.handled = true
