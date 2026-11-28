# ai/

Loaded when working in `ai/`. Project-wide rules are in the top-level `CLAUDE.md`. Design and the slice plan:
the design doc's "NPC AI: first pass" section (owner's decisions are recorded there).

NPC AI runs on the server only, for NPC characters (`Character._update_brain_active`). Layers: a commander
decides and posts objectives (`objectives/`); subordinates claim them by utility (slice 5); a LimboAI tree per
objective type carries them out; an AI pilot flies the helm (slice 4). LimboAI is an engine module here.

- **Commander** (`roles/command.tres`, on the Command capability, `ship_systems/workstations/command.tscn`):
  whoever sits at a Command console as an NPC (Babylon 5's `StationCommand`). Once a second: `AssessThreat`
  (`ThreatAssessment.threat_to`, always 0 this pass), `EvaluateFighterNeed` (doctrine), `PostPatrolObjective`.
  The logic is in `CommanderPatrol` (no nodes; the tasks are thin), tested in `test_commander_patrol.gd`.
- **Only adds fighters** this pass: a posting gains slots, never loses them, never is cancelled (no recall
  without docking). Fighters out = own-side crewed non-capital ships within `FactionDoctrine.patrol_radius`;
  those holding a claim on the posting count as its slots, not on top of them.
- **Patrol routes** (`patrol_route.gd`): Marker3D waypoints under a ship scene's `PatrolRoutes`, relative to
  the ship without scale. Babylon 5 has Inner (10-12 km), the Hyperion Escort (4 km).
- **AI pilot** (`ai_pilot.gd`, `Character.ai_pilot`): an NPC's helm input on the server
  (`InputSource.AI`; `_read_input` skips NPCs, which carry the server's peer ID). `fly_to` a point and hold,
  `follow` a route (relative to an anchor ship, looping or holding at the end), `stop`. Newtonian: it wants the
  velocity it can still brake from on reverse thrust (80%), closing in at 0.25/s of the distance near a hold
  point, points the nose at the velocity change and thrusts each axis toward it. Accelerations are measured
  from the ship's engines (rated thruster forces don't add up: many are angled); a Starfury: 37.5 m/s²
  forward, 14.2 reverse, 4.2 sideways. No weapons. Flight tests run 4 ticks per frame and excuse the known
  Jolt job pool warning (`Ticks.excuse_jolt_job_pool`).
- **BT agents**: a console's BTPlayer sits inside the brain HSM, so tasks find their character with
  `CommanderPatrol.character_of(agent)`. Trees are hand-edited `.tres` (keep the uid); the editor can save its
  cached copy of a tree over the file when it saves a scene using it: rescan after editing one.
