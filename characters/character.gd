class_name Character
extends Node

# This getter setter chain is attempting to automagically assign the player the correct resource for
# network clients
## 0 (FactionRegistry.NO_FACTION) means no faction. Change membership with
## Faction.add_member() rather than setting this directly.
@export var faction_id: int:
	set(new_id):
		if new_id == faction_id:
			return
		faction_id = new_id
		var f := faction
		Log.log(["Character ", name, " faction: ", _faction_label(f), " (", faction_id, ")"], Log.MessageType.INFO)
## The faction for faction_id, or null (no faction, or no registry reachable yet).
var faction: Faction:
	get:
		var r := factions
		return r.get_by_id(faction_id) if r else null
## Set this to use a registry directly, for example in a unit test or before the
## character is in the tree. Otherwise the Galaxy above this node is used.
var faction_registry: FactionRegistry
var factions: FactionRegistry:
	get:
		if faction_registry:
			return faction_registry
		var galaxy := Galaxy.find_for(self)
		return galaxy.factions if galaxy else null
# If this is the player, set the id to 1 or more. 0 means an NPC.
@export var _player_pilot_id: int:
	set(new_id):
		_player_pilot_id = new_id
		_update_brain_active()
## The peer this character's player plays from (0 or the server's for NPCs).
## Changing it moves input authority too: a player who rejoins gets a new peer
## id (pilot_rejoined), and clients learn it from CharacterSync.
@export var multiplayer_id: int:
	set(id):
		_unregister_pilot()
		multiplayer_id = id
		_register_pilot()
		var sync := get_node_or_null("InputsSync")
		if sync:
			sync.set_multiplayer_authority(id)
			# The sync may not be in the tree yet (a spawn sets this mid-entry), so
			# compare ids rather than ask it is_multiplayer_authority().
			if is_inside_tree() and multiplayer.has_multiplayer_peer() and not multiplayer.is_server() \
					and id == multiplayer.get_unique_id():
				keep_inputs_local()
## Server: false while this character's player is disconnected (it stays in the
## world, controls neutral, until they log back in).
var player_connected := true
@export var pilot_id: int
var personality
var current_console: Console
## The console this character sits at, as a path from the character (empty when
## not seated). Console.occupy() runs on the server only; this is replicated
## (CharacterSync) so every client knows who sits where, including the pilot's
## own client, which needs its console to fly and send input.
@export var seat: NodePath:
	set(path):
		seat = path
		_resolve_seat()

@onready var hsm: LimboHSM = $BrainHSM # Later make behavior tree

@onready var inputs: InputSynchronizer:
	get:
		return get_node("InputsSync")

## The ship whose Crew node holds this character, or null.
var current_ship: Ship:
	get:
		var crew_node := get_parent()
		return crew_node.get_parent() as Ship if crew_node else null

@export var doctrine_var: StringName = &"doctrine"


var _brain_initialized := false


## Spawn data for a new crew member, in the format of [method serialize].
## Pass it to [method Ship.spawn_crew], which creates the character on the
## server and every client. [param pilot_id] comes from the world
## ([method WorldIds.next_pilot]).
static func pilot_data(pilot_name: String, faction: int, peer_id: int, pilot_id: int,
		player_pilot_id := 0) -> Dictionary:
	return {
		"name": pilot_name,
		"faction_id": faction,
		"multiplayer_id": peer_id,
		"_player_pilot_id": player_pilot_id,
		"pilot_id": pilot_id,
	}


func _ready():
	_init_brain()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server() \
			and $InputsSync.is_multiplayer_authority():
		keep_inputs_local()


