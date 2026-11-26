#@tool
extends RigidBody3D
class_name Ship

@export var ship_id: int

## 0 (FactionRegistry.NO_FACTION) means no faction.
@export var faction_id: int:
	#TODO: Need to give the ship faction ownership. There needs to be rules on this.
	# Option 1: Ships are owned at the top level faction. Simple.
	# Option 2: Fancy permission system...
	# 1) Factions need some sort of permission control. If B5 owns a ship, can any earthforce fly it?
	# 2) If alpha wing member flies the B5 ship, the ownership should stay b5
	# 3) A ship can be gifted by the faction owner.
	# 4) A transfer can happen by parent faction commanders
	# For now....
	set(new_id):
		if new_id == faction_id:
			return
		# Ownership lists live on the factions. They only matter on the server, and
		# are only kept when the registry can be found (the ship is in the world).
		var old := faction
		if old:
			old.remove_ship(self)
		faction_id = new_id
		var f := faction
		if f:
			f.add_ship(self)
		Log.log(["Ship ", name, " faction: ", _faction_label(f), " (", faction_id, ")"], Log.MessageType.INFO)
## The faction for faction_id, or null (no faction, or no registry reachable yet).
var faction: Faction:
	get:
		var r := factions
		return r.get_by_id(faction_id) if r else null
## Set this to use a registry directly (unit tests). Otherwise the Galaxy above
## this ship is used.
var faction_registry: FactionRegistry
var factions: FactionRegistry:
	get:
		if faction_registry:
			return faction_registry
		var g := Galaxy.find_for(self)
		return g.factions if g else null

@export_node_path("Camera3D") var camera_path: NodePath
@onready var passenger_camera: Camera3D = get_node_or_null(camera_path)

@export var ship_class := ""

@export var max_health := 100
@export var is_station := false:
	set(set_station):
		if set_station:
			add_to_group("station")
		else:
			remove_from_group("station")
	get:
		return is_in_group("station")
@export var is_capital := false:
	set(set_capital):
		if set_capital:
			add_to_group("capital")
		else:
			remove_from_group("capital")
	get:
		return is_in_group("capital")
@export var has_spawn_points := false
## Content ID of the craft this ship launches from its spawn points.
@export var launch_ship_id: StringName = &"b5:aurora_starfury"

@export var sensor: Sensor
@onready var crew := $Crew

@export var em_output_base: float = 1.0
@export var neutron_output_base: float = 1.0
var em_output := 1.0
var neutron_output := 1.0

var detected_ships: Array[Ship] = []

var galaxy: Galaxy

var health := max_health:
	set(new_health):
		health = new_health
		if has_node("SubViewportCenter"):
			$SubViewportCenter/center_ui.set_health(health)
		if (health <= 0.0):
			destroy()
var engine_length = 7.5
#var thruster_force: Vector3 = Vector3(0, 0, 0)
#var thruster_torque: Vector3 = Vector3(0, 0, 0)
var acceleraction: Vector3 = Vector3(0, 0, 0)
var _debug_all_stop := false

var start_velocity := Vector3(0, 0, 0)

@export var local_angular_velocity: Vector3:
	get:
		return angular_velocity * global_basis

var is_spawning := false

## Motion reaches clients as tick-stamped snapshots (netcode slice N4b), not
## through the MultiplayerSynchronizer (it sends motion only when a ship
## appears): the server sends them every SNAPSHOT_TICKS, clients keep them here
## and draw the ship from them a little in the past (N4c, draw_remote).
## The pilot's own client predicts its ship instead and ignores them.
var snapshots := SnapshotBuffer.new(1.0 / 60.0)
## When snapshots arrive, so when to draw from them. Shared by every ship in
## the Galaxy (set in _ready); a ship on its own (tests) keeps its own.
var snapshot_clock := SnapshotClock.new()
var _drawn := false  # Client: drawn from snapshots, kinematic.
var _drawn_frames := 0  # Since the last drawing report.
var _drawn_behind := 0.0  # Summed ticks behind the newest snapshot.
var _drawn_past_newest := 0  # Frames drawn past the newest (extrapolated).
## Ticks between snapshots: 2 at 60 Hz, so 30 a second.
const SNAPSHOT_TICKS := 2
var _last_snapshot_tick := -SNAPSHOT_TICKS  # Server: the tick of the last snapshot sent.
var _peers_with_ship: Dictionary[int, bool] = {}  # Server: clients that confirmed they have this ship.
## Set to treat this ship as predicted on this machine (unit tests).
var prediction_forced := false
## Set to treat this machine as a client that draws this ship (unit tests).
var drawing_forced := false
## Who knows this ship, instead of Galaxy.interest (unit tests).
var interest_override: Interest
## Server: synchronizers given an interest filter, and whether it is the
## "held" one (true: they keep a node spawned) or the "known" one.
var _filtered: Dictionary[MultiplayerSynchronizer, bool] = {}


