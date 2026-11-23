# Into The Fire

A persistent, self-hosted 3D space combat and trading sandbox set in Babylon 5, built in Godot.
Inspired by X4 (sandbox, empire, map), Babylon 5: I Found Her (hyperspace) and Sierra's cancelled
Babylon 5: Into the Fire (crew combat). Long term it is meant to be a general sci-fi spaceship engine with
Babylon 5 as the default mod. Early development: many systems are partial or stubbed.

Project documentation lives in `documentation/` (`testing.md`, `content_registry.md`, `factions.md`, `scenarios.md`).

Design doc (target architecture, decisions, open questions):
https://claude.ai/artifact/SbiKWXHGRsfhgvoeBBGW7J

## Working agreements

- Ask before large refactors or deleting files. The owner is learning netcode and testing, so explain the
  reasoning behind non-obvious choices.
- GDScript first. GDExtensions or engine modules if GDScript is not sufficient or when profiling shows a need.
- Prefer editing scenes through the Godot editor (godot-ai MCP tools) over hand-editing `.tscn`/`.tres`.
  If you must hand-edit, keep `uid` and `unique_id` values intact.
- The README says no vibe coding; keep changes reviewable and small.

## Engine: custom Godot 4.7.2 build (required)

Stock Godot will not open this project correctly. The build has:

- `precision=double` (large world coordinates). Jolt is built with `JPH_DOUBLE_PRECISION`.
- LimboAI as an engine module (BT/HSM classes: `LimboHSM`, `BTPlayer`, `BTAction`, ...).
- Physics stepping patch, godot PR 76462 (`PhysicsServer3D.space_step` / `space_flush_queries`).
  Jolt implements it. Kept for per-zone manual stepping, not for netfox physics rollback.

Physics engine is Jolt, zero gravity and zero damping (`project.godot`). Jolt's speed cap is raised from
500 m/s to 10 km/s and its spin cap halved to 1350°/s (`physics/jolt_physics_3d/limits/*`).
Zone spaces are inactive and stepped by `ZoneStepper`; a space created outside a zone is still stepped
by the engine.

Build image and export templates: the separate godot-ci repo (a fork of abarichello/godot-ci, usually
checked out beside this repo as `../godot-ci`). Its `Dockerfile` pins `GODOT_VERSION`, the LimboAI commit
and `patches/`. Engine changes go there, not here. This repo's `.gitlab-ci.yml` uses the image
`registry.gitlab.com/croxis/itf:<version>.custom`; keep the tag in step with the engine version.

## Running

Main scene: `res://entry.tscn`. Command-line flags are parsed by `boot/launch_options.gd` (`LaunchOptions`)
and dispatched in `entry.gd`. The main menu is created at runtime only when there is a UI:

| Flags | Mode |
| --- | --- |
| (none) | Client with title screen and menu |
| `--server [--game=NAME --password=PW --port=N]` | Dedicated server (also the `dedicated_server` feature, or `--headless` with no mode flag) |
| `--testserver` | Hosts "Test Server" on port 2258 and plays |
| `--testplayer [--host=ADDR --faction=NAME]` | Joins `--host` (default 127.0.0.1) on port 2258 after 5 s as "Test Player"; `--host` lets another device (e.g. a Steam Deck) join a `--testserver` on the dev machine; with `--faction`, spawns in that faction without the menu |
| `--xr-mode on` | OpenXR. Godot's own engine flag: OpenXR can only start with the engine, so the project keeps `xr/openxr/enabled` off. `--xr_mode` alone only prints this hint. Players switch with Options > "VR mode", which restarts the game (`LaunchOptions.restart_args`). XR is low priority for now |

Default port 2258, max 12 peers (`network/network.gd`). Dedicated servers must run with `--headless` on
GPU-less machines; nothing on the server path may depend on rendering.

## Code map

- `entry.gd` / `entry.tscn`: boot and run-mode dispatch, owns `network` and `Galaxy`.
- `boot/`: `LaunchOptions` (command-line parsing, no node dependencies).
- `content/`: `ContentRegistry` and the `Content` autoload. Game code asks for content by ID
  (`Content.instantiate(&"b5:aurora_starfury")`), never by `res://` path. IDs are listed in manifests
  such as `content/babylon5.cfg` (uid:// values; `*.cfg` there is in the export include filter).
- `network/network.gd`: ENet host/join and the custom auth handshake.
- `Galaxy.gd`: owns the world state (factions, systems, players, `ids`). Starts a new game from the
  scenario `scenario_id` (default `b5:playtest`), player spawning, respawn. The server sends factions to
  each client on connect.
- `scenario/`: `Scenario` resources (factions, systems, ships, crew) and `ScenarioLoader` (validate,
  build factions, populate). Scenarios are content, e.g. `content/scenarios/playtest.tres`.
- `world_ids.gd`: `WorldIds`, the world's ship and pilot ID counters (start at 1; never statics).
- `systems/`: each star system (`System`, `system_template.*`) is a zone: a `SubViewport` root with its own
  `World3D`, holding `ships`, `bolts` and their spawners. `System.find_for(node)` finds a node's system.
- `zones/`: `ZoneView` (in Galaxy) draws the viewed zone in the main window: sets its `world_3d`, a camera rig
  (or XR origin) follows the zone's current camera, input is forwarded. Zone SubViewports don't render.
  `ZoneStepper` (`Galaxy.zone_stepper`) steps each system's physics space itself (`space_step`, then
  `space_flush_queries`) instead of the engine; modes FULL and PAUSED. Every system runs FULL for now.