func _init_brain() -> void:
	hsm = $BrainHSM
	var idle_state: LimboState = $BrainHSM/IdleState
	var moving_to_state: LimboState = $BrainHSM/MovingToConsoleState
	var operating_state: LimboState = $BrainHSM/OperatingConsoleState
	var moving_ship_state: LimboState = $BrainHSM/MovingToShipState
	var dead_state: LimboState = $BrainHSM/DeadState
	hsm.add_transition(idle_state, operating_state, &"move_console")
	hsm.add_transition(operating_state, idle_state, &"leave_console")
	hsm.add_transition(idle_state, moving_ship_state, "leave_ship")
	hsm.add_transition(moving_ship_state, idle_state, "enter_ship")
	hsm.add_transition(hsm.ANYSTATE, dead_state, "died")
	hsm.add_transition(dead_state, idle_state, "respawn")
	hsm.initial_state = idle_state
	hsm.initialize(self)
	_brain_initialized = true
	_update_brain_active()



## For logs: the faction name, "none" for no faction, or a note that the
## registry isn't reachable yet (not in the world).
func _faction_label(f: Faction) -> String:
	if f:
		return f.resource_name
	return "none" if faction_id == FactionRegistry.NO_FACTION else "not in world yet"


func is_player() -> bool:
	return _player_pilot_id > 0


## The brain only thinks for NPCs, and only where the simulation is authoritative.
## Players drive their character with inputs instead.
func _update_brain_active() -> void:
	# restore() can set _player_pilot_id before the node enters the tree.
	if not _brain_initialized:
		return
	hsm.set_active(multiplayer.is_server() and not is_player())


## A player's own client: its InputsSync goes to nobody. Remote pilots send
## input through InputChannel, so the server never reads it, and other clients
## draw the ship from snapshots. Sent to the server, its last packet reached a
## character freed at launch; sent everywhere (the server relays), it reached
## clients that don't have this character. Both logged "Node not found".
func keep_inputs_local() -> void:
	$InputsSync.public_visibility = false


func set_multiplayer_id(id):
	multiplayer_id = id  # The setter gives input authority to that peer.


## Server: this character's player disconnected. The character stays in the
## world; its controls go neutral (the server stops holding their last input),
## and a one-seat craft they fly brakes to a stop. (A crewed ship is left to its
## crew; an NPC may take the seat over later.)
func pilot_disconnected() -> void:
	player_connected = false
	input_channel = InputChannel.new()
	var helm := current_console.get_capability(HelmCapability) as HelmCapability if current_console else null
	var ship := current_ship
	if helm and ship and ship.has_node("Crew") and ship.get_node("Crew").max_crew <= 1:
		helm.bring_to_rest()


## Server: this character's player logged back in, from peer [param peer]: they
## fly it again. A fresh input channel, since the new client counts ticks anew.
func pilot_rejoined(peer: int) -> void:
	multiplayer_id = peer
	input_channel = InputChannel.new()
	_held_at_last_report = 0  # The input report counts from the new channel.
	_skipped_at_last_report = 0
	_first_remote_input_logged = false
	player_connected = true


func _resolve_seat() -> void:
	if is_inside_tree():
		current_console = get_node_or_null(seat) as Console if not seat.is_empty() else null


func _enter_tree() -> void:
	_register_pilot()
	_resolve_seat.call_deferred()  # The console may enter the tree after us.
	NetworkTime.before_tick_loop.connect(_read_input)
	NetworkTime.before_tick.connect(_apply_input)
	NetworkTime.after_tick_loop.connect(_trim_input_backlog)


func _exit_tree() -> void:
	_unregister_pilot()
	NetworkTime.before_tick_loop.disconnect(_read_input)
	NetworkTime.before_tick.disconnect(_apply_input)
	NetworkTime.after_tick_loop.disconnect(_trim_input_backlog)


## Once per tick loop: the player on this machine reads their controls into
## InputsSync (synced from the server for the host's player and NPCs; a remote
## pilot's go through InputChannel instead). Read once, not per tick: one
## frame can run several ticks, and the one-shot toggles would fire each time.
func _read_input() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.get_unique_id() == multiplayer_id:
		inputs.update()


