# Factions

Factions are the sides in the game: Earth Alliance, Babylon 5, its fighter wings, and later
player-created factions. They form a tree. Babylon 5 is a child of Earth Alliance, and Zeta Wing is a
child of Babylon 5.

## Where factions live

| Piece | Where | What it is |
| --- | --- | --- |
| `Faction` | `factions/faction.gd` | One faction: name, flags, parent, members. A `Resource`. |
| `FactionRegistry` | `factions/faction_registry.gd` | Every faction in one world, and the IDs that identify them. A plain `RefCounted`. |
| `Galaxy.factions` | `Galaxy.gd` | The registry for the running world. |

There is one registry per world, and `Galaxy` owns it. Factions are not stored in static variables.
Starting a new game or loading a save replaces the registry as a whole, so nothing from the previous
game survives, and each unit test can make its own registry.

## IDs

Every faction has an integer `faction_id`, assigned by the registry when it is created.

- IDs start at **1**. **0 (`FactionRegistry.NO_FACTION`) means "no faction"** and is never assigned.
  Ships and characters default to `faction_id = 0`, so forgetting to set one leaves them with no
  faction instead of silently joining the first faction created.
- IDs are what crosses the network and goes into saves. Ships and characters store and sync only
  `faction_id`. Their `faction` property looks the ID up in the registry each time.
- IDs are never reused. A copy of a registry continues numbering after its highest ID.

## Using factions from code

```gdscript
# Server only: create factions (playtest setup does this in Galaxy).
var ea := galaxy.factions.create("Earth Alliance")
var b5 := galaxy.factions.create("Babylon 5", false, false, false, ea)
var zeta := galaxy.factions.create("Zeta Wing", true, true, false, b5)  # wing, accepts players

# Look up
galaxy.factions.get_by_id(id)            # null for 0 or an unknown ID
galaxy.factions.find_by_name("Zeta Wing")
galaxy.factions.top_level()              # factions without a parent
b5.get_wings()                           # direct children that are wings
zeta.is_a_parent(ea)                     # true: any ancestor counts

# Membership
zeta.add_member(pilot)                   # also removes the pilot from its old faction
zeta.remove_member(pilot)                # pilot is left with no faction (ID 0)
ship.faction_id = b5.faction_id          # ship ownership
```

### How a ship or character finds its registry

`ship.faction` and `character.faction` look for the `Galaxy` above them in the scene tree
(`Galaxy.find_for(node)`) and use its registry. A ship sits at
`Galaxy/Systems/<system>/ships/`, and a character sits in a ship's `Crew`, so both are
always under a Galaxy once they are in the world.

Before a node is in the tree there is no Galaxy above it, so `faction` returns null. Logs show
"not in world yet" in that case. Two consequences:

- **Set a ship's `faction_id` after adding it to a system.** The setter records the ship in the
  faction's `owned_ships`, and it can only do that when it can reach the registry. `Galaxy` and
  `Ship.request_launch` both add the ship first.
- **In unit tests, set `faction_registry`** on the ship or character to give it a registry directly.

## Networking

Only the server creates or changes factions. Clients get a copy:

1. When a client connects, `Galaxy._on_peer_connected` (on the server) sends
   `factions.to_data()` to that client with the `_rpc_receive_factions` RPC.
2. The client replaces its registry with `FactionRegistry.from_data(data)` and emits
   `factions_synced`.
3. The faction picker (`JoinGame`) is shown only once the copy has arrived.

Why it is built this way:

- **`to_data()` is plain dictionaries.** Objects can't be sent over the network, so the copy holds
  IDs, names and flags, with parents as IDs. `from_data()` rebuilds the tree on the client.
- **The RPC is marked `"authority"`.** Only the server can call it, so a modified client can't push
  its own factions to other players.
- **Clients send IDs, the server checks them.** A spawn request carries a faction ID and a system
  name. `Galaxy.check_spawn_request()` refuses unknown factions, factions that don't accept
  players, and anything that isn't a direct child of `Systems`. (Without that last check, a name like
  `".."` would resolve to a node outside the systems.)

Not sent to clients: the AI doctrine (only the server's AI uses it), the server-only lists of
owned and detected ships, and `excluded_from_picture` (which wings are covert is the server's to know).

## Fog of war

A top-level faction's ships share one sensor picture: each player is told about the ships their side
owns or detects (`FogOfWar.view_of`, see the netcode notes in `CLAUDE.md`). A faction or a ship can be
kept out of it (`excluded_from_picture`, in the scenario or changed in play once a leader is allowed:
`FogOfWar.check_exclusion_change`, only the leader of the owning faction or one above it):

- **An excluded faction** (a covert wing): its ships, and what they detect, are seen by it and the
  factions below it, not by the rest of the side. One-way: it still sees the shared picture.
- **An excluded ship**: only its own crew know where it is and what it detects.

Either way, another side's sensors (or the rest of its own side's) can still detect it.

Changes after joining aren't sent yet, because nothing changes factions during play so far. When
faction creation, reorganising or secession is added, the server should send the change (or a fresh
copy) to every client.

## Tests

- `tests/unit/test_faction_registry.gd`: IDs, lookups, the tree, the network copy, lookups from
  ships and characters, and spawn-request checks.
- `tests/unit/test_faction.gd`: the tree queries on `Faction` and membership changes.
