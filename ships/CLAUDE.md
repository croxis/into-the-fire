# ships/

Loaded when working in `ships/`. Project-wide rules are in the top-level `CLAUDE.md`.

## Flight

`Ship.gd` (RigidBody3D), `Engines.gd` (per-thruster forces), `crew.gd`, `PID.gd`. `FlightIntegrator`
(`flight_integrator.gd`) is ship motion without nodes: ships set `custom_integrator` and take their
velocities from it each tick (`Ship._fly`), using Jolt's mass and inertia; Jolt still moves them and handles
contacts. Stations keep Jolt's own integration. It clamps to Jolt's speed limits
(`physics/jolt_physics_3d/limits/*`), so replays match Jolt.

## Own-ship prediction

Our own reconciler, not netfox rollback. The pilot's input reaches the server through `InputChannel`
(see `characters/CLAUDE.md`).

- The pilot's client flies its ship at once and records its thrust (`ShipPrediction`).
- After each tick loop the server sends that client its ship's state and the last input tick it applied
  (`Ship._send_pilot_state`).
- The client replays its thrust since then.
- It eases a correction of its position in over about 100 ms (`CorrectionSmoother`); rotation, velocity and
  jumps over 100 m snap, since thrust follows the way the ship points.
- Corrections go through `Ship.place`, which sets the transform in Jolt directly: Godot only sends a node's new
  transform to physics at the start of the next physics frame, after our ticks have stepped the zone.
- While the server holds the ship frozen (a launch arm), its state says so and the client freezes the ship too
  and follows it exactly, still recording thrust for the replay after release.
- The shared ship sync goes through `sync_*` proxies that the predicting client ignores. The host never predicts.
- Logs: client "Prediction for X: N corrections" every 5 s.
- Not done yet: the replay records thrust, not input, so flight assist (autospin, autobreak: thrust from the
  current spin or speed) brings about a round trip of small corrections after each one (a pending test);
  under lag the client logs "SYS_COMMAND_AUTH" errors while joining (game packets arrive before
  its login finishes), and a late `InputsSync` delta for the pilot's freed pre-launch character logs
  "Node not found" on the server; remote ships aren't smoothed (N4).
- Test lag with `tests/lag/lag_run.sh` (a UDP delay proxy between `--server` and `--testplayer`; see
  `documentation/testing.md`).

## Known issues (from review, not yet fixed)

- Ship `health` setter calls `destroy()` on clients too, and can emit `destroyed` twice.
- `Ship._on_button_launch_pressed` calls a `request_spawn` RPC that does not exist.