## True on the pilot's own client: a client, not the server, where the player
## at this ship's helm plays. The host never predicts (it has no latency).
func is_predicted_here() -> bool:
	if prediction_forced:
		return true
	if multiplayer.is_server():
		return false
	return local_pilot() != null


## The player on another machine who sits at one of this ship's helms, or null.
## The server sends them their ship's state (own-ship prediction).
func remote_pilot() -> Character:
	return _helm_player(false)


## The player at this machine who sits at one of this ship's helms, or null.
func local_pilot() -> Character:
	return _helm_player(true)


func _helm_player(here: bool) -> Character:
	if not has_node("Crew"):
		return null
	for c in $Crew.get_children():
		var character := c as Character
		if character and character.is_player() and character._plays_here() == here \
				and character.current_console \
				and character.current_console.get_capability(HelmCapability) \
				and is_ancestor_of(character.current_console):
			return character
	return null

signal destroyed(ship: Ship)


# Called when the node enters the scene tree for the first time.
func _ready():
	# If in editor simply disable processing as it's not needed here
	if (Engine.is_editor_hint()):
		set_physics_process(false)	
	can_sleep = false
	# Ships move by FlightIntegrator, not Jolt's force integration (see _fly).
	# Stations don't fly; Jolt keeps them as they are.
	custom_integrator = not is_station
	# What it gives off to others' sensors (fog of war); power use will vary it.
	em_output = em_output_base
	neutron_output = neutron_output_base
	#target_rot = rotation_degrees
	
	# No Galaxy when a ship runs on its own (tests, tools).
	galaxy = Galaxy.find_for(self)
	if galaxy:
		destroyed.connect(galaxy._on_ship_destroyed)
		snapshot_clock = galaxy.snapshot_clock
	# A client that now has this ship asks for its snapshots (see snapshot_recipients).
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server() \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_have_ship.rpc_id(1)
		if galaxy:
			galaxy.contact_regained(ship_id)  # Its ghost, if any, goes (N5c).



## For logs: the faction name, "none" for no faction, or a note that the
## registry isn't reachable yet (not in the world).
func _faction_label(f: Faction) -> String:
	if f:
		return f.resource_name
	return "none" if faction_id == FactionRegistry.NO_FACTION else "not in world yet"


func add_passenger(pilot: Character):
	if $Crew.add_passenger(pilot) and pilot.multiplayer_id:
		set_camera.rpc_id(pilot.multiplayer_id)
		Log.log(["Passenger added to ", name, " ", ship_id, " id ", pilot.multiplayer_id], Log.MessageType.INFO)
		set_capital_ui.rpc_id(pilot.multiplayer_id)


## Server only. Creates a crew member from [method Character.pilot_data] or
## [method Character.serialize] data. It goes through the CrewMultiplayerSpawner
## so every client gets the character too; a plain add_child() would exist only
## on the server. Returns null if the ship is full.
func spawn_crew(data: Dictionary) -> Character:
	if $Crew.get_child_count() >= $Crew.max_crew:
		Log.log(["No room for ", data.get("name"), " on ", name], Log.MessageType.WARNING)
		return null
	var pilot: Character = $CrewMultiplayerSpawner.spawn(data)
	Log.log(["Crew ", pilot.name, " spawned on ", name], Log.MessageType.INFO)
	if galaxy:
		galaxy.refresh_interest()  # Their client may only now know this ship (N5a2).
	if pilot.is_player():
		set_camera.rpc_id(pilot.multiplayer_id)
		set_capital_ui.rpc_id(pilot.multiplayer_id)
	return pilot


func get_crew() -> Array[Character]:
	var crew: Array[Character] = []
	for c in $Crew.get_children():
		crew.append(c)
	return crew