- `ui/hud/`: `HudLayer` (`Galaxy.hud`), the local player's HUD in the main window. 2D UI inside a ship is never
  drawn, so HUDs go here, client-side only: the passenger HUD (Launch) on capital ships and space stations, and
  the console's `hud_scene` while a player sits at it. Say "console" for a spacecraft's crew interface;
  "station" means a space station.
- `ships/`: `Ship.gd` (RigidBody3D), `Engines.gd` (per-thruster forces), `crew.gd`, `PID.gd`.
  `FlightIntegrator` (`flight_integrator.gd`) is ship motion without nodes: ships set `custom_integrator` and
  take their velocities from it each tick (`Ship._fly`), using Jolt's mass and inertia; Jolt still moves them and
  handles contacts. Stations keep Jolt's own integration. It clamps to Jolt's speed limits
  (`physics/jolt_physics_3d/limits/*`), so replays match Jolt.
- `ship_systems/workstations/`: `Console` plus capabilities (Helm, Weapons, Command); each capability
  brings a behaviour tree that runs in the occupant's `BrainHSM`.
- `characters/`: `Character` (crew member, player or NPC), input sync, LimboAI state.
- `factions/`: `Faction` resource tree, `FactionRegistry` (one per world, owned by `Galaxy.factions`),
  `FactionDoctrine`. ID 0 is "no faction". Ships and characters find the registry through the Galaxy
  above them (`Galaxy.find_for(node)`), or use an explicitly set `faction_registry` (tests).
- `orders/`: order data model (logic mostly not implemented).
- `ai/`: LimboAI trees, blackboards and command tasks.
- `demo/`: LimboAI demo content, not game code.

Autoloads include netfox (`NetworkTime`, `NetworkRollback`, ...), `Log`, `LimboConsole`,
`LocalGameManager` (local player id), `Content` (content registry), and `_mcp_game_helper` (godot-ai addon).

## Netcode

- ENet with Godot's high-level multiplayer: RPCs, `MultiplayerSpawner`, `MultiplayerSynchronizer`.
- Server authoritative. Client input reaches the server through each character's `InputsSync`
  (a `MultiplayerSynchronizer` owned by that player's peer).
- netfox 1.35 is installed; rollback is currently disabled (`netfox/rollback/enabled=false`).
- The simulation runs on netfox ticks, 60 Hz inside the physics frame (`netfox/time/tickrate`,
  `sync_to_physics`), in a fixed order: `before_tick` characters hand input to their console's helm,
  `on_tick` ships run their helms then fly (`Ship._rollback_tick`), `after_tick` `ZoneStepper` steps each
  zone. Engine physics frames alone no longer move ships or zones; nothing ticks until a game is hosted or
  joined. Tests run ticks by hand with `tests/unit/ticks.gd`.
- Spawners only track nodes they spawned. Reparenting nodes across spawn paths (e.g. crew moving between
  ships) is not replicated; spawn with `spawn_function` and data dictionaries instead. Crew are created
  with `ship.spawn_crew(Character.pilot_data(..., galaxy.ids.next_pilot()))`, never `add_child`.
- Never trust IDs sent by clients: validate every `any_peer` RPC on the server. Work out who asked from
  `multiplayer.get_remote_sender_id()`, not from arguments (see `Ship.request_launch`). Logins are checked by
  `network.gd` `check_login` before anything else, and never logged (they hold passwords).

Target direction (see the design doc): data records separate from scene nodes, per-zone physics stepping,
own-ship prediction with netfox `RollbackSynchronizer` and a custom flight
integrator, interpolation for remote ships, interest management, event-based weapons.

## Known issues (from review, not yet fixed)

- Ship `health` setter calls `destroy()` on clients too, and can emit `destroyed` twice.
- `Ship._on_button_launch_pressed` calls a `request_spawn` RPC that does not exist.
- "Jolt Physics job system exceeded the maximum number of jobs" warning once after a long stall (loading):
  netfox then runs several ticks in one frame, and the stepping patch's `space_step` doesn't free Jolt's
  finished jobs (`JoltJobSystem::post_step`); only the engine's own step does. Jolt waits and recovers, so it
  is left as is for now. If it becomes a problem, fix it in godot-ci's stepping patch: wrap the call in
  `JoltPhysicsServer3D::space_step` with `job_system->pre_step()` / `job_system->post_step()`, as `step()` does.

## Tests and CI

Tests need the custom engine binary (`GODOT` below). Stock Godot lacks LimboAI and doubles.

- Unit tests: GUT 9.7.1 in `addons/gut`, tests in `tests/unit/test_*.gd`, config `.gutconfig.json`.
  GUT fails a test on any engine error, script error or `push_error` during it.
  ```bash
  $GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json
  ```
- Smoke test: boots `--server` headless for 1800 frames, checks startup markers, and fails on any
  error not matched by `tests/smoke/known_issues.txt`. Remove a known-issue line when its cause is fixed.
  ```bash
  GODOT=$GODOT tests/smoke/server_smoke.sh
  ```
- Write a failing test first when fixing a bug. Don't keep game state in statics; tests make their own
  (e.g. a fresh `FactionRegistry` in `before_each`).
- CI (`.gitlab-ci.yml`): import assets, `test` stage (`unit-tests` with JUnit report, `server-smoke`),
  then export Linux and Windows debug builds with the custom image.
- Planned packaging: one binary per OS, base pck plus content pcks (Babylon 5 as the default mod).

## godot-ai MCP

The godot-ai editor addon exposes the running editor (scene, node, script, filesystem and run tools).
Use `editor_state` to confirm the connection. `game_eval` and game screenshots need the project running.
