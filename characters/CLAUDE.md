# characters/

Loaded when working in `characters/`. Project-wide rules are in the top-level `CLAUDE.md`.

## Pilot input

- Pilots on another machine send tick-stamped input (`InputChannel`, `Character._submit_inputs`, unreliable,
  each packet repeating the last 4 inputs); the server checks it and applies one per tick, in order. The
  host's own input and NPCs still go through `InputsSync`.
- The server keeps a cushion (jitter buffer) per pilot and skips a backlog back to it.
- The cushion adapts, 2 to 8 ticks: it grows a tick each time it runs dry and shrinks after a steady spell
  (5 s, doubling up to 40 s if it ran dry soon after the last shrink). Every hold or skip is a one-tick jump on
  the pilot's screen, so this trades a little delay for others against those jumps.
- Log: server "Input from X: held, skipped, queued, cushion" every 5 s.
- The client side of this (prediction, replay, corrections) is in `ships/CLAUDE.md`.