@rpc("call_local")
func set_camera():
	Log.log(["Setting Camera"], Log.MessageType.QUESTION)
	passenger_camera.far = 30000
	passenger_camera.near = 0.3
	passenger_camera.current = true


## Sent by the server to a player who boards this ship. Passengers on a capital
## ship or station get the passenger HUD (Launch), drawn in the main window.
@rpc("call_local")
func set_capital_ui():
	Log.log(["Is capital or station?", is_capital, ", ", is_station], Log.MessageType.INFO)
	if not galaxy:
		return
	if is_capital or is_station:
		galaxy.hud.show_passenger(self, _on_capital_ui_request_launch)
	else:
		galaxy.hud.hide_passenger(self)


@rpc("call_local")
func disable_capital_ui():
	if galaxy:
		galaxy.hud.hide_passenger(self)


func debug_set_health(new_health):
	health = new_health


func _integrate_forces(state: PhysicsDirectBodyState3D):
	if is_station:
		return
	if _debug_all_stop:
		state.angular_velocity = Vector3(0,0,0)
		state.linear_velocity = Vector3(0,0,0)
		_debug_all_stop = false


func _enter_tree() -> void:
	NetworkTime.on_tick.connect(_on_tick)
	NetworkTime.after_tick_loop.connect(_after_tick_loop)
	# Before the ship's spawner sees it, so the first spawn already asks Interest.
	if multiplayer.is_server():
		_follow_interest(self)
		var crew := get_node_or_null("Crew")
		if crew and not crew.child_entered_tree.is_connected(_follow_interest):
			crew.child_entered_tree.connect(_follow_interest)


# Interest management (netcode N5a2): this ship exists on a client, and is
# synced to it, only while Interest says so. Godot spawns a node on a peer while
# the synchronizers rooted at that node are visible to it, and sends each
# synchronizer's data only to peers it is visible to, so every one in the ship,
# its helms' and its crew's too, gets a filter. Two kinds, for the two steps of
# leaving (see Interest): the ship's own and its crew's keep them spawned while
# the client still holds the ship; the rest (helms, Babylon 5's rotation) stop
# as soon as it stops knowing it, along with the snapshots.

## Server: gives every synchronizer under [param node] (the ship, or a crew
## member as it boards) its interest filter, once each. Their visibility is then
## updated only when Interest changes (update_interest), not every frame.
func _follow_interest(node: Node) -> void:
	var syncs := node.find_children("*", "MultiplayerSynchronizer", true, false)
	if node is MultiplayerSynchronizer:
		syncs.append(node)
	for sync: MultiplayerSynchronizer in syncs:
		if _filtered.has(sync):
			continue
		var root := sync.get_node_or_null(sync.root_path)
		var held := root == self or root is Character
		_filtered[sync] = held
		sync.add_visibility_filter(is_held_by if held else is_known_to)
		sync.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE


## Server: whether client [param peer] is told about this ship and has
## confirmed it has it (_have_ship): it gets its snapshots and the syncs that
## aren't part of the spawn. Unreliable, they would overtake the spawn itself.
func is_known_to(peer: int) -> bool:
	var source := _interest()
	return _peers_with_ship.has(peer) and (source == null or source.knows(peer, self))


## Server: whether this ship exists on client [param peer]'s machine (known,
## or leaving).
func is_held_by(peer: int) -> bool:
	var source := _interest()
	return source == null or source.holds(peer, self)


## The Interest that decides, or null for a ship on its own (tools): then
## every client knows it.
func _interest() -> Interest:
	if interest_override:
		return interest_override
	var g := galaxy if galaxy else Galaxy.find_for(self)
	return g.interest if g else null


## Server: this ship's synchronizers in the order to update them when a client
## starts ([param shown]) or stops knowing it: the ship's own first when shown,
## so it spawns before anything inside it, and last when hidden, after its crew
## have despawned (a client must never hold crew without their ship).
func synchronizers_in_order(shown: bool) -> Array[MultiplayerSynchronizer]:
	var root: MultiplayerSynchronizer = $MultiplayerSynchronizer
	var crew: Array[MultiplayerSynchronizer] = []
	var others: Array[MultiplayerSynchronizer] = []
	for sync: MultiplayerSynchronizer in find_children("*", "MultiplayerSynchronizer", true, false):
		if sync == root:
			continue
		if has_node("Crew") and $Crew.is_ancestor_of(sync):
			crew.append(sync)
		else:
			others.append(sync)
	var out: Array[MultiplayerSynchronizer] = []
	if shown:
		out.append(root)
		out.append_array(others)
		out.append_array(crew)
	else:
		out.append_array(crew)
		out.append_array(others)
		out.append(root)
	return out