## Server, after each tick loop: a real backlog of this player's input is
## skipped (InputChannel.trim_backlog), once the loop's ticks have used theirs.
func _trim_input_backlog() -> void:
	if input_source(multiplayer.is_server(), is_player(), _plays_here()) == InputSource.CHANNEL:
		input_channel.trim_backlog()


## Tick-stamped input (netcode slice N3a). On the pilot's own client it builds
## the packets to send; on the server it queues what arrives from that client.
var input_channel := InputChannel.new()
var _first_remote_input_logged := false
var _next_input_report_tick := 0
var _held_at_last_report := 0
var _skipped_at_last_report := 0


## Each tick, before ships fly (netcode slice N2): hand the input to the helm of
## the console this character sits at. A player on another machine is flown
## from their tick-stamped input (one per tick, in order), not from the
## InputsSync values, which carry no tick.
func _apply_input(_dt: float, tick: int) -> void:
	if not current_console:
		return
	var helm := current_console.get_capability(HelmCapability) as HelmCapability
	if not helm:
		return
	var r: Dictionary
	var source := input_source(multiplayer.is_server(), is_player(), _plays_here())
	if source == InputSource.CHANNEL and not player_connected:
		r = InputChannel.make_record(tick, Vector3.ZERO, Vector3.ZERO)  # Away: hands off.
	elif source == InputSource.CHANNEL:
		r = input_channel.next()
		if not _first_remote_input_logged and input_channel.last_applied_tick >= 0:
			_first_remote_input_logged = true
			Log.log(["First input from ", name, " applied (client tick ",
					input_channel.last_applied_tick, ")"], Log.MessageType.SUCCESS)
		if tick >= _next_input_report_tick and input_channel.last_applied_tick >= 0:
			_next_input_report_tick = tick + 300  # Every 5 s at 60 Hz.
			Log.log(["Input from ", name, ": ", input_channel.held_ticks - _held_at_last_report,
					" held, ", input_channel.skipped_ticks - _skipped_at_last_report, " skipped, ",
					input_channel.queued(), " queued, cushion ", input_channel.cushion],
					Log.MessageType.INFO)
			_held_at_last_report = input_channel.held_ticks
			_skipped_at_last_report = input_channel.skipped_ticks
	else:
		r = InputChannel.make_record(tick, inputs.throttle, inputs.rotation_throttle,
				inputs.autospin_toggle, inputs.autobreak_toggle, inputs.debug_all_stop, inputs.fire_primary,
				_view_ticks(tick))
		# One-shot: used once, even if this frame runs another tick.
		inputs.autobreak_toggle = false
		inputs.autospin_toggle = false
		if source == InputSource.LOCAL_AND_SEND:
			var galaxy := Galaxy.find_for(self)
			if galaxy:
				galaxy._submit_inputs.rpc_id(1, InputChannel.encode(input_channel.record(r)))
	if r.autobreak_toggle:
		helm.toggle_autobreak()
	if r.autospin_toggle:
		helm.toggle_autospin()
	helm.input_rotation_throttle = r.rotation_throttle
	helm.throttle = r.throttle
	if r.debug_all_stop and debug_commands_allowed():
		helm._debug_all_stop()
	var weapons := current_console.get_capability(WeaponsCapability) as WeaponsCapability
	if weapons:
		# A remote player's shots are checked against what they saw (W4).
		var system := System.find_for(self)
		var rewind := system.shots.rewind_for(tick, r.tick, r.view_ticks) if source == InputSource.CHANNEL and system else 0
		weapons.trigger(r.fire_primary, tick, rewind, r.tick if source == InputSource.CHANNEL else -1)


## Client: how many ticks behind [param tick] this machine is showing other
## ships (SnapshotClock), sent with the input so the server can check our shots
## against what we saw. 0 before any snapshots.
func _view_ticks(tick: int) -> int:
	var galaxy := Galaxy.find_for(self)
	if galaxy == null or not galaxy.snapshot_clock.has_estimate():
		return 0
	return clampi(roundi(tick - galaxy.snapshot_clock.render_tick(SnapshotClock.local_now())), 0, 255)


