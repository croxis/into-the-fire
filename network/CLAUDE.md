# network/

Loaded when working in `network/`. Project-wide rules are in the top-level `CLAUDE.md`. Fog of war is
`fog_of_war.gd` (`FogOfWar`, `Galaxy.fog`: refresh, pictures, contacts; the RPC `Galaxy._contact_lost` stays
on the Galaxy), with `Galaxy.interest`, `Galaxy.contacts` and `Ship.sensor_check`, each ship's side in
`ships/ship_interest.gd` (`ShipInterest`, `Ship.interest`) and the detection maths in `ships/ship_sensors.gd`.

## Interest management (fog of war)

Interest management (N5, `network/interest.gd`, `Galaxy.interest`): the server decides which ships each
client is told about; a ship a client doesn't know does not exist there. The rule is fog of war: the ships
in the player's system that are in their top-level faction's sensor picture (`FogOfWar.pictures_of`: its own
ships and what their sensors detect, `Ship.detected_ships` from each system's 0.5 s scan), plus the ship
they are aboard; none before they have a character. Factions and ships can be kept out of the shared
picture (`excluded_from_picture`; covert wings still see it, one-way; `documentation/factions.md`). Not
yet: sharing pictures between sides, and the host's own player (the server has everything).

- With no character a client knows nothing, so the join menu asks the server for a faction's spawn points
  (`Galaxy._request_spawn_points`, own side only), and `first_spawn_player` checks the one picked
  (`Galaxy.check_spawn_point`).
- `FogOfWar.refresh` runs every 0.5 s and at once when a client connects, a ship is launched (after
  it is placed: showing a ship sends its spawn with its transform at that moment) or crew board (Godot
  refuses an RPC to a peer that can't see the node).
- Detection (`Ship.sensor_check` calls `ShipSensors.detects`; `Sensor`): EM, neutrino and gravimetric fall off with distance squared
  (sensitivity S picks up signals down to 1/S). A ship gives off its base (EM: its subsystems' power use,
  no power system yet) plus what its drive gives off with thrust each tick (`Ship.drive`, `DriveProfile`
  in `ship_systems/drives/`: chemical EM, the default; gravitic gravimetric; esoteric neutrinos). It is
  also seen when it looks wider than the sensor's `visual_acuity_degrees` (default 1); its size comes from
  its own and inner physics bodies' shapes (`ShipSensors.reach`, never areas). At 1 degree a Starfury is
  seen within ~1.4 km, a Hyperion hull ~59 km, Babylon 5 ~510 km.
- Lost contacts (N5c): when a ship leaves a client's picture while still in the world, the server sends
  `Galaxy._contact_lost` (its last state); the client records it in `Galaxy.contacts` (`ContactLog`, kept
  after the ghost fades, with when it was last seen) and draws a `GhostMarker` (`contacts/`) in that system:
  it drifts on the last course and fades over `ContactLog.fade_seconds` (30 s); stations stay put for good.
  The ship's next spawn there ends the ghost (`FogOfWar.regained`). Client log "Lost contact with X".
- Every synchronizer in a ship, crew included, has a visibility filter (`ShipInterest.follow`) and is
  updated only when interest changes (`visibility_update_mode` none; `ShipInterest.update`, the ship's own
  synchronizer first when shown, last when hidden). Godot spawns a node on a peer while the synchronizers
  rooted at it are visible there.
- A ship a client stops knowing is "leaving" for one refresh (snapshots and its other syncs stop; it stays
  on the client), then despawned: unreliable packets sent just before would otherwise arrive after it went.
  Synchronizers that keep a node spawned (the ship's own, crew's) must send nothing unreliable.
- Snapshots and the syncs that aren't part of the spawn start only once the client confirms it has the ship
  (`Ship._have_ship`, from its `_ready` there); a despawn forgets that. Sent at once they overtook the spawn.
- A player's own client sends its `InputsSync` to nobody (`Character.keep_inputs_local`): its input goes
  through `InputChannel`. New broadcast RPCs (`.rpc()`) on ship
  nodes would reach clients that don't have the ship: send to the clients that know it.
- Server log "Interest: peer X now knows N ships (+ more, leaving, gone)".

## Quitting

- `network.gd` `_exit_tree` detaches the peer (`multiplayer_peer = null`) before Galaxy is freed (network comes
  after Galaxy in `entry.tscn`; Godot frees children last first). Freed online, the server sent despawns for
  nodes a client never had (fog of war): an error each. Not closed early: a clean DTLS shutdown makes the client
  log TLS errors. Left: a server quitting first sometimes gives the client one `-0x6C00` (its UDP send hit the
  closed port, `bio_send`), about 3 runs in 8.

## Steady links

- `network.gd` `steady(link)` turns off ENet's packet throttle for each connection (server: in
  `_authenticating`, which also tells the client; client: `on_connected`). The throttle is bulk-traffic
  congestion control: after one RTT spike it drops a share of unreliable packets on purpose for seconds,
  down to all of them; our streams are small and carry their own redundancy.