## Server: [param peer] now knows this ship, or no longer does ([param shown]);
## Godot spawns or despawns it there and starts or stops syncing. When it is
## [param despawned] there, the client's next copy must confirm itself again.
func update_interest(peer: int, shown: bool, despawned := false) -> void:
	if despawned:
		forget_peer_with_ship(peer)
	for sync in synchronizers_in_order(shown):
		sync.update_visibility(peer)


func _exit_tree() -> void:
	NetworkTime.on_tick.disconnect(_on_tick)
	NetworkTime.after_tick_loop.disconnect(_after_tick_loop)


## Own-ship prediction (netcode N3b/N3c): the pilot's client records its thrust
## here and replays it when the server's state arrives.
var prediction := ShipPrediction.new()
## Eases the server's corrections in over a few ticks instead of jumping (N4a).
var smoother := CorrectionSmoother.new()
var _corrections := 0  # Since the last prediction report.
var _largest_correction := 0.0
var _next_report_tick := 0
const PREDICTION_REPORT_TICKS := 300  # Every 5 s at 60 Hz.


func _after_tick_loop() -> void:
	if multiplayer.is_server():
		_send_pilot_state()
		var last_tick := NetworkTime.tick - 1  # The last tick just run.
		if _snapshot_due(last_tick):
			_last_snapshot_tick = last_tick
			var pilot := remote_pilot()
			var knows := Callable()
			if galaxy:
				knows = func(peer: int) -> bool: return galaxy.interest.knows(peer, self)
			for peer in snapshot_recipients(multiplayer.get_peers(), pilot.multiplayer_id if pilot else 0, knows):
				_receive_snapshot.rpc_id(peer, last_tick, global_transform, linear_velocity, angular_velocity)
	elif is_predicted_here() and NetworkTime.tick >= _next_report_tick:
		_next_report_tick = NetworkTime.tick + PREDICTION_REPORT_TICKS
		if _corrections:
			Log.log(["Prediction for ", name, ": ", _corrections, " corrections, largest ",
					"%.3f m" % _largest_correction], Log.MessageType.INFO)
		_corrections = 0
		_largest_correction = 0.0


## Server: whether a snapshot goes out after [param last_tick]. Counted from
## the last one sent, since a loop can run several ticks at once.
func _snapshot_due(last_tick: int) -> bool:
	return last_tick - _last_snapshot_tick >= SNAPSHOT_TICKS


## Server: the peers a snapshot goes to: those that asked for this ship's
## (they have it, so the RPC finds it) and are still [param connected], except
## [param pilot_peer], who predicts the ship and gets its own state, and any
## that [param knows] (peer -> bool, Galaxy.interest) says aren't told about it
## (netcode N5). Peers that left are forgotten.
func snapshot_recipients(connected: Array, pilot_peer: int, knows := Callable()) -> Array[int]:
	var out: Array[int] = []
	for peer in _peers_with_ship.keys():
		if not peer in connected:
			_peers_with_ship.erase(peer)
		elif peer != pilot_peer and (not knows.is_valid() or knows.call(peer)):
			out.append(peer)
	return out


func _add_peer_with_ship(peer: int) -> void:
	_peers_with_ship[peer] = true


## Server: the ship was despawned on [param peer]'s client.
func forget_peer_with_ship(peer: int) -> void:
	_peers_with_ship.erase(peer)


## Server: a client has this ship now (sent from its _ready there), so its
## snapshots and the syncs that aren't part of the spawn can start (N5a2). The
## peer comes from the sender, never from arguments.
@rpc("any_peer", "call_remote", "reliable")
func _have_ship() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	_add_peer_with_ship(peer)
	if _interest():
		update_interest(peer, true)


