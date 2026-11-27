# Scenarios

A scenario is the starting state of a world: its factions, the star systems to load, and the ships
and crew in them. A new game starts from one. Galaxy uses `scenario_id` (default `b5:playtest`).

Scenarios are data, not code. A different start (a Minbari campaign, a small test world, a mod's
setting) is a new scenario file, with no change to Galaxy.

## The pieces

| Piece | Where | What it is |
| --- | --- | --- |
| `Scenario` | `scenario/scenario.gd` | The resource: `factions`, `systems`, `ships`. |
| `ScenarioFaction` | `scenario/scenario_faction.gd` | Name, parent name, wing and player flags, optional `FactionDoctrine`. |
| `ScenarioShip` | `scenario/scenario_ship.gd` | Content ID, node name, system, position, faction name, crew. |
| `ScenarioCrew` | `scenario/scenario_crew.gd` | Name, faction name (empty: the ship's), console to sit at. |
| `ScenarioLoader` | `scenario/scenario_loader.gd` | Checks a scenario and builds the world from it. |
| `WorldIds` | `world_ids.gd` | Ship and pilot IDs for one world (`Galaxy.ids`). |

The Babylon 5 playtest is `content/scenarios/playtest.tres`, registered as `b5:playtest` in
`content/babylon5.cfg` under `[scenario]`. It holds Babylon 5 and the EASS Hyperion (Earth Alliance, whose wings
players join) and a Narn cruiser (a Hyperion hull standing in, faction Narn Regime, closed to players) 80 km
out, beyond every Earth Alliance sensor at the start (a Hyperion-sized hull is seen at 1 degree from about
59 km), so fog of war has something to hide.
`test_playtest_has_an_enemy_its_players_cannot_see_at_first` checks that.

## How things refer to each other

- **Factions by name.** A ship's `faction` and a faction's `parent` are names from the scenario's
  own faction list. Names are readable in the Inspector; the world gives each faction its numeric ID.
- **Systems and ships by content ID** (`b5:test_system`, `b5:hyperion`), never by `res://` path,
  so a mod can replace a ship and existing scenarios use the new one.
- **Consoles by path inside the ship** (`Consoles/StationCommand`), the one node path a scenario holds.

## Editing a scenario

Open the `.tres` in the Inspector. Arrays of factions, ships and crew are edited in place: add an
element, choose "New ScenarioShip" (or Faction, Crew) and fill in its fields. Save, then run the tests.
`test_playtest_scenario_is_valid` fails if a name or content ID doesn't resolve.

To add a scenario, save a new `Scenario` resource and add it to a manifest:

```ini
[scenario]
narn_border="uid://<the uid of your .tres>"
```

## What happens at startup

On the server, `Galaxy.start_new_world()` hands the scenario to a `WorldBuilder`
(`world/world_builder.gd`), the one path a world starts by (a save will feed it too):

1. **Validate.** `ScenarioLoader.validate()` lists every problem: unknown or duplicate factions,
   unknown content IDs, ships in systems the scenario doesn't load. If there are any, the game logs
   them and does not start. A typo gives a clear error, not half a world.
2. **Factions.** `build_factions()` makes a new `FactionRegistry`. Parents may be listed after their
   children. Doctrines are copied, so play never changes the scenario resource.
3. **Systems.** Every system and ship scene loads at once through `Galaxy.scene_loader`: the loading
   screen, on worker threads, in the game; at once (`WorldBuilder.load_now`) in unit tests. The
   systems are then added in order. A system that fails to load is logged and its ships skipped.
4. **Ships and crew.** `populate()` places each ship (stations with `add_station`), gives it an ID
   from `Galaxy.ids`, sets its faction, spawns its crew through `Ship.spawn_crew` so clients receive
   them, and seats crew at their consoles. Then `Galaxy.world_built`; a host's own player may then
   pick a spawn point (`ready_to_spawn`).

Clients don't read scenarios. They receive factions on connect and ships and crew through the
multiplayer spawners, like any other world state.

## Why the loader is split in three

Each step can be tested without the others. `tests/unit/test_scenario.gd` checks validation and
faction building with plain resources, and `populate()` with a stand-in system node, so no Galaxy or
system scene is needed.

## Relation to saves

A scenario describes the same records a save will hold (see the design doc, *Saves*). A save is the
scenario's records plus everything that changed since. The world's data records live in one
`WorldState` (`world/world_state.gd`, `Galaxy.state`: factions, IDs, game name, player logins), apart
from scene nodes, so a save can serialize it and a test can build it without nodes; systems, ships
and crew are still nodes. Saving isn't built yet; when it is, it will
store records through a storage interface (SQLite on servers), and scenarios stay text so they can be
reviewed, merged and shipped by mods.

## Current limitations

- Players spawn aboard any ship of their side with launch bays (`SpawnService.spawn_points`); a scenario
  can't choose spawn points or death rules (`RespawnRules`) yet.
- Scenarios hold no player spawn rules, economy or orders yet.
- Ship and pilot IDs restart at 1 each new game, and player IDs each server run: nothing saves
  `WorldState` yet.
