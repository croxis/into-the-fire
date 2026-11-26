# characters/

Loaded when working in `characters/`. Project-wide rules are in the top-level `CLAUDE.md`.

## Pilot input

- Pilots on another machine send tick-stamped input (`InputChannel`, `Character._submit_inputs`, unreliable,
  each packet repeating the last 4 inputs); the server checks it and applies one per tick, in order. The
  host's own input and NPCs still go through `InputsSync`.
- The server keeps a cushion (jitter buffer) per pilot. Every hold (queue dry: the last input repeats) or skip
  (backlog: the oldest is dropped) is a tick of motion the client didn't predict, a correction of speed x
  1/60 s (about 40 m at 2.5 km/s). Autospin and autobreak presses in skipped or flooded-out inputs carry over.
- The cushion adapts, 2 to 8 ticks: it grows a tick each time it runs dry and shrinks after a steady spell
  (5 s, doubling up to 40 s if it ran dry soon after the last shrink), without dropping an input.
- Time dilation (`InputLead`): each state the server sends the pilot says how many of their inputs are queued
  and the cushion; the client steers how far ahead of netfox's server time it runs (`NetworkTime.lead_seconds`,
  at most 1.5% faster or slower) to keep the queue one over the cushion. So the queue drains or fills
  smoothly instead of by holds and skips; the server skips only a backlog over cushion + 8 (a stall).
  `lead_seconds` is an ITF patch in `addons/netfox/network-time.gd` (marked "ITF patch"): reapply it after
  updating netfox.
- Log: server "Input from X: held, skipped, queued, cushion" every 5 s.
- A player's own client keeps its `InputsSync` to itself (`keep_inputs_local`): nobody reads a remote
  pilot's, and its last packet used to reach a character the server had just freed at launch.
- A player who disconnects keeps their character in the world (`Galaxy._on_peer_disconnected`,
  `Character.pilot_disconnected`): the server gives it neutral input (`player_connected` false) and a
  one-seat craft brakes to a stop. Logging back in with the same name resumes it (`Galaxy._resume`: new peer
  id and input authority, camera and HUD again, no join menu); `pilot_rejoined` starts a fresh channel for
  the new client's ticks.
- The client side of this (prediction, replay, corrections) is in `ships/CLAUDE.md`.