## Clients: this ship's state after server tick [param tick]. Unreliable and
## not ordered: SnapshotBuffer puts them in order, and a late one still fills
## its gap. ("unreliable_ordered" would have ENet drop any packet overtaken by
## a later one on its channel, which every ship's snapshots and the pilot's
## state share: under jitter that lost half of them.)
@rpc("authority", "call_remote", "unreliable")
func _receive_snapshot(tick: int, server_transform: Transform3D, server_velocity: Vector3,
		server_spin: Vector3) -> void:
	if multiplayer.is_server():
		return
	var s := FlightIntegrator.FlightState.new()
	s.transform = server_transform
	s.linear_velocity = server_velocity
	s.angular_velocity = server_spin
	take_snapshot(tick, s, _local_clock())


## Keeps a snapshot, which arrived at this client's tick [param local_now], for
## drawing the ship (draw_remote). The newest also sets the clock: a late one
## would make the server look further behind than it is. Ignored for the ship
## this client predicts.
func take_snapshot(tick: int, s: FlightIntegrator.FlightState, local_now: float) -> void:
	if is_predicted_here():
		return
	if not snapshots.push(tick, s) or tick != snapshots.newest_tick():
		return
	snapshot_clock.observe(tick, local_now)
	if snapshots.size() == 1:
		Log.log(["First snapshot for ", name, " (server tick ", tick, ")"], Log.MessageType.INFO)


## True on a client for a ship it doesn't predict: drawn from snapshots.
func is_drawn_here() -> bool:
	if is_predicted_here():
		return false
	return drawing_forced or not multiplayer.is_server()


## This machine's steady clock, in ticks (fractional: render frames fall
## between ticks), for SnapshotClock. Not NetworkTime.tick: netfox runs a
## client's ticks a little fast or slow to catch up with the server, and nor
## does it tick before a game starts, so snapshots measured against it said the
## server was further ahead than it was and ships were drawn past their newest.
func _local_clock() -> float:
	return SnapshotClock.local_now()


## Client, each frame: a ship nobody here predicts is drawn from its snapshots
## at the clock's moment, [constant SnapshotClock.DELAY_TICKS] behind the newest
## (netcode slice N4c), instead of being flown here. When this client starts
## predicting it (our player took the helm), it stays frozen until the server's
## first state for the pilot lets it go (reconcile_with), as on a launch arm.
func draw_remote(local_now: float) -> void:
	if not is_drawn_here():
		if _drawn:
			_drawn = false
			freeze_mode = RigidBody3D.FREEZE_MODE_STATIC  # As the launch arms freeze.
		return
	if snapshot_clock.has_estimate():
		var at := snapshot_clock.render_tick(local_now)
		if show_snapshots(at):
			_note_drawn(at)


## Client: every 5 s, how far behind its newest snapshot the ship was drawn and
## how often it ran past it (a late or lost snapshot, so extrapolated).
func _note_drawn(at: float) -> void:
	_drawn_frames += 1
	_drawn_behind += snapshots.newest_tick() - at
	if at > snapshots.newest_tick():
		_drawn_past_newest += 1
	if NetworkTime.tick >= _next_report_tick:
		_next_report_tick = NetworkTime.tick + PREDICTION_REPORT_TICKS
		Log.log(["Drawing ", name, ": ", "%.1f" % (_drawn_behind / _drawn_frames),
				" ticks behind the newest snapshot, ", _drawn_past_newest, " of ", _drawn_frames,
				" frames past it"], Log.MessageType.INFO)
		_drawn_frames = 0
		_drawn_behind = 0.0
		_drawn_past_newest = 0


## Puts the ship where its snapshots have it at server tick [param at],
## kinematic: Jolt doesn't fly it, but other bodies still hit it. Its velocities
## are zeroed: on a kinematic body they would be a conveyor-belt surface
## velocity. False with no snapshots of this ship yet (it stays as it spawned).
func show_snapshots(at: float) -> bool:
	var s := snapshots.sample(at)
	if s == null:
		return false
	if not _drawn:
		_drawn = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	place(s.transform)
	return true


## Server: tell the remote pilot where their ship is after the ticks just run,
## and which of their inputs that includes. Returns true when sent. A player who
## disconnected can still be seated here, so only connected peers are sent to.
func _send_pilot_state() -> bool:
	var pilot := remote_pilot()
	if pilot == null or pilot.input_channel.last_applied_tick < 0:
		return false
	if not pilot.multiplayer_id in multiplayer.get_peers():
		return false
	_receive_state.rpc_id(pilot.multiplayer_id, pilot.input_channel.last_applied_tick,
			global_transform, linear_velocity, angular_velocity, freeze)
	return true


