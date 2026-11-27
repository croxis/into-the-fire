class_name Galaxy
extends Node

var game_name := "default"
var active_galaxy := false

## The scenario a new game starts from (content ID, kind "scenario").
@export var scenario_id: StringName = &"b5:playtest"
var _scenario: Scenario
var _scenario_scenes: SceneBatchLoader  # Held from loading until populate() runs.

## Ship and pilot IDs for this world.
var ids := WorldIds.new()

## Draws the zone the local player is in. Unused on a dedicated server.
var zone_view := ZoneView.new()
## The local player's HUD (passenger HUD for now). Empty on a dedicated server.
var hud := HudLayer.new()
## Steps every system's physics space (zones), on server and clients.
var zone_stepper := ZoneStepper.new()
## This world's zones (star systems): which exist and who is in each.
@onready var zones: Zones = $Zones
## Where players come in and where crews go when their ship is destroyed.
var spawns := SpawnService.new(self)
## Server: how far back players' shots are checked (favour the shooter), in
## ticks; given to each system's ShotField. From --max-rewind.
var max_rewind_ticks := ShotField.DEFAULT_REWIND_TICKS
## Server: each remote player's pilot by the peer they play from (Character
## registers itself), so their inputs find it whatever ship it is in now.
var _pilots: Dictionary = {}  # int -> Character. Untyped: a value may be freed.
## Client: when ships' snapshots arrive, so when to draw them (netcode N4c).
var snapshot_clock := SnapshotClock.new()
## Client: how far ahead of server time the pilot's inputs are sent (time
## dilation; steered from the server's reports, see InputLead).
var input_lead := InputLead.new(1.0 / 60.0)
## Client: ships this player's side lost contact with, and their ghosts (N5c).
var contacts := ContactLog.new(1.0 / 60.0)
## Server: which ships each client is told about (netcode N5). Kept up to date
## by fog (FogOfWar.refresh).
var interest := Interest.new()
## Fog of war: what each client may know, and the ghosts of lost contacts.
var fog := FogOfWar.new(self)
## Server: FogOfWar.refresh has just run.
signal interest_refreshed()

## Every faction in this world. The server creates them; clients receive a copy
## when they join (see _rpc_receive_factions). Replaced as a whole, never patched
## from client data.
var factions := FactionRegistry.new()
var _factions_synced := false  # Client: a faction copy has arrived from the server.

## Emitted on clients when a faction copy arrives from the server.
signal factions_synced()
## This machine's player has entered the world (joined, or hosts it) and may
## pick where to spawn, once factions_ready(). The join UI (JoinFlow) listens.
signal ready_to_spawn()
## Asks the loading screen to load [param paths] in the background; it calls
## [param callback] with the finished SceneBatchLoader.
signal load_scenes(paths: PackedStringArray, callback: Callable)


## Client: shows [param system_name], the system this machine's player is now
## in (SpawnService tells it), and notes who the local player is.
func view_system(system_name: String) -> void:
	var system := zones.get_system(system_name)
	if system == null:
		Log.log(["No system ", system_name, " here to enter"], Log.MessageType.WARNING)
		return
	zone_view.view(system)
	var w0 := get_viewport()
	#Music Hack
	system.get_node("AudioStreamPlayer").playing = true
	# This runs on the spawning player's own machine, so look up the local peer
	# (the sender is always the server).
	var player: Player = $Players.find_player_by_netid(multiplayer.get_unique_id())
	if player == null:
		Log.log(["No Player for this peer yet; local player id not set"], Log.MessageType.WARNING)
		return
	LocalGameManager.player_id = player.player_id


## The Galaxy that [param node] lives under, or null when there is none (the
## node isn't in the tree yet, or it is running alone in a unit test).
static func find_for(node: Node) -> Galaxy:
	var n := node
	while n:
		if n is Galaxy:
			return n
		n = n.get_parent()
	return null


func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	zone_view.name = "ZoneView"
	add_child(zone_view)
	add_child(hud)
	add_child(zone_stepper)
	add_child(spawns)
	zones.stepper = zone_stepper
	zones.zone_added.connect(func(system: System) -> void:
			system.shots.max_rewind_ticks = max_rewind_ticks)


## Server: send the faction tree to a client that just connected.
## (peer_connected also fires on clients when other peers join; they ignore it.)
func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_rpc_receive_factions.rpc_id(peer_id, factions.to_data())
		var player: Player = $Players.find_player_by_netid(peer_id)
		var character := zones.player_character(player.player_id) if player else null
		if character:
			spawns.resume(character, peer_id)
		else:
			fog.refresh()  # So its ships spawn there now, not up to 0.5 s later.


## Server: a peer left. A player's character stays in the world, hands off the
## controls, until they log back in (Character.pilot_disconnected).
func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for character in zones.characters_of_peer(peer_id):
		character.pilot_disconnected()
		Log.log([character.name, " left; their character stays"], Log.MessageType.INFO)


## Client: replace the local copy with the server's.
## "authority" means only the server may call this, so a client can't push
## factions to other peers. The data is plain dictionaries, not objects.
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_factions(data: Dictionary) -> void:
	factions = FactionRegistry.from_data(data)
	_factions_synced = true
	Log.log(["Received ", factions.size(), " factions from server"], Log.MessageType.INFO)
	factions_synced.emit()


## True once there are factions to pick from: the server's own, or on a client
## the copy the server sent.
func factions_ready() -> bool:
	return multiplayer.is_server() or _factions_synced