enum InputSource {
	LOCAL,  ## The InputsSync values: the host's own player, NPCs, others seen on a client.
	LOCAL_AND_SEND,  ## The pilot's own client: fly with it, and send it to the server.
	CHANNEL,  ## The server, for a player on another machine: their tick-stamped input.
}


## Where a character's input comes from each tick.
static func input_source(is_server: bool, player: bool, plays_here: bool) -> InputSource:
	if player and is_server and not plays_here:
		return InputSource.CHANNEL
	if player and plays_here and not is_server:
		return InputSource.LOCAL_AND_SEND
	return InputSource.LOCAL


## True when this character's player is at this machine.
func _plays_here() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer_id == multiplayer.get_unique_id()


## Server: registers this character as its player's pilot with the Galaxy
## (Galaxy.inputs_from finds it by peer). A player's, played from another
## machine: not NPCs, not the host's own.
func _register_pilot() -> void:
	if not is_inside_tree() or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if multiplayer_id <= 0 or multiplayer_id == multiplayer.get_unique_id():
		return
	var galaxy := Galaxy.find_for(self)
	if galaxy:
		galaxy.register_pilot(multiplayer_id, self)


func _unregister_pilot() -> void:
	if not is_inside_tree():
		return
	var galaxy := Galaxy.find_for(self)
	if galaxy:
		galaxy.unregister_pilot(multiplayer_id, self)


## Server: queues [param packet] if [param sender] is this character's player.
## Returns why not ("" when accepted).
func receive_inputs_from(sender: int, packet: Variant) -> String:
	if sender != multiplayer_id or not is_player():
		return "not this character's player"
	return input_channel.receive(packet)


func _physics_process(_dt: float) -> void:
	if current_console:
		if Input.is_action_just_released("camera_change") and _player_pilot_id == LocalGameManager.player_id:
			current_console.change_camera()
		# A commander's tree (ai/roles/command.tres) reads what it needs itself.


## Debug inputs (all-stop) count only for the player playing on this machine:
## the listen-server host, or anyone offline. A remote client's inputs reach the
## server too, and must not stop ships dead there.
func debug_commands_allowed() -> bool:
	if multiplayer.multiplayer_peer == null:
		return true
	return multiplayer_id == multiplayer.get_unique_id()


func _to_string() -> String:
	return name


func serialize() -> Dictionary:
	var payload:= {}
	# Personality
	# payload["personality"] = personality.resource_path
	
	# Blackboard. Object references (ships, factions, doctrine) are runtime
	# context rebuilt every tick, and cannot cross the network, so skip them.
	var blackboard: Blackboard = $BrainHSM.blackboard
	for key in blackboard.list_vars():
		var value = blackboard.get_var(key)
		if value is Object:
			continue
		payload["bb_" + key] = value
	
	# HSM
	if hsm.get_active_state():
		payload["hsm_state"] = hsm.get_active_state().name
	
	payload["name"] = name
	payload["faction_id"] = faction_id
	payload["_player_pilot_id"] = _player_pilot_id
	payload["multiplayer_id"] = multiplayer_id
	payload["pilot_id"] = pilot_id
	# Objectives are not part of a character: the world's ObjectiveBoard knows
	# what each pilot has claimed (claimed_by), by pilot ID.
	
	return payload


func restore(payload: Dictionary):
	## Restores state when spawning a node from a save or crew transfer
	
	if payload.has("personality"):
		personality = load(payload["personality"])
	
	for key in payload.keys():
		if key.begins_with("bb_"):
			var bb_key = key.trim_prefix("bb_")
			$BrainHSM.blackboard.set_var(bb_key, payload[key])
	
	name = payload["name"]
	faction_id = payload["faction_id"]
	_player_pilot_id = payload["_player_pilot_id"]
	multiplayer_id = payload["multiplayer_id"]
	pilot_id = payload["pilot_id"]
	
	#hsm.initialize(self)
	