## The pilot's client: the server's state after applying input [param ack].
## Start again from it and replay our own thrust since. Unreliable but ordered:
## a lost state is made up for by the next one.
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_state(ack: int, server_transform: Transform3D, server_velocity: Vector3,
		server_spin: Vector3, frozen := false) -> void:
	if not is_predicted_here():
		return
	var server := FlightIntegrator.FlightState.new()
	server.transform = server_transform
	server.linear_velocity = server_velocity
	server.angular_velocity = server_spin
	reconcile_with(server, ack, NetworkTime.tick - 1, frozen)


## The pilot's client: start again from [param server] (the server's state
## after applying input [param ack]) and replay our own ticks up to
## [param last_tick], the last one this client ran. While the server holds the
## ship [param frozen] (on a launch arm), the arm moves it, not the pilot: the
## client freezes it too and puts it exactly where the server has it, with no
## replay. Released, it is predicted again.
func reconcile_with(server: FlightIntegrator.FlightState, ack: int, last_tick: int,
		frozen := false) -> void:
	if frozen:
		if not prediction.confirm(ack):
			return  # Older than a state already used.
		freeze = true
		smoother.reset()
		place(server.transform)
		return
	if freeze:
		freeze = false  # Released by the arm.
	if flight == null:
		flight = FlightIntegrator.from_body(PhysicsServer3D.body_get_direct_state(get_rid()))
	var now := prediction.reconcile(server, ack, last_tick, flight, NetworkTime.ticktime, _replay_thrust)
	if now == null:
		return  # Older than a state already used.
	place(smoother.apply(global_transform, now.transform))
	var error := smoother.last_correction
	if error > 0.001:
		_corrections += 1
		_largest_correction = maxf(_largest_correction, error)
	linear_velocity = now.linear_velocity
	angular_velocity = now.angular_velocity


## Moves the ship to [param to] now, in Jolt as well as on the node. Setting
## global_transform alone isn't enough between ticks: Godot sends a node's new
## transform to the physics engine only at the start of the next physics frame,
## our ticks step the zone before that, and the step writes the old place back.
## (Velocity setters go to the physics engine at once.)
func place(to: Transform3D) -> void:
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, to)
	global_transform = to


## One netfox tick (netcode slice N2), in on_tick: characters have already
## handed this tick's input to the helms (before_tick); the zone steps after
## (after_tick, ZoneStepper).
func _on_tick(dt: float, tick: int) -> void:
	_rollback_tick(dt, tick, true)


## The ship's whole tick, in a fixed order: helms set thruster power, then the
## ship flies with it. Prediction (N3) will replay ticks through here.
func _rollback_tick(dt, tick, is_fresh):
	var helms := _helms()
	if is_predicted_here() and not is_station:
		# Recorded before the helms run (they write assisted throttle back), and
		# while frozen too: the server may already have let go of the ship.
		prediction.record(tick, helms.map(func(h: HelmCapability) -> Dictionary: return h.input_record()))
	for helm in helms:
		helm._rollback_tick(dt, tick, is_fresh)
	if is_station:
		return
	if custom_integrator and not freeze:  # Frozen: held by a launch arm.
		_fly(dt, tick)
	acceleraction = (linear_velocity - start_velocity) / dt
	start_velocity = linear_velocity


## Mass, inertia and centre of mass come from Jolt (worked out from the
## collision shapes). Made on first flight; set to null to re-read them after
## the shapes or mass change.
var flight: FlightIntegrator


## Sets this tick's velocities from the thrusters, before the physics step.
## Not in _integrate_forces: Godot calls that after the step, which would make
## thrust a tick late. Jolt then moves the ship and resolves contacts.
func _fly(dt: float, tick := 0) -> void:
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	if flight == null:
		flight = FlightIntegrator.from_body(state)
	var push := thrust(state.center_of_mass, global_transform.basis)
	var now := FlightIntegrator.FlightState.new()
	now.transform = global_transform
	now.linear_velocity = linear_velocity
	now.angular_velocity = angular_velocity
	var next := flight.step_velocity(now, push[0], push[1], dt)
	linear_velocity = next.linear_velocity
	angular_velocity = next.angular_velocity


