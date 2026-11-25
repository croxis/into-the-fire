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

## Motion as the MultiplayerSynchronizer sends it, server to clients. On the
## pilot's own client this ship is predicted (ShipPrediction), so incoming
## values are ignored there; the server sends that client its own state instead.
var sync_position: Vector3:
	get:
		return position
	set(value):
		if not is_predicted_here():
			position = value
var sync_rotation: Vector3:
	get:
		return rotation
	set(value):
		if not is_predicted_here():
			rotation = value
var sync_linear_velocity: Vector3:
	get:
		return linear_velocity
	set(value):
		if not is_predicted_here():
			linear_velocity = value
var sync_angular_velocity: Vector3:
	get:
		return angular_velocity
	set(value):
		if not is_predicted_here():
			angular_velocity = value
## Set to treat this ship as predicted on this machine (unit tests).
var prediction_forced := false


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
	#target_rot = rotation_degrees
	
	# No Galaxy when a ship runs on its own (tests, tools).
	galaxy = Galaxy.find_for(self)
	if galaxy:
		destroyed.connect(galaxy._on_ship_destroyed)



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
	elif is_predicted_here() and NetworkTime.tick >= _next_report_tick:
		_next_report_tick = NetworkTime.tick + PREDICTION_REPORT_TICKS
		if _corrections:
			Log.log(["Prediction for ", name, ": ", _corrections, " corrections, largest ",
					"%.3f m" % _largest_correction], Log.MessageType.INFO)
		_corrections = 0
		_largest_correction = 0.0


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
	pass
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


func _on_area_3d_dock_body_entered(body) -> void:
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
	var old_pilot: Character = $Crew.remove_passenger_by_id(player_id)
	new_ship.faction_id = old_pilot.faction_id
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


func sensor_check(other_ship: Ship) -> bool:
	var detected := false
	var distance := global_position.distance_to(other_ship.global_position)
	#TODO: Calculate angular size of other ship. IF bigger than 1 degree, it is detected.
	var em_signal := other_ship.em_output / pow(distance/1000.0, 2) # Convert to km. Signal strength of 1.0 can be detected by a sensor of 1.0 at 1 km
	var neuteno_signal := other_ship.neutron_output / pow(distance/1000.0, 2)
	if em_signal > sensor.em_sensitive or neuteno_signal > sensor.neutrino_sensitive:
		detected = true
	if detected:
		if other_ship not in detected_ships:
			detected_ships.append(other_ship)
	else:
		detected_ships.erase(other_ship)
	return detected
