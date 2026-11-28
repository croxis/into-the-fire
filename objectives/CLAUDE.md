# objectives/

Loaded when working in `objectives/`. Project-wide rules are in the top-level `CLAUDE.md`. Design: the design
doc's "NPC AI: first pass" section.

How orders pass down a chain of command, to NPCs and (later) players. `Objective` is one order, plain data;
`ObjectiveBoard` (`WorldState.objectives`, `Galaxy.state.objectives`) holds a world's and is the only thing
that changes them. Server only for now; the board's `changed` signal is there for replication and saves.

- **Posted or assigned.** A posting has `slots` any character on its faction's side, or a side below it
  (its wings), may claim; never a side above the issuer's. It is FILLED once every slot is claimed and opens
  again when a claim is released. An assignment is for one pilot (`assignee_id`). Same record either way, so
  an issuer's choice between them can change without changing the data.
- **IDs only.** Pilots by pilot ID, factions by faction ID, issuer 0 for the world itself. Objective IDs come
  from `WorldIds.next_objective` (`WorldState` hands a replaced counter to the board).
- **Checked claims.** `claim` returns why a claim is refused ("" when made). When players can claim they will
  send an objective ID; check it here, never trust it.
- **Types.** `Objective.Type` lists general and specific kinds; an NPC only takes the types it has behaviour
  for. First pass: PATROL: `params.route` (Array of Vector3 relative to the ship `params.anchor_ship_id`, so a
  moving carrier's patrol moves with it; `PatrolRoute.from_anchor`) and `params.system`. Default routes are
  `PatrolRoute` nodes (Marker3D waypoints) under a ship scene's `PatrolRoutes`; `PatrolRoute.pick` takes one
  that fits a radius, else builds a ring. A character holds no copy
  of its objectives: ask `claimed_by(pilot_id)` / `assigned_to(pilot_id)`.
- Replaces the old `orders/` resources (removed 2026-11-27); its typed array of itself kept a script alive
  at exit.