## The helm capabilities of this ship's consoles, in console order.
func _helms() -> Array[HelmCapability]:
	var helms: Array[HelmCapability] = []
	for console in $Consoles.get_children():
		var helm := (console as Console).get_capability(HelmCapability) if console is Console else null
		if helm:
			helms.append(helm)
	return helms


## Replays (ShipPrediction): [force, torque] for the helms' recorded
## [param inputs] with the ship in [param s], worked out as a live tick does:
## flight assist from the replayed spin and speed, then the thrusters.
func _replay_thrust(inputs: Variant, s: FlightIntegrator.FlightState) -> Array[Vector3]:
	var helms := _helms()
	var to_ship := s.transform.basis.transposed()
	var local_velocity := to_ship * s.linear_velocity
	var local_spin := to_ship * s.angular_velocity
	for i in mini(helms.size(), (inputs as Array).size()):
		var throttles := helms[i].assist(inputs[i], local_velocity, local_spin, NetworkTime.ticktime)
		helms[i].system.request_thrust(throttles[0], throttles[1])
	return thrust(s.transform.basis * flight.center_of_mass_local, s.transform.basis)


## [force, torque] from all thrusters this tick, in world space; torque is about
## the centre of mass ([param center_of_mass]: offset from the ship's origin, in
## world axes), with the ship turned to [param basis]. The same sums Jolt made
## from apply_force at each thruster.
func thrust(center_of_mass: Vector3, basis: Basis) -> Array[Vector3]:
	var force := Vector3.ZERO
	var torque := Vector3.ZERO
	for thruster in $Engines.thrusters:
		var f: Vector3 = basis * thruster.force_vector
		force += f
		torque += (basis * thruster.position - center_of_mass).cross(f)
	return [force, torque]


func _process(_delta: float) -> void:
	if multiplayer.has_multiplayer_peer():
		draw_remote(_local_clock())
	#DebugDraw3D.draw_arrow_ray(global_position, target_rot, 32.0, Color.LAVENDER, 0.5)
	#DebugDraw3D.draw_arrow(global_position, global_position+Vector3(0,0,-2050), Color.MAGENTA, 32, false)
	#DebugDraw3D.draw_arrow(position, position+Vector3(0,2000,-2050), Color.MAGENTA, 32, false)
	#DebugDraw2D.set_text("Frames drawn", Engine.get_frames_drawn())


func bullet_hit(damage, bullet_global_trans):
	var BASE_BULLET_BOOST = 1
	var direction_vect = bullet_global_trans.basis.z.normalized() * BASE_BULLET_BOOST
	apply_impulse((bullet_global_trans.origin - global_transform.origin).normalized(), direction_vect * damage)
	health -= damage


func destroy() -> void:
	emit_signal("destroyed", self)
	if faction:
		faction.remove_ship(self)
	queue_free()


## [launch_point, position] for a free launch bay, or [] when none is free.
## launch_point has spawn_ship(ship). Each carrier's Spawner node implements it.
func find_free_spawner() -> Array:
	return $Spawner.find_free_spawner()


## Server only: a ship entering this one's dock area boards its crew here and is
## freed (replicated as a despawn). A client docking its own copy would free a
## ship the server still has.
func _on_area_3d_dock_body_entered(body) -> void:
	if not multiplayer.is_server():
		return
	if body == self:
		#can't dock with self, silly
		return
	if body is not Ship:
		return
	if body.is_spawning:
		return
	Log.log([body, " ship entered dock on ", name], Log.MessageType.INFO)
	for c in body.get_crew():
		add_passenger(c)
	body.queue_free()


func _on_crew_child_exiting_tree(_node: Node) -> void:
	return
	Log.log(["_on_crew_child_exiting_tree"], Log.MessageType.INFO)
	disable_capital_ui()


func _on_button_launch_pressed() -> void:
	var system_name := get_current_system().name
	galaxy.rpc("request_spawn", system_name, name)
	$CapitalShipControl.visible = false


func _on_capital_ui_request_launch() -> void:
	Log.log(["Asking to launch from ", name], Log.MessageType.INFO)
	request_launch.rpc_id(1)


