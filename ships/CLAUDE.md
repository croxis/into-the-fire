# ships/

Loaded when working in `ships/`. Project-wide rules are in the top-level `CLAUDE.md`.

## Flight

`Ship.gd` (RigidBody3D), `Engines.gd` (per-thruster forces), `crew.gd`, `PID.gd`. Split out of `Ship.gd`:
`ship_sensors.gd` (emissions, size and detection maths for fog of war), `ship_interest.gd` (which clients a
ship exists on; both in `network/CLAUDE.md`), `ship_snapshots.gd` and `ship_reconciler.gd` (below),
`ship_launch.gd` (server: a player launching from a carrier, `request_launch`). `FlightIntegrator`
(`flight_integrator.gd`) is ship motion without nodes: ships set `custom_integrator` and take their
velocities from it each tick (`Ship._fly`), using Jolt's mass and inertia; Jolt still moves them and handles
contacts. Stations keep Jolt's own integration. It clamps to Jolt's speed limits
(`physics/jolt_physics_3d/limits/*`), so replays match Jolt.

Thrust uses the ship's basis for both force direction and thruster lever arms (`Ship.thrust`), so a scaled
ship thrusts differently. Place ships with position and rotation only (`orthonormalized()`): Babylon 5's
launch-arm spawn points sit at a global scale of 0.81. `FlightIntegrator.step` keeps any scale when it turns
a ship, as Jolt does.

## Own-ship prediction

Our own reconciler, not netfox rollback: `ShipReconciler` (`ship_reconciler.gd`, `Ship.reconciler`; the
RPC `Ship._receive_state` stays on the ship). The pilot's input reaches the server through `InputChannel`
(see `characters/CLAUDE.md`).

- The pilot's client flies its ship at once and records each helm's input every tick (`ShipPrediction`,
  `HelmCapability.input_record`).
- After each tick loop the server sends that client its ship's state and the last input tick it applied
  (`ShipReconciler.send_state`).
- The client replays its input since then, working thrust out again from the replayed state
  (`ShipReconciler.reconcile`, `Ship.replay_thrust`, `HelmCapability.assist`: flight assist depends on the current spin and speed; its
  PIDs are proportional only, so replays can re-run them).
- It eases a correction of its position in over about 100 ms (`CorrectionSmoother`); rotation, velocity and
  jumps over 100 m snap, since thrust follows the way the ship points.
- Corrections go through `Ship.place`, which sets the transform in Jolt directly: Godot only sends a node's new
  transform to physics at the start of the next physics frame, after our ticks have stepped the zone.
- While the server holds the ship frozen (a launch arm), its state says so and the client freezes the ship too,
  still recording input for the replay after release. A Babylon 5 arm holds it on the client's own arm
  (`held_by_local_arm`), drawn with the station; otherwise it follows the server's states exactly.
- Babylon 5 runs on the clock: its rotating section's angle (`rotation.gd`, not synced) and its arms' poses
  (`cobra_bay_arm.gd`, the deploy's start tick sent to clients) come from `Galaxy.shown_tick`: the server's
  tick, or the moment a client draws the station. The release from the arm costs one eased correction of
  roughly speed x (render delay + latency), as prediction takes over from the drawn arm.
- The host never predicts.
- Logs: client "Prediction for X: N corrections" every 5 s.
- How it all fits together, for people: `documentation/netcode.md`.

## Snapshots (other ships)

- Motion reaches clients as tick-stamped snapshots, not through the `MultiplayerSynchronizer`. Each ship's
  `ShipSnapshots` (`ship_snapshots.gd`, `Ship.snapshots`) holds both sides: after each tick loop the server
  sends its transform and velocities every `INTERVAL_TICKS` (2, so 30 a second; `send`, through the RPC
  `Ship._receive_snapshot`, which stays on the ship). The synchronizer sends motion only when a ship appears
  (`transform`, velocities: spawn only), so a new ship starts in the right place.
- Interest tiers: that rate is for a ship within 5 km of the ship the client's player is aboard
  (`Galaxy.interest.viewpoint`); to 25 km every 6 ticks, further every 16 (`ShipSnapshots.interval_for`,
  paced per client by `due_for`). Clients draw distant ships between sparser snapshots, extrapolating
  past the newest when one is late.
- Each client confirms it has a ship from that ship's `_ready` (`_have_ship`): a snapshot sent before the ship
  exists there would fail ("node not found"). A despawn forgets it (interest management, see
  `network/CLAUDE.md`). `ShipSnapshots.recipients` skips peers that left, the pilot predicting the ship, who gets its own
  state, and clients that `Galaxy.interest` says don't know the ship.
- Snapshots are plain `unreliable`, not `unreliable_ordered`: ENet drops an ordered packet that a later one on
  the same channel overtook, and every ship's snapshots and the pilot's state share it, so under jitter half
  were lost. `SnapshotBuffer` orders them itself.
- Clients keep them in `Ship.snapshots.buffer` (`SnapshotBuffer`: in tick order, samples between them on a Hermite
  curve with slerped rotation, extrapolates up to 15 ticks past the newest).
- Drawing (N4c): on a client, every ship it doesn't predict (stations too) is kinematic and drawn each frame
  from its buffer (`ShipSnapshots.draw`), `SnapshotClock.DELAY_TICKS` (6, 100 ms) behind the newest snapshot.
  `SnapshotClock` (one per `Galaxy`) estimates the newest server tick from when snapshots arrive, averaged
  against this machine's real time (`SnapshotClock.local_now`), not the netfox tick: netfox speeds up and slows a
  client's ticks to catch the server, and doesn't tick before a game starts. Jolt moves a kinematic body to
  its new transform during the next step, with the velocity that takes, so contacts see it moving; velocities
  set on it would be a surface velocity, so they are zeroed. When our player takes the helm the ship stays
  frozen until the server's first state releases it (`ShipReconciler.reconcile`).
- Logs: client "First snapshot for X"; every 5 s "Drawing X: N ticks behind the newest snapshot, M of F frames
  past it" (about 5 behind is right: 6, less the time since the last arrival; frames past it were
  extrapolated, from late or lost snapshots).
- Test lag with `tests/lag/lag_run.sh` (a UDP delay proxy between `--server` and `--testplayer`; see
  `documentation/testing.md`).

## Health

`Ship.health` starts at the scene's `max_health` (set in `_ready`; a client's spawn carries the server's).
Only the server destroys a ship at zero, once (`destroy`); clients see it despawn.
