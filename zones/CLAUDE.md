# zones/

Loaded when working in `zones/`. Project-wide rules are in the top-level `CLAUDE.md`.

## Known issue: Jolt job pool warning

"Jolt Physics job system exceeded the maximum number of jobs" appears once after a long stall (loading):
netfox then runs several ticks in one frame, and the stepping patch's `space_step` (used by `ZoneStepper`)
doesn't free Jolt's finished jobs (`JoltJobSystem::post_step`); only the engine's own step does. Jolt waits and
recovers, so it is left as is until a new symptom appears. Known symptom: `test_ship_flight.gd` and `test_rewind.gd`
run on their own fail on this warning (the full suite passes). The fix belongs in godot-ci's stepping patch: wrap the call in
`JoltPhysicsServer3D::space_step` with `job_system->pre_step()` / `job_system->post_step()`, as `step()` does.
