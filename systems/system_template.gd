extends SubViewport
class_name System
## A star system: one zone. The SubViewport gives it its own World3D (rendering,
## physics space, audio); ships, bolts and spawners sit directly under it. It is
## never shown itself: ZoneView draws the viewed zone in the main window.

var ship_scan_timer := Timer.new()

func _ready():
	# The sky is placed by $StarField itself (anchor_star "Ran", 1.058 AU out:
	# Epsilon 3's distance from Ran) once the star catalogue has loaded.
	if multiplayer.is_server():
		ship_scan_timer.wait_time = 0.5
		ship_scan_timer.autostart = true
		ship_scan_timer.timeout.connect(ship_scanner_check)
		add_child(ship_scan_timer)  # A Timer only runs inside the scene tree.


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


func ship_scanner_check():
	for ship: Ship in $ships.get_children():
		for other_ship: Ship in $ships.get_children():
			if ship != other_ship:
				ship.sensor_check(other_ship)
