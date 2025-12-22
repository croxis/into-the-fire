extends SubViewportContainer
class_name System

var ship_scan_timer := Timer.new()

func _ready():
	var ran = $SubViewport/StarField.get_star_proper("Ran")
	var ran_position = Vector3(ran['x'].to_float(), ran['y'].to_float(), ran['z'].to_float())
	ran_position.z += $SubViewport/StarField.AU_IN_PARSEC * 1.058  # Distance of epsilon 3 to RAN
	$SubViewport/StarField.celestial_coords = ran_position
	$SubViewport/StarField.mag_ref = 7.0
	$SubViewport/StarField.mag_limit = 7.0
	
	if multiplayer.is_server():
		ship_scan_timer.wait_time = 0.5
		ship_scan_timer.autostart = true
		ship_scan_timer.timeout.connect(ship_scanner_check)


func add_station(station: Ship):
	Log.log(["Adding station ", station, " to system ", name], Log.MessageType.QUESTION)
	$SubViewport/ships.add_child(station, true)
	Log.log(["Added station ", station, " to system ", name], Log.MessageType.SUCCESS)
	

func add_ship(ship: Ship):
	Log.log(["Adding ship ", ship, " to system ", name], Log.MessageType.QUESTION)
	$SubViewport/ships.add_child(ship, true)
	Log.log(["Added ship ", ship, " to system ", name], Log.MessageType.SUCCESS)


func ship_scanner_check():
	for ship: Ship in $SubViewport/ships.get_children():
		for other_ship: Ship in $SubViewport/ships.get_children():
			if ship != other_ship:
				ship.sensor_check(other_ship)
			
			
