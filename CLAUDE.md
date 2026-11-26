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
  client is told about; a ship a client doesn't know does not exist there. The rule is fog of war: the ships
  in the player's system that are in their top-level faction's sensor picture (`Galaxy.picture_of`: its own
  ships and what their sensors detect, `Ship.detected_ships` from each system's 0.5 s scan), plus the ship
  they are aboard; none before they have a character. Not yet: ships left out of the picture, sharing
  pictures, and the host's own player (the server has everything).
  - With no character a client knows nothing, so the join menu asks the server for a faction's spawn points
    (`Galaxy._request_spawn_points`, own side only), and `first_spawn_player` checks the one picked
    (`Galaxy.check_spawn_point`).
  - `Galaxy.refresh_interest` runs every 0.5 s and at once when a client connects, a ship is launched (after
    it is placed: showing a ship sends its spawn with its transform at that moment) or crew board (Godot
    refuses an RPC to a peer that can't see the node).
  - Detection (`Ship.sensor_check`, `Sensor`): EM, neutrino and gravimetric fall off with distance squared
    (sensitivity S picks up signals down to 1/S). A ship gives off its base (EM: its subsystems' power use,
    no power system yet) plus what its drive gives off with thrust each tick (`Ship.drive`, `DriveProfile`
    in `ship_systems/drives/`: chemical EM, the default; gravitic gravimetric; esoteric neutrinos). It is
    also seen when it looks wider than the sensor's `visual_acuity_degrees` (default 1); its size comes from
    its own and inner physics bodies' shapes (`Ship.visual_radius`, never areas). At 1 degree a Starfury is
    seen within ~1.4 km, a Hyperion hull ~59 km, Babylon 5 ~510 km.
  - Lost contacts (N5c): when a ship leaves a client's picture while still in the world, the server sends
    `Galaxy._contact_lost` (its last state); the client records it in `Galaxy.contacts` (`ContactLog`, kept
    after the ghost fades, with when it was last seen) and draws a `GhostMarker` (`contacts/`) in that system:
    it drifts on the last course and fades over `ContactLog.fade_seconds` (30 s); stations stay put for good.
    The ship's next spawn there ends the ghost (`Galaxy.contact_regained`). Client log "Lost contact with X".
  - Every synchronizer in a ship, crew included, has a visibility filter (`Ship._follow_interest`) and is
    updated only when interest changes (`visibility_update_mode` none; `Ship.update_interest`, the ship's own
    synchronizer first when shown, last when hidden). Godot spawns a node on a peer while the synchronizers
    rooted at it are visible there.
  - A ship a client stops knowing is "leaving" for one refresh (snapshots and its other syncs stop; it stays
    on the client), then despawned: unreliable packets sent just before would otherwise arrive after it went.
    Synchronizers that keep a node spawned (the ship's own, crew's) must send nothing unreliable.
  - Snapshots and the syncs that aren't part of the spawn start only once the client confirms it has the ship
    (`Ship._have_ship`, from its `_ready` there); a despawn forgets that. Sent at once they overtook the spawn.
  - A player's own client sends its `InputsSync` only to the server. New broadcast RPCs (`.rpc()`) on ship
    nodes would reach clients that don't have the ship: send to the clients that know it. (`Gun.fire_sound`
    does; fix it when weapons are restored.)
  - Server log "Interest: peer X now knows N ships (+ more, leaving, gone)".

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
- Join test: a headless server and a `--testplayer --launch` client over ENet (port 2270); fails on a missing
  join step in either log or an error not in `tests/smoke/known_issues.txt` / `known_client_issues.txt`.
  ```bash
  GODOT=$GODOT tests/smoke/join_smoke.sh
  ```
- Write a failing test first when fixing a bug. No game state in statics; tests make their own (e.g. a fresh
  `FactionRegistry` in `before_each`).
- `test_ship_flight.gd` run on its own fails on a known Jolt warning (`zones/CLAUDE.md`); the full suite passes.
- CI (`.gitlab-ci.yml`): import, `unit-tests` (JUnit), `server-smoke` and `join-smoke`, then Linux and Windows debug exports.

## godot-ai MCP

The editor addon exposes scene, node, script, filesystem and run tools. `editor_state` confirms the
connection; `game_eval` and game screenshots need the project running.
