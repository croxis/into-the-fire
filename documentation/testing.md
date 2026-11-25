# Testing

The project has two kinds of automated test:

| Kind | What it checks | Where | Speed |
| --- | --- | --- | --- |
| **Unit tests** (GUT) | One class or scene at a time, with known inputs and expected outputs. | `tests/unit/test_*.gd` | A few seconds for all of them |
| **Smoke test** | The whole dedicated server boots and runs for 30 seconds without errors. | `tests/smoke/` | About 30 to 60 seconds |

Both run in CI on every push. Both need the **custom engine build**: stock Godot has no LimboAI
classes and no double precision, so scripts fail to parse.

In the commands below, `$GODOT` is the custom editor binary, for example:

```bash
export GODOT=~/src/godot-4.7.2-stable/bin/godot.linuxbsd.editor.double.x86_64
```

## Why bother

Tests catch a broken change minutes after you make it instead of during a play-test, or after a
player reports it. Writing the first tests for this project found several bugs nobody had noticed,
including NPC behaviour trees ticking twice per frame and a faction check that ignored grandparents.

They also make refactoring safe. The engine-fundamentals work rewrites large parts of the code; the
tests are how we know the rewritten code still does what the old code did.

## Running the tests

### Unit tests

```bash
GODOT=$GODOT tests/run.sh
```

`tests/run.sh` runs GUT and prints a short report. When everything passes that is one line:

```
PASS: Scripts 27, Tests 267, Passing Tests 267, Asserts 736, Time 16.179s
```

When something fails it prints each failing test's own output (its errors, backtraces and log lines,
without GUT's internal stack frames), then the totals and where the full log is. The exit code is
GUT's: 0 when everything passes, 1 when anything fails. It also fails when no test matched the
selection, and shows the end of the log when GUT crashed before its summary. Engine errors go to
stderr and GUT's lines to stdout, so now and then an error line lands in the next test's block; the
full log has the exact order. Set `TEST_LOG=path` to keep the log somewhere specific.

