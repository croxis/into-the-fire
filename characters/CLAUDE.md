# characters/

Loaded when working in `characters/`. Project-wide rules are in the top-level `CLAUDE.md`.

## Pilot input

- Pilots on another machine send tick-stamped input (`InputChannel`, `Galaxy._submit_inputs`: the server
  finds the sender's pilot in `Galaxy._pilots`, which each player's Character joins on entering, so inputs
  in flight when a ship is destroyed are dropped quietly; unreliable,
  each packet repeating the last 4 inputs, packed by `InputChannel.encode`, 29 bytes each; `make_record`
  rounds vectors to float32 so client and server fly the same values); the server checks it and applies
  one per tick, in order. The
  host's own input and NPCs still go through `InputsSync`.
- The server keeps a cushion (jitter buffer) per pilot. Every hold (queue dry: the last input repeats) or skip
  (backlog: the oldest is dropped) is a tick of motion the client didn't predict, a correction of speed x
  1/60 s (about 40 m at 2.5 km/s). Autospin and autobreak presses in skipped or flooded-out inputs carry over.
- The cushion adapts, 2 to 8 ticks: it grows a tick each time it runs dry and shrinks after a steady spell
  (5 s, doubling up to 40 s if it ran dry soon after the last shrink), without dropping an input.
- Time dilation (`InputLead`): each state the server sends the pilot says how many of their inputs are queued
  and the cushion; the client steers how far ahead of netfox's server time it runs (`NetworkTime.lead_seconds`,
  at most 1.5% faster or slower) to keep the queue one over the cushion. So the queue drains or fills
  smoothly instead of by holds and skips; the server skips only a backlog over cushion + 8 (a stall), checked
  once per tick loop after its ticks (`Character._trim_input_backlog`): checked in the first tick of a
  catch-up loop, the inputs that loop was about to use looked like a backlog.
  `lead_seconds` is an ITF patch in `addons/netfox/network-time.gd` (marked "ITF patch"): reapply it after
  updating netfox.
- Launches used to cost 10-25 holds then 16-32 skips, the cushion growing to 7 for ~30 s. Two causes, both
  from the client's ~670 ms frame boarding a ship (and the host's when it spawns things): ENet's packet
  throttle dropped unreliable inputs after the RTT spike (links are now `network.gd` `steady`), and a
  time-sync sample whose reply waited out that frame pulled netfox's clock 12% slow then fast for seconds
  (second ITF patch, `network-time-synchronizer.gd` `_discipline_clock`: samples over 2x the best RTT,
  or best + 50 ms, are left out). Tests: `test_steady_link.gd`, `test_clock_sync.gd`. The frame itself is
  now paid at startup instead (`zones/CLAUDE.md`, render warm-up).
- Log: server "Input from X: held, skipped, queued, cushion" every 5 s.
- A player's own client keeps its `InputsSync` to itself (`keep_inputs_local`): nobody reads a remote
  pilot's, and its last packet used to reach a character the server had just freed at launch.
- A player who disconnects keeps their character in the world (`Galaxy._on_peer_disconnected`,
  `Character.pilot_disconnected`): the server gives it neutral input (`player_connected` false) and a
  one-seat craft brakes to a stop. Logging back in with the same name resumes it (`Galaxy._resume`: new peer
  id and input authority, camera and HUD again, no join menu); `pilot_rejoined` starts a fresh channel for
  the new client's ticks.
- The client side of this (prediction, replay, corrections) is in `ships/CLAUDE.md`.
