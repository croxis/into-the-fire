extends SubViewport
class_name System
## A star system: one zone. The SubViewport gives it its own World3D (rendering,
## physics space, audio); ships, bolts and spawners sit directly under it. It is
## never shown itself: ZoneView draws the viewed zone in the main window.

var ship_scan_timer := Timer.new()
## The shots flying here (weapons netcode).
var shots := ShotField.new(self)

func _ready():
	# The sky is placed by $StarField itself (anchor_star "Ran", 1.058 AU out:
	# Epsilon 3's distance from Ran) once the star catalogue has loaded.
	if multiplayer.is_server():
		ship_scan_timer.wait_time = 0.5
		ship_scan_timer.autostart = true
		ship_scan_timer.timeout.connect(ship_scanner_check)
		add_child(ship_scan_timer)  # A Timer only runs inside the scene tree.


## After this system's physics step for [param tick] (ZoneStepper): shots
## move on and, on the server, hit.
func after_step(tick: int) -> void:
	shots.record_history(tick)
	shots.step(tick)
	if tick % 300 == 0:  # Every 5 s at 60 Hz.
		var line := shots.report()
		if line:
			Log.log(["Shots in ", name, ": ", line], Log.MessageType.INFO)


func add_station(station: Ship):
	Log.log(["Adding station ", station, station.ship_id, " to system ", name], Log.MessageType.QUESTION)
	$ships.add_child(station, true)
	Log.log(["Added station ", station, station.ship_id, " to system ", name], Log.MessageType.SUCCESS)
	

func add_ship(ship: Ship):
	Log.log(["Adding ship ", ship, ship.ship_id, " to system ", name], Log.MessageType.QUESTION)
	$ships.add_child(ship, true)
	ship.owner = $ships
	Log.log(["Added ship ", ship, ship.ship_id, " to system ", name], Log.MessageType.SUCCESS)


## The System that [param node] is in, or null (not in a system yet).
static func find_for(node: Node) -> System:
	var n := node
	while n:
		if n is System:
			return n
		n = n.get_parent()
	return null


func get_ships() -> Array[Ship]:
	var ships: Array[Ship] = []
	for ship: Ship in $ships.get_children():
		ships.append(ship)
	return ships


## Server: names of the ships here with launch bays on [param faction]'s side,
## where its players can spawn (Galaxy._spawn_points; a client is told of no
## others, netcode N5b2). TODO: inventory, hyperspace, generated deep-space
## systems.
func spawn_points_for(faction: Faction) -> Array:
	var names := []
	for ship in get_ships():
		if ship.has_spawn_points and _on_side(ship, faction):
			names.append(String(ship.name))
	return names


## Server: the nearest capital ship or station here on [param pilot]'s side to
## [param destroyed], not counting it, or null: where the crew of a destroyed
## ship respawn. [param destroyed] is still listed here: it is only queued for
## freeing.
func nearest_carrier_for(pilot: Character, destroyed: Ship) -> Ship:
	if pilot.faction == null:
		return null
	var best: Ship = null
	var best_distance := INF
	for target in get_ships():
		if target == destroyed or not (target.is_capital or target.is_station):
			continue
		if not _on_side(target, pilot.faction):
			continue
		var d := target.global_position.distance_to(destroyed.global_position)
		if d < best_distance:
			best_distance = d
			best = target
	return best


## Client: puts [param marker] (a lost contact, Galaxy._contact_lost) in this
## system, replacing any ghost of the same ship.
func add_ghost(marker: GhostMarker) -> void:
	var ghosts: Node = get_node_or_null("Ghosts")
	if ghosts == null:
		ghosts = Node3D.new()
		ghosts.name = "Ghosts"
		add_child(ghosts)
	var old := ghosts.get_node_or_null(NodePath(marker.name))
	if old:
		old.free()
	ghosts.add_child(marker)


## Whether [param ship] is on [param faction]'s side: its own faction or one
## above it.
static func _on_side(ship: Ship, faction: Faction) -> bool:
	var side := ship.faction
	return side != null and (side == faction or faction.is_a_parent(side))


func ship_scanner_check():
	for ship: Ship in $ships.get_children():
		for other_ship: Ship in $ships.get_children():
			if ship != other_ship:
				ship.sensor_check(other_ship)
