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
  physics body. `Gun.make_shot`: from the muzzle, forward (-z) at the gun's speed plus the ship's velocity.
- Each system's `ShotField` (`System.shots`) is stepped after that system's physics step (`ZoneStepper` calls
  `System.after_step`), so hulls are where this tick put them. On the server each shot's stretch of path this
  tick is ray-tested (`_hit`, skipping the shooter's own hull) and a hit calls `Ship.take_shot`. Clients never
  decide hits. Damage falls off as damage / (1 + 0.2 x seconds in flight); shots last 600 ticks.
- `Bolt.tscn` only draws a shot (no collision, no synchronizer), at `Galaxy.shown_tick`; none on headless
  machines. The system's `BoltSpawner` node is gone (`systems/BoltSpawner.gd` is unused).
