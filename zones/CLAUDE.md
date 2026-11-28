# zones/

Loaded when working in `zones/`. Project-wide rules are in the top-level `CLAUDE.md`.

## Known issue: Jolt job pool warning

"Jolt Physics job system exceeded the maximum number of jobs" appears once after a long stall (loading):
netfox then runs several ticks in one frame, and the stepping patch's `space_step` (used by `ZoneStepper`)
doesn't free Jolt's finished jobs (`JoltJobSystem::post_step`); only the engine's own step does. Jolt waits and
recovers, so it is left as is until a new symptom appears. Known symptom: `test_ship_flight.gd` and `test_rewind.gd`
run on their own fail on this warning (the full suite passes); the AI pilot's long test flights hit it in
the full suite, so they excuse exactly this warning (`Ticks.excuse_jolt_job_pool`; remove with the fix). The fix belongs in godot-custom's stepping patch (`patches/`): wrap the call in
`JoltPhysicsServer3D::space_step` with `job_system->pre_step()` / `job_system->post_step()`, as `step()` does.

## Render warm-up

`RenderWarmup` (`render_warmup.gd`, added by `entry.gd` on machines that render) draws each ship scene from
its own passenger camera for 2 frames, in the main window, under a black "Loading" cover, once Content has
loaded them. Without it a client's first look at a station cost a ~670 ms frame (the renderer building
pipelines: 19 surface, 8 draw, 14 specialisation), which also started the launch input stall. It only works
with the final graphics settings: MSAA changes every pipeline, so `DisplayManager._ready` applies the
player's settings (`apply`) before it runs. Startup gains about 0.8 s (one ~1 s frame, covered).
