# ship_systems/weapons/

Loaded when working in `ship_systems/weapons/`. Project-wide rules are in the top-level `CLAUDE.md`. The
owner's design choices: favour the shooter, fire events (not networked bolt nodes), Starfury player fire first.

## Firing (weapons netcode W1)

- The trigger rides in the pilot's tick-stamped input (`fire_primary`, bit 3 of `InputChannel`'s flag byte).
  `Character._apply_input` hands it to the console's `WeaponsCapability.trigger(pressed, tick)`, which fires
  its system (a `Guns` node: `Guns.fire_at`, each `Gun.fire_at`). Not in replays: guns fire once per real tick.
- Cooldowns count ticks (`Gun.cooldown_ticks`), so server and shooter agree on when a gun fires.
- The Starfury cockpit's Weapons points at `../../../Guns`. Gun values (bolt speed 30 m/s, 2 s cooldown) look
  like placeholders; the owner decides tuning.

## Shots (W2)

- A shot is data (`Shot`: origin, velocity, fire tick, damage, shooter), a straight line by tick number, not a
  physics body. `Gun.make_shot`: from the muzzle along the gun's +z (the scenes' convention: the Starfury's `Guns` node is
  turned half a turn, so +z is the ship's forward) at the gun's speed plus the ship's velocity.
- Each system's `ShotField` (`System.shots`) is stepped after that system's physics step (`ZoneStepper` calls
  `System.after_step`), so hulls are where this tick put them. On the server each shot's stretch of path this
  tick is ray-tested (`_hit`, skipping the shooter's own hull) and a hit calls `Ship.take_shot`. Clients never
  decide hits. Damage falls off as damage / (1 + 0.2 x seconds in flight); shots last 600 ticks.
- `Bolt.tscn` only draws a shot (no collision, no synchronizer), at `Galaxy.shown_tick`; none on headless
  machines. The system's `BoltSpawner` node is gone (`systems/BoltSpawner.gd` is unused).

## Fire events and prediction (W3)

- The server's shot is the real one. `Gun.fire_at` on the server calls `Ship.announce_shot`: a fire event
  (`ShotField.encode_fire`: gun index, tick, origin as doubles, velocity, 41 bytes, unreliable) to the clients
  that know the ship (`ShipSnapshots.recipients`), except its pilot's. Those clients fly it (`Ship._shot_fired`).
- The pilot's own client fires its copy at once (`Ship.is_predicted_here`): `Shot.predicted`, its tick this
  client's, drawn at this machine's tick with the predicted ship (`Bolt.drawn_tick`). Other shots are drawn at
  `Galaxy.shown_tick`, the moment the shooter is drawn. Clients fire no other guns (an NPC's synced trigger).

## Favour the shooter (W4)

- Each input record carries `view_ticks` (a byte): how far behind its own tick the client was showing other
  ships (`Character._view_ticks`, from `SnapshotClock`). The server's rewind for a remote player's shot is
  `ShotField.rewind_for(server tick, input tick, view_ticks)`, capped at `MAX_REWIND_TICKS` (15, 250 ms), kept
  for the shot's flight (`Shot.rewind_ticks`); NPCs' and the host's shots have none.
- The server keeps each ship's transform for the last 17 ticks (`ShotField.record_history`, from
  `System.after_step`). A rewound shot's stretch this tick is moved with each nearby ship from then to now
  (now x then inverted) and ray-tested against that ship alone (`_rewound_hit`); the nearest hit wins.
- Tests: place ships with `Ship.place`, not `global_position` (physics only learns a set position next frame).

## Hits (W5)

- On a hit the server's `ShotField` lowers health (`Ship.take_shot`), emits `hit(shot, target, at)` and the
  shooter announces it (`Ship.announce_hit`: gun, tick, position, 29 bytes, unreliable) to clients that know
  the shooter, its pilot too. Each names the shot by the tick that client knows it by: `Shot.client_tick`
  (the pilot's input tick) for the pilot, the server's fire tick for others. Clients drop it
  (`ShotField.remove_named`) and flash (`HitFlash`). Clients that know the target but not the shooter see no flash.
- Server log `Shots in SYSTEM: N fired, M hits` every 5 s (`ShotField.report`). `--fire` (test player) holds
  the trigger once flying. The guns have no sound yet (their AudioStreamPlayer3D has no stream).