Why a wrapper: a passing run of the plain command prints about 1000 lines (colours, orphan listings,
the game's own log, leak warnings at shutdown), which buries the few lines that matter.

Run only part of the suite while you work on something:

```bash
# Only scripts whose file name contains "faction"
GODOT=$GODOT tests/run.sh faction

# Only tests whose name contains "rotation" (any GUT option is passed through)
GODOT=$GODOT tests/run.sh -gunit_test_name=rotation
```

The plain GUT command still works and shows everything, including the leak warnings printed after
the summary (`ObjectDB instances were leaked at exit`, `resources still in use at exit`; they come
from engine shutdown and don't affect the result):

```bash
$GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json
```

If you add a new `class_name` script, run `$GODOT --headless --path . --import` once first (or focus
the editor so it rescans). Otherwise the test runner doesn't know the new class and reports a parse
error.

`.gutconfig.json` holds the shared settings: tests live in `res://tests/unit/`, files start with
`test_`, and the runner exits when finished.

### Smoke test

```bash
GODOT=$GODOT tests/smoke/server_smoke.sh
```

It boots `--server` headless for 1800 frames, then fails if:

- a startup marker is missing from the log ("Server hosted on port", "Galaxy setup complete",
  "Added station", "Added ship EASS Hyperion"), or
- any `ERROR`, `SCRIPT ERROR` or `Parse Error` line appears that isn't listed in
  `tests/smoke/known_issues.txt`.

Environment variables: `SMOKE_FRAMES` (default 1800) and `SMOKE_LOG` (keep the log at a known path
instead of a temp file).

## Writing a unit test

### The shape of a test file

A test file is a script in `tests/unit/` that extends `GutTest`. Every function whose name starts
with `test_` is one test.

```gdscript
extends GutTest
## Short description of what this file tests.

const CharacterScene := preload("res://characters/character.tscn")


var registry: FactionRegistry


func before_each() -> void:
	# Runs before every test: set up a clean starting state.
	registry = FactionRegistry.new()


func test_player_brain_is_inactive() -> void:
	# Arrange: build the thing under test.
	var player: Character = CharacterScene.instantiate()
	add_child_autofree(player)

	# Act: do the one thing the test is about.
	player._player_pilot_id = 1

	# Assert: check the result. The message says what should be true.
	assert_false(player.hsm.is_active(), "players drive their own character")
```

Arrange, act, assert is a good default layout. Each test should check **one behaviour** and have a
name that says what it is, so a failure in the report tells you what broke without reading the code:
`test_contact_is_lost_out_of_range`, not `test_sensors_2`.

### Common assertions

| Assertion | Passes when |
| --- | --- |
| `assert_eq(got, expected, msg)` / `assert_ne` | Values are equal / not equal |
| `assert_true(x, msg)` / `assert_false` | Condition holds / doesn't |
| `assert_null(x)` / `assert_not_null` | Value is / isn't null |
| `assert_almost_eq(got, expected, tolerance)` | Floats or vectors are within `tolerance`. Use this for physics, never `assert_eq` |
| `assert_gt` / `assert_lt` | Greater / less than |
| `assert_has(array_or_dict, value)` | Contains the value |
| `assert_signal_emitted(obj, "name")` | After `watch_signals(obj)`, the signal fired |
| `assert_push_error_count(n)` | Exactly `n` `push_error` calls happened in this test (see below) |

### Freeing what you create

Nodes created in a test must be freed, or they leak into later tests:

- `add_child_autofree(node)` adds the node to the scene tree and frees it after the test.
- `autofree(obj)` frees an object that isn't in the tree.

Use `add_child_autofree` whenever the code under test needs `_ready`, timers or `get_tree()`.

### Waiting for frames

Some behaviour only happens after physics steps or timers. Use `await` with GUT's wait helpers:

```gdscript
await wait_physics_frames(5)
await wait_seconds(0.6)  # e.g. past a 0.5 s timer
```

Prefer calling the method directly instead (see the Helm example below). Tests that wait are slower
and can be flaky.

## Rules specific to this project

### Any engine error fails the test

GUT is set to fail a test if the engine logs **any** error during it: a script error, a failed
`get_node`, or a `push_error`. This is deliberate. Errors that scroll past in the output are bugs
waiting to happen, and this setting is how the tests found most of the bugs so far.

When an error *is* the expected behaviour (for example, the content registry rejecting a bad ID),
say so in the test:

```gdscript
func test_unknown_id_reports_error() -> void:
	assert_eq(registry.path_of(&"t:missing"), "")
	assert_push_error_count(1)
```

`assert_push_error_count` counts `push_error` calls. For errors raised by the engine itself, use
`assert_engine_error_count`.

### Don't share state between tests

Static variables survive between tests, so a test that changes one can make later tests pass or
fail depending on which ran first. Avoid statics for game state. Use an object the test can create
fresh in `before_each` instead.

Factions work this way: each test makes its own `FactionRegistry`. Characters and ships normally
find the registry through the `Galaxy` above them; in a test there is no Galaxy, so hand them the
registry directly:

```gdscript
var pilot: Character = autofree(CharacterScene.instantiate())
pilot.faction_registry = registry
registry.create("Zeta Wing", true, true).add_member(pilot)
```

Without a registry, `pilot.faction` is null (faction ID 0 means no faction).

### Multiplayer in tests

GUT runs with Godot's default `OfflineMultiplayerPeer`. That means `multiplayer.is_server()` is
`true` and the unique ID is 1, the same as single player or a host. Server-only code runs normally.
Client-only paths can't be unit tested this way yet; cover those by play-testing for now.

### Test one piece, replace its neighbours

A unit test shouldn't need the whole game running. When the code under test calls into another
system, replace that system with a small stub that records what it was asked to do. The Helm test
does this for the engines (`tests/unit/test_helm.gd`):

```gdscript
## Stands in for the Engines node and records the last request.
class EnginesStub extends Node:
	var linear := Vector3.ZERO
	var rotation_request := Vector3.ZERO

	func request_thrust(linear_throttle: Vector3, rotation_throttle: Vector3) -> void:
		linear = linear_throttle
		rotation_request = rotation_throttle


func test_manual_rotation_reaches_engines() -> void:
	var helm: HelmCapability = HelmScene.instantiate()
	add_child_autofree(helm)
	helm.set_physics_process(false)  # Tick by hand so the test controls timing.
	var engines := autofree(EnginesStub.new())
	helm.system = engines

	helm.input_rotation_throttle = Vector3(0, 1, 0)
	helm._rollback_tick(1.0 / 60.0, 0, true)

	assert_eq(engines.rotation_request, Vector3(0, 1, 0))
```

Two techniques here are worth copying:

- **Stub the neighbour.** The test checks only what the Helm sends, not whether the physics engine
  turns the ship.
- **Tick by hand.** Switching off `_physics_process` and calling the tick function directly makes the
  test exact and instant, with no waiting for frames.

GUT can also generate stubs automatically (`double()`, `stub()`, `assert_called()`). A hand-written
inner class like the one above is easier to read, so prefer it until a stub gets complicated.

### Fixing a bug: write the failing test first

1. Write a test that reproduces the bug, and run it to watch it **fail**. This proves the test
   actually detects the bug.
2. Fix the code.
3. Run the test again and watch it **pass**.
4. Run the whole suite to make sure nothing else broke.

Without step 1 you can't tell whether a passing test means "fixed" or "the test doesn't check
anything".

### What to test, and what not to

Good candidates:

- **Pure logic:** parsers (`LaunchOptions`), registries, faction tree queries, order handling. These
  are cheap to test and break silently.
- **Rules between systems:** "a player's brain is off", "an occupied console refuses a second
  character", "launch tells the new ship's helm".
- **Every bug you fix**, so it can't come back.
- **Data files:** `test_babylon5_manifest_resolves` loads every manifest entry, so a mistyped UID
  fails a test, not a play-test.

Leave to play-testing for now:

- How flight *feels*, visuals, UI layout and audio.
- Full client-and-server sessions. These need two processes, which the unit tests don't run.

Design new code so the logic can be tested without nodes where possible. `LaunchOptions` takes the
command line as a parameter instead of reading `OS.get_cmdline_args()` itself, which is why it can be
tested with any arguments.

## Testing under lag

Own-ship prediction and the server's input cushion only show their worth on a bad connection, and
two processes on one machine have none. `tests/lag/lag_proxy.py` is a small UDP proxy that delays
packets both ways, and can add jitter (which reorders packets, as the internet does) and loss.
`tests/lag/lag_run.sh` runs a dedicated server and a test player joined through it, then prints the
netcode reports:

```bash
GODOT=$GODOT tests/lag/lag_run.sh 75 15 2 90
```

The arguments are one-way latency (so ping is twice it), jitter and loss percent, then seconds to
run. The server's "Input from" lines count holds and skips every 5 s; each is a one-tick jump on the
pilot's screen. The client prints "Prediction for" only for 5 s spells that had corrections. Expect a
burst while the ship is launched; after that, a steady link should settle to none.

netfox has a latency simulator too, but it only works with netfox's own autoconnect (which does the
hosting itself, skipping our login), and only in the editor.

The proxy can also go in front of a game you play in a window: run it, start `--server` (or
`--testserver`) as usual, and join with `--testplayer --port=2259`.

## The smoke test's known-issues list

`tests/smoke/known_issues.txt` holds extended regular expressions, one per line, for errors the
smoke test tolerates. Lines starting with `#` are comments.

- **Adding a line** hides an error. Do it only for a known problem you aren't fixing yet, and put a
  comment above it saying what causes it.
- **Removing a line** as soon as its cause is fixed is just as important. From then on, the smoke
  test guards against that error coming back.

To add a startup marker (something that must appear in every healthy boot), add it to the `marker`
loop in `tests/smoke/server_smoke.sh`.

## Continuous integration

`.gitlab-ci.yml` has a `test` stage that runs after assets are imported and before the builds are
exported:

- **`unit-tests`** runs the GUT suite and writes a JUnit report. GitLab shows that report on merge
  requests, test by test.
- **`server-smoke`** runs the smoke test and keeps `smoke.log` as a job artifact. Download it from
  the job page when the smoke test fails.

A failing test stops the pipeline before the export jobs run, so a broken build isn't exported.

## Checklist for a change

- [ ] New logic has a unit test; a bug fix has a test that failed before the fix.
- [ ] Tests create their own state (such as a `FactionRegistry`) instead of sharing statics.
- [ ] The unit suite passes.
- [ ] The smoke test passes.
- [ ] Any `known_issues.txt` line whose cause you fixed is removed.
