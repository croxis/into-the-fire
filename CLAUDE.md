# Into The Fire

A persistent, self-hosted 3D space combat and trading sandbox set in Babylon 5, built in Godot; long term a
general sci-fi spaceship engine with Babylon 5 as the default mod. Early development: many systems are partial
or stubbed.

Docs: `documentation/` (`testing.md`, `content_registry.md`, `factions.md`, `scenarios.md`, `command_line.md`).
Design doc (target architecture, decisions, open questions): https://claude.ai/artifact/SbiKWXHGRsfhgvoeBBGW7J
Folders with their own `CLAUDE.md` (loaded when you work there): `ships/` (flight, own-ship prediction),
`characters/` (pilot input, jitter buffer), `zones/` (Jolt job pool warning).

## Working agreements

- Ask before large refactors or deleting files. The owner is learning netcode and testing, so explain the
  reasoning behind non-obvious choices.
- GDScript first. GDExtensions or engine modules if GDScript is not sufficient or when profiling shows a need.
- Prefer editing scenes through the Godot editor (godot-ai MCP tools) over hand-editing `.tscn`/`.tres`.
  If you must hand-edit, keep `uid` and `unique_id` values intact. To understand a scene, start with
  `scene_get_hierarchy` / `node_get_properties` (editor running) or `rg -n` for the node you need; read a whole
  `.tscn` only when that isn't enough (meshes and materials make them long).
- The README says no vibe coding; keep changes reviewable and small.
- Search with `rg`, which honours `.ignore` (addons, `demo/`, `*.import`, `*.uid` and the action maps are
  skipped). To search an addon, name its path: `rg NetworkTime addons/netfox`.

## Engine: custom Godot 4.7.2 build (required)

Stock Godot will not open this project correctly. The build has:

- `precision=double` (large world coordinates). Jolt is built with `JPH_DOUBLE_PRECISION`.
- LimboAI as an engine module (BT/HSM classes: `LimboHSM`, `BTPlayer`, `BTAction`, ...).
- Physics stepping patch, godot PR 76462 (`PhysicsServer3D.space_step` / `space_flush_queries`), for
  per-zone manual stepping (not netfox physics rollback).

Jolt physics, zero gravity and damping. Speed cap raised to 10 km/s, spin cap 1350°/s
(`physics/jolt_physics_3d/limits/*`). Zone spaces are inactive and stepped by `ZoneStepper`; a space created
outside a zone is still stepped by the engine.

Engine changes, the build image and export templates live in the separate godot-ci repo (usually
`../godot-ci`; its `Dockerfile` pins `GODOT_VERSION`, the LimboAI commit and `patches/`). `.gitlab-ci.yml`
uses `registry.gitlab.com/croxis/itf:<version>.custom`; keep the tag in step with the engine version.

## Running

Main scene `res://entry.tscn`; flags parsed by `boot/launch_options.gd`, dispatched in `entry.gd`, full
reference in `documentation/command_line.md`. The main menu exists only when there is a UI.

| Flags | Mode |
| --- | --- |
| (none) | Client with title screen and menu |
| `--server [--game=NAME --password=PW --port=N]` | Dedicated server (also `dedicated_server` feature, or `--headless` alone) |
| `--testserver` | Hosts "Test Server" on port 2258 and plays |
| `--testplayer [--host=ADDR --faction=NAME --launch]` | Joins after 5 s; `--faction` spawns without the menu, `--launch` also presses Launch |
| `--xr-mode on` | OpenXR (low priority) |

Default port 2258, max 12 peers (`network/network.gd`). Dedicated servers run `--headless` on GPU-less
machines; nothing on the server path may depend on rendering.

## Code map

- `entry.gd`: boot and run-mode dispatch, owns `network` and `Galaxy`. `boot/`: `LaunchOptions`.
- `content/`: `ContentRegistry` and the `Content` autoload. Game code asks for content by ID
  (`Content.instantiate(&"b5:aurora_starfury")`), never by `res://` path; IDs are in manifests such as
  `content/babylon5.cfg`.
- `network/network.gd`: ENet host/join and the custom auth handshake.
- `Galaxy.gd`: world state (factions, systems, players, `ids`), new game from scenario `scenario_id`
  (default `b5:playtest`), player spawning, respawn. `world_ids.gd`: ship and pilot ID counters (never statics).
- `scenario/`: `Scenario` resources and `ScenarioLoader`; scenarios are content (`content/scenarios/`).
- `systems/`: each star system is a zone: a `SubViewport` with its own `World3D`, holding `ships`, `bolts`
  and their spawners. `System.find_for(node)` finds a node's system.