## A client asks to launch from this ship. It carries no IDs on purpose: the
## server works out who asked from the connection, so nobody can launch someone
## else (or an NPC) by sending their ID.
@rpc("any_peer", "call_local")
func request_launch() -> void:
	if not multiplayer.is_server() or galaxy == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()  # The host asking itself.
	var player: Player = galaxy.get_node("Players").find_player_by_netid(sender)
	if player == null:
		Log.log(["Launch refused for peer ", sender, ": not logged in"], Log.MessageType.WARNING)
		return
	var refusal := launch_player(player.player_id, galaxy.ids)
	if refusal:
		Log.log(["Launch refused for ", player.name, " from ", name, ": ", refusal], Log.MessageType.WARNING)


## Server only. Launches player [param player_id]'s character from this ship in
## a new fighter. Returns why not ("" when launched). Everything is checked
## before anything is built.
func launch_player(player_id: int, ids: WorldIds) -> String:
	var passenger: Character = null
	for c in get_crew():
		if c._player_pilot_id == player_id:
			passenger = c
	if passenger == null:
		return "not aboard"
	if not $Spawner.has_method("find_free_spawner"):
		return "no launch bays"
	var spawn := find_free_spawner()
	if spawn.is_empty():
		return "no free launch bay"
	var new_ship := Content.instantiate(launch_ship_id) as Ship
	if new_ship == null:
		Log.log(["Cannot launch ", launch_ship_id, " from ", name], Log.MessageType.ERROR)
		return "no craft to launch"

	Log.log(["Launching ", passenger.name, " from ", name], Log.MessageType.QUESTION)
	new_ship.is_spawning = true
	#TODO: Pull ship from existing invetory using the id
	new_ship.ship_id = ids.next_ship()
	get_current_system().add_ship(new_ship)
	new_ship.global_transform.origin = spawn[1]
	spawn[0].spawn_ship(new_ship)
	new_ship.faction_id = passenger.faction_id  # Before it is shown: the pilot knows it through their side.
	# Show it to clients now (N5a2): not as it entered the world, since its spawn
	# goes with its place at that moment, and not after the pilot leaves this
	# ship, since a player between ships has no character and knows nothing. The
	# cockpit's RPCs below need the pilot's client to have it.
	if galaxy:
		galaxy.refresh_interest()
	var old_pilot: Character = $Crew.remove_passenger_by_id(player_id)
	var pilot: Character = new_ship.get_node("CrewMultiplayerSpawner").spawn(old_pilot.serialize())
	#TODO: Genealize this to a multicrew craft
	var cockpit: Console = new_ship.get_node("Consoles/Cockpit") as Console
	cockpit.occupy(pilot)
	old_pilot.queue_free()
	disable_capital_ui.rpc_id(pilot.multiplayer_id)
	_finish_launch(new_ship, pilot)
	return ""


## The launched craft is clear of the bay after a moment.
func _finish_launch(new_ship: Ship, pilot: Character) -> void:
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(new_ship):
		return
	new_ship.is_spawning = false
	for c in new_ship.get_node("Consoles").get_children():
		if c is Console:
			var helm := (c as Console).get_capability(HelmCapability) as HelmCapability
			if helm:
				helm.launch_completed()
	Log.log(["Spawn complete for ", pilot], Log.MessageType.SUCCESS)


## The star system this ship is in, or null (not placed yet).
func get_current_system() -> System:
	return System.find_for(self)


## Server: whether this ship's sensors pick up [param other_ship] now, kept in
## detected_ships. Each signature falls off with the square of the distance (in
## km: an output of 1.0 is a signal of 1.0 at 1 km). Higher sensitivity is
## better: sensitivity S picks up signals down to 1/S, so 0 is blind.
func sensor_check(other_ship: Ship) -> bool:
	var detected := false
	if sensor:
		var km_squared := global_position.distance_squared_to(other_ship.global_position) / 1e6
		#TODO: Calculate angular size of other ship. IF bigger than 1 degree, it is detected.
		var em_signal := other_ship.em_output / km_squared
		var neutrino_signal := other_ship.neutron_output / km_squared
		detected = em_signal * sensor.em_sensitive > 1.0 or neutrino_signal * sensor.neutrino_sensitive > 1.0
	if detected:
		if other_ship not in detected_ships:
			detected_ships.append(other_ship)
	else:
		detected_ships.erase(other_ship)
	return detected
