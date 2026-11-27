# Netcode

How the game keeps a server and its clients in step: what each machine simulates, what crosses the
network, when, and why. For the per-folder detail an agent needs while editing, see the `CLAUDE.md`
files in `ships/`, `characters/` and `network/`; this page is the overview.

## The shape of it

One machine is the **server**: it runs the real simulation, decides everything that matters and
tells clients what happened. A **client** never decides an outcome. It sends its player's input and
shows the world as well as it can while it waits for the server to confirm.

A client sees three kinds of things, each handled differently:

| What | How it reaches the client | How it is shown |
| --- | --- | --- |
| The ship your player flies | Your input goes up; the server sends back its state for your ship | Flown at once on your machine (**prediction**), corrected when the server's state disagrees |
| Every other ship and station | Tick-stamped **snapshots** of position and velocity | Drawn about 100 ms in the past, smoothly between snapshots |
| Slow-changing state (health, names, crew seats, factions) | Godot's `MultiplayerSynchronizer` (on change) and reliable RPCs | As it arrives |

The **host** of a listen server is the server, so it has no latency: it never predicts.

Transport is ENet through Godot's high-level multiplayer. netfox 1.35 supplies the tick clock and
time sync; its rollback is not used. Prediction, snapshots and interest management are our own.

## Time

The simulation runs in **ticks**, 60 a second, inside the physics frame (netfox `NetworkTime`, with
`sync_to_physics`). Each tick runs in a fixed order:

1. `before_tick`: characters hand this tick's input to the helm of the console they sit at.
2. `on_tick`: ships run their helms, then fly (`Ship._rollback_tick`).
3. `after_tick`: `ZoneStepper` steps each star system's physics space.

After a loop of ticks, `after_tick_loop`: the server sends pilots their ship's state and everyone
their snapshots; the server also checks pilots' input queues for a backlog.

There are three clocks to keep apart:

- **The server's tick**: the truth.
- **A client's netfox tick**: netfox keeps it near the server's, stretching the client's clock a
  little to catch up. A client can also run a few milliseconds *ahead* of it (time dilation, below).
  It is not steady, so nothing that measures arrival times uses it.
- **The moment a client draws other ships at** (`SnapshotClock`): about 100 ms behind the newest
  server tick it has heard of, measured against the machine's real-time clock
  (`SnapshotClock.local_now`).

`Galaxy.shown_tick(node)` gives "the server tick this machine is showing now": the server's own
tick, or a client's drawn moment. Anything that moves on a schedule rather than by physics (Babylon
5's rotating section, its launch arms) uses it, so every machine shows the same pose for the same
moment.

## Joining

1. **Login.** `network.gd`: the server sends its protocol details and its content signature; the
   client checks them (`check_server_info`) and sends a login with its own; the server checks that
   (`check_login`, never logged: it holds passwords) and completes the handshake. The content
   signature (`ContentRegistry.signature`) lists each manifest loaded, in order, with a hash of the
   file: a client with other mods, other versions of them or another load order is told what
   differs and can't join, rather than breaking later on content IDs it doesn't have.
2. **Factions.** The server sends the faction tree as plain data (`FactionRegistry.to_data`).
3. **Nothing else, yet.** A client with no character is told about no ships at all (fog of war). The
   join menu asks the server for a faction's spawn points (`Galaxy._request_spawn_points`, names
   only, own side only) and the server checks the pick (`Galaxy.check_spawn_point`).
4. **Spawning in.** The server puts the player's character aboard; their client is then told about
   the ships its side can see, and they spawn there.

Ship scenes are loaded, and their collision shapes built, in the first frames after startup
(`Content`, one ship a frame): the first instantiate of a ship would otherwise read it from disk and
have Jolt build its hull shapes, half a second of frozen ticks.

A player who disconnects keeps their character in the world with neutral controls (a one-seat craft
brakes to a stop). Logging back in with the same name resumes it (`Galaxy._resume`).

## Your own ship

### Input up

Your client stamps each tick's input with its tick number and sends it unreliably, each packet
repeating the last four inputs so a lost packet loses nothing (`InputChannel`,
`Character._submit_inputs`). The server queues them and applies exactly one per tick, in order.

Packets arrive in clumps, so the server keeps a small **cushion** of inputs before using them (2 to
8 ticks, growing when it runs dry and shrinking after a steady spell). Two things can go wrong, and
each costs a correction of one tick of motion (speed x 1/60 s, about 40 m at 2.5 km/s):

- **A hold**: the queue ran dry, so the server repeated your last input for a tick you never flew.
- **A skip**: a backlog built up, so the server dropped your oldest input.

**Time dilation** keeps both rare. With each state, the server reports how many of your inputs are
queued and its cushion; your client runs very slightly faster or slower than real time (at most
1.5%, `InputLead` steering `NetworkTime.lead_seconds`) to keep the queue one above the cushion. So
the queue drains or fills smoothly. The server still skips a real backlog (after a stall), checked
once per loop after its ticks.

### State down, and corrections