- `zones/`: `ZoneView` draws the viewed zone in the main window (zone SubViewports don't render).
  `ZoneStepper` (`Galaxy.zone_stepper`) steps each system's physics space itself; modes FULL and PAUSED.
- `ui/hud/`: `HudLayer` (`Galaxy.hud`), the local player's HUD, client-side only. 2D UI inside a ship is never
  drawn, so HUDs go here (passenger HUD, a console's `hud_scene`). "Console" is a spacecraft's crew
  interface; "station" means a space station.
- `ships/`: `Ship`, `Engines`, `FlightIntegrator`, prediction (see `ships/CLAUDE.md`).
- `ship_systems/workstations/`: `Console` plus capabilities (Helm, Weapons, Command), each with a behaviour
  tree run in the occupant's `BrainHSM`. Helm's part in prediction: `ships/CLAUDE.md`.
- `characters/`: `Character` (crew, player or NPC), input, LimboAI state.
- `factions/`: `Faction`, `FactionRegistry` (one per world, `Galaxy.factions`; found via
  `Galaxy.find_for(node)` or an explicit `faction_registry` in tests). ID 0 is "no faction".
- `orders/` (data model, logic mostly missing), `ai/` (LimboAI trees and tasks), `demo/` (LimboAI demo, not game code).

Autoloads include netfox (`NetworkTime`, `NetworkRollback`, ...), `Log`, `LimboConsole`, `LocalGameManager`
(local player id), `Content`, and `_mcp_game_helper` (godot-ai).

## Netcode

- ENet with Godot's high-level multiplayer (RPCs, `MultiplayerSpawner`, `MultiplayerSynchronizer`). Server
  authoritative. netfox 1.35 is installed, rollback disabled; own-ship prediction is our own (`ships/CLAUDE.md`).
- The simulation runs on netfox ticks, 60 Hz inside the physics frame, in a fixed order: `before_tick`
  characters hand input to their console's helm, `on_tick` ships run their helms then fly
  (`Ship._rollback_tick`), `after_tick` `ZoneStepper` steps each zone. Nothing ticks until a game is hosted or
  joined. Tests run ticks by hand with `tests/unit/ticks.gd`.
- Spawners only track nodes they spawned; reparenting across spawn paths is not replicated. Spawn with
  `spawn_function` and data dictionaries: crew via
  `ship.spawn_crew(Character.pilot_data(..., galaxy.ids.next_pilot()))`, never `add_child`.
- Never trust IDs sent by clients: validate every `any_peer` RPC on the server, and get the sender from
  `multiplayer.get_remote_sender_id()`, not arguments (see `Ship.request_launch`). Logins are checked by
  `network.gd` `check_login` first and never logged (they hold passwords).
- Interest management (N5, `network/interest.gd`, `Galaxy.interest`): the server decides which ships each
  client is told about, refreshed every 0.5 s (`Galaxy.refresh_interest`); for now, the ships in its player's
  system, or where it could spawn before it has a character. Snapshots go only to clients that know the ship.
  It is to grow into fog of war (faction sensor pictures), so a client never learns of a ship it shouldn't
  see: next, unknown ships are despawned on that client (N5a2). Server log "Interest: peer X now knows N ships".

## Tests and CI

Tests need the custom engine binary (`GODOT` below); stock Godot lacks LimboAI and doubles.

- Unit tests: GUT 9.7.1, `tests/unit/test_*.gd`. GUT fails a test on any engine error, script error or
  `push_error` during it. `tests/run.sh` prints one line on a pass, only the failing tests' output otherwise
  (`tests/run.sh NAME` = `-gselect=NAME`; other GUT options pass through).
  ```bash
  GODOT=$GODOT tests/run.sh
  ```
- Smoke test: boots `--server` headless for 1800 frames, checks startup markers, fails on any error not in
  `tests/smoke/known_issues.txt` (remove a line when its cause is fixed).
  ```bash
  GODOT=$GODOT tests/smoke/server_smoke.sh
  ```
- Write a failing test first when fixing a bug. No game state in statics; tests make their own (e.g. a fresh
  `FactionRegistry` in `before_each`).
- `test_ship_flight.gd` run on its own fails on a known Jolt warning (`zones/CLAUDE.md`); the full suite passes.
- CI (`.gitlab-ci.yml`): import, `unit-tests` (JUnit) and `server-smoke`, then Linux and Windows debug exports.

## godot-ai MCP

The editor addon exposes scene, node, script, filesystem and run tools. `editor_state` confirms the
connection; `game_eval` and game screenshots need the project running.
