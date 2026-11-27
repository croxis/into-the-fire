# Command-line flags

The game reads its run mode from the command line. `boot/launch_options.gd` (`LaunchOptions`) parses
the flags, and `entry.gd` starts the matching mode. Parsing uses no nodes, so
`tests/unit/test_launch_options.gd` can test it.

In the examples, `$GODOT` is the custom engine binary (see [testing.md](testing.md)). When running from
source, put the game's flags after `--path .`. An exported build takes the same flags directly:
`./itf.x86_64 --server`.

```bash
$GODOT --path . --testserver
```

## Run modes

Give at most one mode flag. If you give more than one, the first one in this table wins.

| Flag | Mode |
| --- | --- |
| (none) | **Client**: title screen and main menu. Single player and host-and-play start here. |
| `--server` | **Dedicated server**: no local player and no UI. |
| `--testserver` | **Test server**: hosts a game called "Test Server" and plays in it (developer shortcut). |
| `--testplayer` | **Test player**: waits 5 s, then joins a server as "Test Player" (developer shortcut). |

A process also runs as a dedicated server, with no mode flag, when:

- it is an export with the `dedicated_server` feature, or
- the display server is headless (`--headless`), because a menu can't be shown without a screen.

`--headless --testserver` stays a test server; the smoke test and two-process tests rely on that.

## Options

| Flag | Used by | Default | Meaning |
| --- | --- | --- | --- |
| `--port=N` | all network modes | `2258` | Port to host on or join. Must be from 1 to 65535; any other value is ignored and logged. |
| `--game=NAME` | `--server` | `default` | Name of the hosted game. |
| `--password=PW` | `--server` | (empty) | Password clients must give to join. |
| `--host=ADDR` | `--testplayer` | `127.0.0.1` | Server to join, as an IP or hostname. Set this when the test player runs on another device. |
| `--faction=NAME` | `--testplayer` | (empty) | Spawn in this faction (its `name` in the scenario, e.g. `--faction="Zeta Wing"`) as soon as the server's factions arrive, instead of waiting in the join menu. Used by automated two-process tests. |
| `--spawn-at=NAME` | `--testplayer` with `--faction` | (empty) | Spawn aboard this spawn point (a ship with launch bays, e.g. `--spawn-at="EASS Hyperion"`) instead of the first one offered. |
| `--launch` | `--testplayer` with `--faction` | off | Once aboard, press Launch by itself, as a player would. Used by automated two-process tests of a remote pilot flying. |
| `--fire` | `--testplayer` with `--launch` | off | Once flying (3 s after launch), hold the trigger. Used by automated lag runs of weapons. |
| `--fly` | `--testplayer` with `--launch` | off | Once flying (3 s after launch), thrust and turn in a fixed pattern that changes every 2 s. Used by lag runs of own-ship prediction while steering. |

Flags take their value after `=`. A space-separated value (`--port 3000`) is not read: `3000` is
reported as an unknown argument. Unknown arguments are logged at startup ("Ignored arguments") and
otherwise ignored.

## Engine flags

These belong to Godot, not to the game, but matter here:

| Flag | Notes |
| --- | --- |
| `--headless` | No window and no GPU. Required for dedicated servers on machines without a GPU; nothing on the server path may depend on rendering. With no mode flag it means dedicated server. |
| `--xr-mode on` | Starts OpenXR. OpenXR can only start with the engine, so the project keeps `xr/openxr/enabled` off and needs this flag. Players can also switch with Options > "VR mode", which restarts the game with or without it (`LaunchOptions.restart_args`). XR is low priority for now. |

`--xr_mode` (underscore) is the game's own flag and only prints a hint to use `--xr-mode on`.

## Common setups

Dedicated server with a password:

```bash
$GODOT --headless --path . --server --game=Epsilon --password=secret --port=3000
```

Host-and-play plus a second player on the same machine:

```bash
$GODOT --path . --testserver
```

```bash
$GODOT --path . --testplayer
```

A test player on another device, such as a Steam Deck, joining a `--testserver` on the dev machine.
Use the dev machine's LAN IP, and let UDP port 2258 through its firewall (ENet uses UDP):

```bash
./itf.x86_64 --testplayer --host=192.168.1.50
```

Two-process automated test, with the test player spawning straight into a faction:

```bash
$GODOT --headless --path . --testserver
```

```bash
$GODOT --headless --path . --testplayer --faction="Zeta Wing"
```
