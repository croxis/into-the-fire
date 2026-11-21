# Into The Fire

A persistent, self-hosted 3D space combat and trading sandbox set in Babylon 5, built in Godot.
Inspired by X4 (sandbox, empire, map), Babylon 5: I Found Her (hyperspace) and Sierra's cancelled
Babylon 5: Into the Fire (crew combat). Long term it is meant to be a general sci-fi spaceship engine with
Babylon 5 as the default mod. Early development: many systems are partial or stubbed.

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

Physics engine is Jolt, zero gravity and zero damping (`project.godot`).

Build image and export templates: the separate godot-ci repo (a fork of abarichello/godot-ci, usually
checked out beside this repo as `../godot-ci`). Its `Dockerfile` pins `GODOT_VERSION`, the LimboAI commit
and `patches/`. Engine changes go there, not here. This repo's `.gitlab-ci.yml` uses the image
`registry.gitlab.com/croxis/itf:<version>.custom`; keep the tag in step with the engine version.

## Running

Main scene: `res://entry.tscn`. Command-line flags are parsed in `entry.gd`:

| Flags | Mode |
| --- | --- |
| (none) | Client with title screen and menu |
| `--server [--game=NAME --password=PW --port=N]` | Dedicated server (also triggered by the `dedicated_server` feature) |
| `--testserver` | Hosts "Test Server" on port 2258 and plays |
| `--testplayer` | Joins 127.0.0.1:2258 after 5 s as "Test Player" |
| `--xr_mode` | OpenXR (legacy from Godot 3, being reworked) |

Default port 2258, max 12 peers (`network/network.gd`). Dedicated servers must run with `--headless` on
GPU-less machines; nothing on the server path may depend on rendering.

## Code map

- `entry.gd` / `entry.tscn`: boot, flag parsing, owns `network` and `Galaxy`.
- `network/network.gd`: ENet host/join and the custom auth handshake.
- `Galaxy.gd`: playtest world setup (hard-coded Babylon 5 station, Hyperion, NPC crew), spawning, respawn.
- `systems/`: each star system is a `SubViewportContainer` with its own `World3D` (`system_template.*`).
- `ships/`: `Ship.gd` (RigidBody3D), `Engines.gd` (per-thruster forces), `crew.gd`, `PID.gd`.
- `ship_systems/workstations/`: `Console` plus capabilities (Helm, Weapons, Command); each capability
  brings a behaviour tree that runs in the occupant's `BrainHSM`.
- `characters/`: `Character` (crew member, player or NPC), input sync, LimboAI state.
- `factions/`: `Faction` resource tree with a static registry, `FactionDoctrine`.
- `orders/`: order data model (logic mostly not implemented).
- `ai/`: LimboAI trees, blackboards and command tasks.
- `demo/`: LimboAI demo content, not game code.

Autoloads include netfox (`NetworkTime`, `NetworkRollback`, ...), `Log`, `LimboConsole`,
`LocalGameManager` (local player id), and `_mcp_game_helper` (godot-ai addon).

## Netcode

- ENet with Godot's high-level multiplayer: RPCs, `MultiplayerSpawner`, `MultiplayerSynchronizer`.
- Server authoritative. Client input reaches the server through each character's `InputsSync`
  (a `MultiplayerSynchronizer` owned by that player's peer).
- netfox 1.35 is installed; rollback is currently disabled (`netfox/rollback/enabled=false`).
- Spawners only track nodes they spawned. Reparenting nodes across spawn paths (e.g. crew moving between
  ships) is not replicated; spawn with `spawn_function` and data dictionaries instead.
- Never trust IDs sent by clients: validate every `any_peer` RPC on the server.

Target direction (see the design doc): data records separate from scene nodes, per-zone `SubViewport`
worlds without containers, own-ship prediction with netfox `RollbackSynchronizer` and a custom flight
integrator, interpolation for remote ships, interest management, event-based weapons.

## Known issues (from review, not yet fixed)

- `faction.gd`: `@rpc` on a static function does nothing; factions are created locally on every peer
  and live in static variables (tests must reset `Faction.factions` / `Faction._next_id`).
- Ship `health` setter calls `destroy()` on clients too, and can emit `destroyed` twice.
- `Ship._on_button_launch_pressed` calls a `request_spawn` RPC that does not exist.
- Headless server builds Maaack's option menus ("Not supported by this display server" errors).
- `factions/factions.tres.gd` duplicates the faction setup with different wings.
- `Ship.tscn` syncs `autospin`/`autobreak`/`target_*` on the root, but they moved to Helm.
- `Galaxy.gd` and `Ship.gd` load content by path; content should come from a registry.

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
- Write a failing test first when fixing a bug. Reset static state (factions) in `before_each`.
- CI (`.gitlab-ci.yml`): import assets, `test` stage (`unit-tests` with JUnit report, `server-smoke`),
  then export Linux and Windows debug builds with the custom image.
- Planned packaging: one binary per OS, base pck plus content pcks (Babylon 5 as the default mod).

## godot-ai MCP

The godot-ai editor addon exposes the running editor (scene, node, script, filesystem and run tools).
Use `editor_state` to confirm the connection. `game_eval` and game screenshots need the project running.