func setup_new_galaxy(dedicated=false, callback = null):
	Log.log(["Setting up galaxy."], Log.MessageType.QUESTION)
	if dedicated:
		callback = Callable(self, "finish_setup_galaxy_all")
	# Only the machine that runs the world builds it; clients get theirs from
	# the server's spawners. Asked of this world's own multiplayer, not of entry.
	if not active_galaxy and multiplayer.is_server():
		if not _start_scenario(callback):
			return
		active_galaxy = true
		Log.log(["Galaxy setup complete."], Log.MessageType.INFO)
	else:
		print("Galaxy already initalized")


## Server: checks the scenario, creates its factions and starts loading its
## systems. [param callback] runs once every system is in the tree.
func _start_scenario(callback) -> bool:
	_scenario = load(Content.path_of(scenario_id)) as Scenario
	if _scenario == null:
		Log.log(["Scenario ", scenario_id, " not found"], Log.MessageType.ERROR)
		return false
	var errors := ScenarioLoader.validate(_scenario, Content.registry)
	if not errors.is_empty():
		Log.log(["Scenario ", scenario_id, " is invalid: ", "; ".join(errors)], Log.MessageType.ERROR)
		return false
	factions = ScenarioLoader.build_factions(_scenario)
	ids = WorldIds.new()
	# Every system and ship scene at once, on worker threads, so populate()
	# later instantiates from the cache instead of reading files on this thread.
	load_scenes.emit(ScenarioLoader.scene_paths(_scenario, Content.registry),
			_on_scenario_scenes_loaded.bind(callback))
	return true


## Adds the scenario's systems, in order, then runs [param callback].
func _on_scenario_scenes_loaded(batch: SceneBatchLoader, callback) -> void:
	_scenario_scenes = batch  # Keeps the ship scenes cached until populate().
	for id in _scenario.systems:
		var scene := batch.scenes.get(Content.path_of(id)) as PackedScene
		if scene == null:
			Log.log(["Scenario system ", id, " failed to load"], Log.MessageType.ERROR)
			continue
		zones.add_system(scene.instantiate())
	if callback:
		callback.call()


func _on_main_menu_new_game(g_name, _player_name, _port, _server_password, _player_password):
	game_name = g_name
	var callback := Callable(self, "finish_setup_galaxy_client")
	setup_new_galaxy(false, callback)


func finish_setup_galaxy_all() -> void:
	if not multiplayer.is_server():
		_scenario_scenes = null
		return
	var systems := {}
	for id in _scenario.systems:
		systems[id] = zones.system_for_content(id)
	ScenarioLoader.populate(_scenario, Content.registry, factions, systems, ids,
			multiplayer.get_unique_id())
	_scenario_scenes = null  # Placed ships hold their own references now.


func finish_setup_galaxy_client():
	ready_to_spawn.emit()
	finish_setup_galaxy_all()


func _process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		fog.process(delta)


## The server tick [param node]'s machine shows things at now (fractional): the
## server's own tick, or on a client the moment it draws remote ships at
## (snapshot_clock), so clock-driven parts of a station (Babylon 5's rotation,
## its launch arms) are where the server has them at that moment.
static func shown_tick(node: Node) -> float:
	if not node.multiplayer.has_multiplayer_peer() or node.multiplayer.is_server():
		return NetworkTime.tick + NetworkTime.tick_factor
	var galaxy := find_for(node)
	if galaxy and galaxy.snapshot_clock.has_estimate():
		return galaxy.snapshot_clock.render_tick(SnapshotClock.local_now())
	return NetworkTime.tick + NetworkTime.tick_factor


## Client: the server says this player's side lost contact with [param ship_id]
## (it is about to be despawned here): FogOfWar.lost.
@rpc("authority", "call_remote", "reliable")
func _contact_lost(ship_id: int, data: Dictionary) -> void:
	fog.lost(ship_id, data)


func _on_network_connection_succeeded() -> void:
	finish_setup_galaxy_client()


## Server: [param pilot] now plays from [param peer] (it entered the world, or
## its player rejoined on a new connection).
func register_pilot(peer: int, pilot: Character) -> void:
	_pilots[peer] = pilot


## Server: [param pilot] no longer plays from [param peer] (it left the world:
## its ship destroyed, docked, its player gone). Only if it is still the one.
func unregister_pilot(peer: int, pilot: Character) -> void:
	if _pilots.get(peer) == pilot:
		_pilots.erase(peer)


## A remote player's inputs (InputChannel.encode). Sent to the Galaxy, which
## always exists, not to their Character: inputs still in flight when its ship
## is destroyed would find no node there (an engine error each). The pilot is
## the sender's, from the connection. Sent every tick, unreliable: a lost packet
## is covered by the next, which repeats the last few inputs.
@rpc("any_peer", "call_remote", "unreliable")
func _submit_inputs(packet: Variant) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var refusal := inputs_from(sender, packet)
	if refusal and refusal != NO_PILOT:
		Log.log(["Input from peer ", sender, " refused: ", refusal], Log.MessageType.WARNING)


const NO_PILOT := "no pilot"


## Server: queues [param packet] for [param sender]'s pilot. Returns why not
## ("" when queued). No pilot (not spawned yet, or just died with inputs in
## flight) is not worth a warning: NO_PILOT.
func inputs_from(sender: int, packet: Variant) -> String:
	var pilot: Variant = _pilots.get(sender)
	if pilot == null or not is_instance_valid(pilot) or not (pilot as Character).is_inside_tree():
		return NO_PILOT
	return (pilot as Character).receive_inputs_from(sender, InputChannel.decode(packet))
