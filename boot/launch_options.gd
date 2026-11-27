class_name LaunchOptions
extends RefCounted
## How this process was asked to run, parsed from the command line.
##
## Kept free of nodes and engine state so it can be unit tested: entry.gd passes
## in the arguments and what it knows about the display server.

enum Mode {
	CLIENT,  ## Title screen and main menu. Single player and host-and-play start here.
	DEDICATED,  ## Headless server, no local player.
	TEST_SERVER,  ## Hosts "Test Server" and plays (developer shortcut).
	TEST_PLAYER,  ## Joins the local test server after a delay (developer shortcut).
}

const DEFAULT_PORT := 2258
const DEFAULT_HOST := "127.0.0.1"

var mode: Mode = Mode.CLIENT
var game_name := "default"
var password := ""
var port := DEFAULT_PORT
## --max-rewind=MS (server): how far back, in milliseconds, a player's shots are
## checked against where they saw their target (favour the shooter). 0 to 1000.
var max_rewind_ms := 250
## --host=ADDRESS: the server a test player joins (IP or hostname). Defaults to
## this machine; set it when the test player runs on another device, e.g. a
## Steam Deck joining a --testserver on the dev machine.
var host := DEFAULT_HOST
var xr := false
## --faction=NAME: a test player spawns in this faction as soon as it joins,
## instead of waiting in the join menu (for automated two-process tests).
var faction := ""
## --spawn-at=NAME: with --faction, the spawn point (a ship with launch bays,
## e.g. "EASS Hyperion") to spawn at; empty means the first one offered.
var spawn_at := ""
## --name=NAME: the name a test player logs in as (two at once need two names:
## the server refuses a second login by one name).
var player_name := "Test Player"
## --launch: once aboard, a test player presses Launch by itself (for automated
## two-process tests of a remote pilot flying).
var launch := false
## --fire: once flying, a test player holds the trigger (automated weapons tests).
var fire := false
## --fly: once flying, a test player thrusts and turns in a fixed pattern
## (automated prediction tests: corrections while steering).
var fly := false
## The display server is "headless": no window, nothing on screen.
var headless := false
## Arguments that were not recognised, kept for logging.
var unknown: PackedStringArray = []


## Parses [param args] (as from [method OS.get_cmdline_args]).
## [param headless] is true when the display server is "headless".
## [param dedicated_feature] is true for exports with the dedicated_server feature.
static func parse(args: PackedStringArray, headless := false, dedicated_feature := false) -> LaunchOptions:
	var options := LaunchOptions.new()
	options.headless = headless
	var flags := {}
	for argument in args:
		if not argument.begins_with("--"):
			options.unknown.append(argument)
			continue
		var key := argument.substr(2)
		var value := ""
		var equals := key.find("=")
		if equals > -1:
			value = key.substr(equals + 1)
			key = key.substr(0, equals)
		flags[key] = value

	if flags.has("server") or dedicated_feature:
		options.mode = Mode.DEDICATED
	elif flags.has("testserver"):
		options.mode = Mode.TEST_SERVER
	elif flags.has("testplayer"):
		options.mode = Mode.TEST_PLAYER
	elif headless:
		# There is no screen to show a menu on, so the only useful thing to be is a server.
		options.mode = Mode.DEDICATED

	if flags.has("game") and flags["game"] != "":
		options.game_name = flags["game"]
	if flags.has("password"):
		options.password = flags["password"]
	if flags.has("port"):
		var p: String = flags["port"]
		if p.is_valid_int() and int(p) > 0 and int(p) < 65536:
			options.port = int(p)
		else:
			options.unknown.append("--port=" + p)
	if flags.has("max-rewind"):
		var m: String = flags["max-rewind"]
		if m.is_valid_int() and int(m) >= 0 and int(m) <= 1000:
			options.max_rewind_ms = int(m)
		else:
			options.unknown.append("--max-rewind=" + m)
	if flags.get("host", "") != "":
		options.host = flags["host"]
	options.xr = flags.has("xr_mode")
	options.faction = flags.get("faction", "")
	options.spawn_at = flags.get("spawn-at", "")
	if flags.get("name", "") != "":
		options.player_name = flags["name"]
	options.launch = flags.has("launch")
	options.fire = flags.has("fire")
	options.fly = flags.has("fly")

	for key in flags:
		if key not in ["server", "testserver", "testplayer", "game", "password", "port", "host", "xr_mode", "faction", "spawn-at", "launch", "fire", "fly", "max-rewind", "name"]:
			options.unknown.append("--" + key)
	return options


## Arguments for restarting the game with XR on or off (the in-game VR setting).
## OpenXR can only start with the engine, so switching means a restart.
## [param current] is [method OS.get_cmdline_args]: the engine has already
## removed its own flags from it (--xr-mode, --path), so they are added back.
## [param project_path] is needed when running from source, not when exported.
static func restart_args(current: PackedStringArray, xr_on: bool, project_path: String,
		exported: bool) -> PackedStringArray:
	var args := PackedStringArray()
	if not exported:
		args.append_array(["--path", project_path])
	for argument in current:
		# The old game flag would restart into the "start with --xr-mode on" hint.
		if argument != "--xr_mode":
			args.append(argument)
	if xr_on:
		args.append_array(["--xr-mode", "on"])
	return args


## True when this process shows menus and a game view.
func has_ui() -> bool:
	return mode != Mode.DEDICATED


## True when Discord rich presence should run: someone is playing on a screen.
## Not on servers or headless runs (tests, the smoke test, test players), nor
## when the Discord GDExtension failed to load ([param extension_loaded]), e.g.
## because a system library it links against is missing.
func wants_discord(extension_loaded := ClassDB.class_exists(&"DiscordClient")) -> bool:
	return extension_loaded and has_ui() and not headless


## The game window's title once this process hosts or joins: [param app] with
## the [param role] ("Host" or "Client") and the local player's name, so a host
## and clients side by side (tests, screenshots) can be told apart.
static func window_title(app: String, role: String, player_name: String) -> String:
	if player_name.is_empty():
		return "%s [%s]" % [app, role]
	return "%s [%s: %s]" % [app, role, player_name]


func _to_string() -> String:
	return "LaunchOptions(mode=%s game=%s port=%d xr=%s)" % [
		Mode.keys()[mode], game_name, port, xr]