Your client flies your ship at once, recording each tick's input. After each tick loop the server
sends your ship's state and the last input it applied (`ShipReconciler.send_state`). Your client goes
back to that state and replays its own input since (`ShipReconciler.reconcile`): if the result
differs from where it had you, that is a **correction**. Flight assist is worked out again during
the replay from the replayed speed and spin, as the server did.

A position correction is eased in over about 100 ms (`CorrectionSmoother`). Rotation and velocity
snap, since thrust follows the way the ship points.

While the server holds your ship (on a launch arm), its state says so: your client holds it too and
keeps recording input for when it is let go. On Babylon 5 it rides your own client's arm, drawn with
the station, until the server releases it; prediction then takes over, with one eased correction.

## Other ships

After each tick loop the server sends each ship's position, rotation and velocities to the clients
that know it, stamped with the server tick (`ShipSnapshots`, the RPC `Ship._receive_snapshot`).
How often depends on distance from the ship the client's player is aboard (**interest tiers**):
30 a second within 5 km, every 6 ticks to 25 km, every 16 beyond.

Snapshots are sent unreliable and unordered. `SnapshotBuffer` puts them back in order, so a late one
still fills its gap.

A client draws each other ship about 100 ms in the past: between the two snapshots either side of
that moment it follows a curve matching both positions and both velocities, so a turning ship does
not cut corners. Past the newest (a late or lost snapshot) it carries the ship on for up to 250 ms.
The ship is kinematic on the client: physics doesn't fly it, but other bodies still hit it.

## Who is told what: interest management and fog of war

The server decides, per client, which ships exist on that client at all (`Interest`, refreshed by
`FogOfWar` every 0.5 s and at once when that changes). The rule is fog of war: the ships in the
player's system that their side's sensors see, plus the ship they are aboard. A ship a client isn't
told about is not on its machine, so a modified client can't reveal it. Detection, exclusions and
lost-contact ghosts are described in `network/CLAUDE.md` and `documentation/factions.md`.

How a ship appears and disappears on a client:

- Every synchronizer in a ship, crew included, asks `Interest` whether the client should have it
  (`ShipInterest.follow`). Godot spawns a node on a client while its own synchronizer is visible
  there, and despawns it when not.
- Snapshots and the other syncs start only once the client confirms it has the ship
  (`Ship._have_ship`): sent at once, they overtook the spawn and found no ship.
- A ship that drops out of view is "leaving" for one refresh (no more snapshots) before it is
  despawned, so nothing sent just before can arrive after it is gone.
- Godot refuses an RPC to a client that can't see the node. Any message to the clients about a ship
  must go to the clients that know it, never `.rpc()` to everyone.

## Security

- The server validates every request a client makes against what that player's character may do.
- Never trust an ID a client sends: the sender is `multiplayer.get_remote_sender_id()`.
- Logins are never logged. Passwords still cross the network in plain text.

## Testing under lag

Two processes on one machine have no latency. `tests/lag/lag_proxy.py` is a UDP proxy that adds
delay, jitter and loss; `tests/lag/lag_run.sh LATENCY JITTER LOSS SECONDS [TEST PLAYER FLAGS]` runs a
headless server and a headless test player through it and prints the reports below. See
`documentation/testing.md`. A headless test player gives no input, and a headless server renders
nothing: input-dependent and rendering problems need a window.

What the logs tell you:

| Log line | Where | Healthy |
| --- | --- | --- |
| `Input from X: H held, S skipped, Q queued, cushion C` | server, every 5 s | 0 held and 0 skipped once flying; queued near the cushion + 1 |
| `Prediction for X: N corrections, largest D m` | client, every 5 s, only when there were some | One at launch (the arm's release), then rare and small |
| `Drawing X: N ticks behind the newest snapshot, M of F frames past it` | client, every 5 s | About 5 behind (6, less the time since the last arrival); few frames past it |
| `Interest: peer X now knows N ships (+ more, leaving, gone)` | server, on change | Matches what that player's side can see |

## Lessons learned

Each of these cost a debugging session; the code and its tests now guard against them.

- **Godot sends a node's new transform to physics only at the start of the next physics frame.** A
  correction set between ticks was overwritten by the zone step. `Ship.place` sets it in Jolt too.
- **`unreliable_ordered` drops any packet that a later one on its channel overtook,** across all RPCs
  sharing the channel. Under jitter half the snapshots were lost; they are now unordered.
- **netfox's client tick is not a steady clock.** Measuring snapshot arrivals against it drew ships
  ahead of their snapshots. Real time is used instead.
- **A spawn carries the node's state at the moment it is shown.** A ship shown as it entered the world
  appeared at the origin and snapped 5.8 km.
- **A server that falls behind runs several ticks in one frame,** with what arrived meanwhile already
  queued. Checked in the first of them, that looked like a backlog.
- **Loading a scene on a worker thread while the main thread loads it, or its scripts, deadlocked or
  failed to parse.** `Content` loads on the main thread.
- **Jolt builds a concave hull shape the first time a body uses it** (Babylon 5's: 277 ms). `Content`
  builds them at startup.
- **A VoxelGI node in a ship froze every machine that drew one,** each time one appeared. Ships carry
  none.

What is planned but not built (weapons and lag compensation, moving between systems, password security)
is in the design doc linked from `CLAUDE.md`.
