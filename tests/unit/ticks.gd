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


static func run(count: int, first_tick := 0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i in count:
		NetworkTime.before_tick.emit(DT, first_tick + i)
		NetworkTime.on_tick.emit(DT, first_tick + i)
		NetworkTime.after_tick.emit(DT, first_tick + i)
		await tree.physics_frame
