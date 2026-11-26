# Adding content with the content registry

Game code never loads ships, stations or star systems by `res://` path. It asks the content
registry for a **content ID**, and the registry says which scene to use. This is what will let mods
add new content, or replace existing content, without changing any game code.

This guide covers adding a new asset (for example a ship) and using it from code.

## The pieces

| Piece | Where | What it does |
| --- | --- | --- |
| `ContentRegistry` | `content/content_registry.gd` | Maps IDs to resource paths. Plain `RefCounted`, no nodes. |
| `Content` autoload | `content/content.gd` | The game's registry. Loads every manifest in `MANIFESTS` at startup. |
| Manifest | `content/babylon5.cfg` | A text file listing one mod's content. Babylon 5 is the default mod. |

## Content IDs

An ID has the form `namespace:name`, for example `b5:aurora_starfury`.

- **namespace** is the mod that owns the content. Babylon 5 content uses `b5`.
- **name** identifies the item within that mod.
- Use only lowercase letters, digits and underscores, with exactly one colon. `B5:Starfury` and
  `star fury` are rejected.

Pick names that describe *what the thing is*, not where its file lives. File paths change; IDs end
up in save files and must not.

## Manifest format

A manifest is a Godot `ConfigFile` (INI-style):

```ini
[meta]
namespace="b5"

[ship]
aurora_starfury="uid://cdmfpwxkn7p4l"
babylon_5="uid://bx03e1mn48l58"
hyperion="uid://dmpj0ge68t2li"

[system]
test_system="uid://sl64gsa8wdih"
```

- `[meta]` must set `namespace`. A manifest without it is refused and registers nothing.
- Every other section is a **kind** of content (`ship`, `system`, ...). Kinds are labels for
  listing (`registry.ids(&"ship")`); the registry doesn't enforce them yet.
- Each key is a name in the manifest's namespace, so `aurora_starfury` under `namespace="b5"`
  becomes `b5:aurora_starfury`.
- Each value is the resource to load. **Use `uid://` references, not `res://` paths.** A UID stays
  the same when the file is moved or renamed in the editor, so the manifest won't break.

## Adding a new ship, step by step

This example adds an Omega-class destroyer as `b5:omega`.

### 1. Make the scene

Build the ship scene in the Godot editor as usual, e.g.
`ships/earth alliance/omega/omega.tscn`. Its root should be a `Ship` (`ships/Ship.gd`).

### 2. Get the scene's UID

Use either of these:

- **In the editor:** right-click the scene in the FileSystem dock and choose **Copy UID**.
- **From the file:** the first line of a `.tscn` file holds it:
  `[gd_scene format=3 uid="uid://..."]`.

### 3. Add it to the manifest

Add one line under the right section of `content/babylon5.cfg`:

```ini
[ship]
omega="uid://<the uid you copied>"
```

### 4. Let the ship replicate over the network

Ships live under each system's `ships` node, and the `ShipSpawner`
(`MultiplayerSpawner`) in `systems/system_template.tscn` replicates them to clients. A spawner only
replicates scenes in its **Auto Spawn List**.

Open `systems/system_template.tscn`, select `ShipSpawner`, and add the new scene to
**Auto Spawn List** in the Inspector. If you skip this, the ship exists on the server but never
appears on clients. Nothing warns you, so check it on a client.

> This step is manual for now. Filling the spawner's list from the registry is planned, so that mods
> can add ships without editing the template scene.

### 5. Use it from code

```gdscript
# Spawn an instance (returns null and logs an error if the ID is unknown).
var omega := Content.instantiate(&"b5:omega") as Ship

# Only the path, e.g. for the loading screen or background loading.
var path := Content.path_of(&"b5:test_system")

# Check before using an optional ID.
if Content.has(&"b5:omega"):
	...
```

Every `ship` is loaded in the first frames after startup, one a frame on the main thread, on server
and clients, and kept in memory (`Content.ships_preloaded()`): the first instantiate of a ship would
otherwise read it from disk, about 300 ms for a Starfury, a stall that froze the game's ticks at a
first launch. Then `Content` has Jolt build each ship's collision shapes (`Content.ships_ready()`):
Jolt builds a concave hull shape the first time a body uses it, 277 ms for Babylon 5's, a stall
wherever the station first appeared (a client's spawn, or fog of war revealing it mid-flight). Since
`Content` keeps the scenes, their shapes stay built.

Not on worker threads: background loads of these scenes raced the main thread for the same scripts
as the game or the test runner started, and deadlocked or failed to parse a scene. Where a
`SceneBatchLoader` does load on threads (the loading screen), `ContentRegistry.load_scene` waits on
a scene in flight with `ResourceLoader.load_threaded_get`; a plain `load()` of it can deadlock.

Write IDs as `StringName` literals (`&"b5:omega"`). They are compared faster than Strings, and that
is the type the registry uses.

Anything a designer might change per instance should be an exported ID property instead of a literal
in code. For example, every `Ship` has `launch_ship_id` (default `b5:aurora_starfury`), the craft it
launches from its hangars. To make the Omega launch something else, change that property in the
Inspector.

### 6. Run the tests

`tests/unit/test_content_registry.gd` includes `test_babylon5_manifest_resolves`, which loads every
ID in the Babylon 5 manifest and fails if any of them doesn't point at a real scene. A mistyped UID
fails here, not in the middle of a play-test.

```bash
$GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json
```

## Adding a new kind of content

To add something that isn't a ship or system (weapons, factions, music, ...), add a new section to
the manifest:

```ini
[weapon]
pulse_cannon="uid://..."
```

That gives you `b5:pulse_cannon` with kind `weapon`. `Content.instantiate()` only works for scenes;
for other resources use `load(Content.path_of(id))`.

## Overriding content (how mods will work)

If an ID is registered twice, the later registration wins, and the replacement is logged. Manifests
load in the order listed in `MANIFESTS` in `content/content.gd`, so a mod manifest listed after
`babylon5.cfg` can replace `b5:aurora_starfury` with its own Starfury by using the same ID in a
manifest with `namespace="b5"`. Everything that asks for that ID, including existing ships'
`launch_ship_id`, gets the mod's version.

To add a new manifest today, add its path to `MANIFESTS`. Later, mod pck files will register their
manifests as they load (see the design doc, *packaging*).

## Exports

Godot only exports files it recognises as resources, and a `.cfg` file isn't one. The export presets
in `export_presets.cfg` therefore include `content/*.cfg` in their include filter. If you put a
manifest anywhere else, add its folder to the include filter of every preset, or exported builds will
start with an empty registry.

## Current limitations

- `MANIFESTS` is a hard-coded list; there is no mod discovery yet.
- The `ShipSpawner` auto spawn list is maintained by hand (step 4).
- Kinds are labels only; nothing checks that a `ship` entry really is a `Ship` scene.
- Some engine scenes (characters, UI, the player node) are still loaded by path. That is deliberate:
  they are part of the engine, not content a mod would swap.
