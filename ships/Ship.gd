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

## What this ship gives off to others' sensors (fog of war), signal 1.0 at
## 1 km. The base EM stands for its subsystems' power use (no power system
## yet); its drive adds to it with thrust each tick (emissions_for).
@export var em_output_base: float = 1.0
## Neutrinos: esoteric ships only (Shadows, Vorlons). None today.
@export var neutron_output_base: float = 0.0
## Kept out of its side's shared picture (fog of war): where it is and what it
## detects are known only to its own crew (and to sides that detect it).
## Changed through Galaxy.check_exclusion_change.
@export var excluded_from_picture := false
## Its engines: what thrust gives off. Chemical unless the ship says otherwise.
@export var drive: DriveProfile = preload("res://ship_systems/drives/chemical.tres")
var em_output := 1.0
var neutron_output := 0.0
var gravimetric_output := 0.0

var detected_ships: Array[Ship] = []
var _visual_radius := -1.0  # Worked out once, from the body's shapes.

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

## Set to treat this ship as predicted on this machine (unit tests).
var prediction_forced := false
## The pilot's client: a launch arm here holds this ship (it is placed on the
## arm as drawn with the station, not at the server's frozen states).
var held_by_local_arm := false
## Server: which clients this ship exists on and is synced to (netcode N5a2).
var interest := ShipInterest.new(self)
## Its motion as snapshots: sent by the server, drawn on clients (N4b/N4c).
var snapshots := ShipSnapshots.new(self)
## Own-ship prediction: the server's states to the pilot, the pilot's client
## replaying its input from them (N3b/N3c).
var reconciler := ShipReconciler.new(self)


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
	_set_emissions(emissions_for(0.0))
	#target_rot = rotation_degrees
	
	# No Galaxy when a ship runs on its own (tests, tools).
	galaxy = Galaxy.find_for(self)
	if galaxy:
		destroyed.connect(galaxy._on_ship_destroyed)
		snapshots.clock = galaxy.snapshot_clock
	# A client that now has this ship asks for its snapshots (ShipSnapshots.recipients).
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
		interest.follow(self)
		var crew := get_node_or_null("Crew")
		if crew and not crew.child_entered_tree.is_connected(interest.follow):
			crew.child_entered_tree.connect(interest.follow)


func _exit_tree() -> void:
	NetworkTime.on_tick.disconnect(_on_tick)
	NetworkTime.after_tick_loop.disconnect(_after_tick_loop)


func _after_tick_loop() -> void:
	if multiplayer.is_server():
		reconciler.send_state()
		snapshots.send(NetworkTime.tick - 1)  # The last tick just run.
	elif is_predicted_here():
		reconciler.report()


## Server: a client has this ship now (sent from its _ready there), so its
## snapshots and the syncs that aren't part of the spawn can start (N5a2). The
## peer comes from the sender, never from arguments.
@rpc("any_peer", "call_remote", "reliable")
func _have_ship() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	interest.confirm(peer)
	if interest.source():
		interest.update(peer, true)


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
	snapshots.take(tick, s, SnapshotClock.local_now())


## The pilot's client: the server's state after applying input [param ack].
## ShipReconciler starts again from it and replays our own thrust since.
## Unreliable but ordered: a lost state is made up for by the next one.
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_state(ack: int, server_transform: Transform3D, server_velocity: Vector3,
		server_spin: Vector3, frozen := false, queued := -1, cushion := 0) -> void:
	if not is_predicted_here():
		return
	var server := FlightIntegrator.FlightState.new()
	server.transform = server_transform
	server.linear_velocity = server_velocity
	server.angular_velocity = server_spin
	reconciler.receive(ack, server, frozen, queued, cushion)


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
		reconciler.prediction.record(tick, helms.map(func(h: HelmCapability) -> Dictionary: return h.input_record()))
	for helm in helms:
		helm._rollback_tick(dt, tick, is_fresh)
	if is_station:
		return
	if custom_integrator and not freeze:  # Frozen: held by a launch arm.
		_fly(dt, tick)
	_set_emissions(emissions_for(ShipSensors.thrust_now(self)))
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
func replay_thrust(inputs: Variant, s: FlightIntegrator.FlightState) -> Array[Vector3]:
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
		snapshots.draw(SnapshotClock.local_now())
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


## A client asks to launch from this ship (ShipLaunch). It carries no IDs on
## purpose: the server works out who asked from the connection, so nobody can
## launch someone else (or an NPC) by sending their ID.
@rpc("any_peer", "call_local")
func request_launch() -> void:
	if not multiplayer.is_server() or galaxy == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()  # The host asking itself.
	ShipLaunch.request(self, sender)


## The star system this ship is in, or null (not placed yet).
func get_current_system() -> System:
	return System.find_for(self)


## What this ship gives off with [param thrust_newtons] of thrust, as (EM,
## neutrino, gravimetric). See ShipSensors.
func emissions_for(thrust_newtons: float) -> Vector3:
	return ShipSensors.emissions(em_output_base, neutron_output_base, drive, thrust_newtons)


func _set_emissions(e: Vector3) -> void:
	em_output = e.x
	neutron_output = e.y
	gravimetric_output = e.z


## How far this ship reaches from its origin, in metres, for visual detection
## (ShipSensors.reach). Worked out once its shapes exist.
func visual_radius() -> float:
	if _visual_radius < 0.0:
		_visual_radius = ShipSensors.reach(self)
	return maxf(_visual_radius, 0.0)


## Server: whether this ship's sensors pick up [param other_ship] now
## (ShipSensors.detects), kept in detected_ships.
func sensor_check(other_ship: Ship) -> bool:
	var detected := sensor != null and ShipSensors.detects(sensor, global_position, other_ship)
	if detected:
		if other_ship not in detected_ships:
			detected_ships.append(other_ship)
	else:
		detected_ships.erase(other_ship)
	return detected
