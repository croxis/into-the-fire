extends SubViewportContainer


func _ready():
	var ran = $SubViewport/StarField.get_star_proper("Ran")
	var ran_position = Vector3(ran['x'].to_float(), ran['y'].to_float(), ran['z'].to_float())
	ran_position.z += $SubViewport/StarField.AU_IN_PARSEC * 1.058  # Distance of epsilon 3 to RAN
	$SubViewport/StarField.celestial_coords = ran_position
	$SubViewport/StarField.mag_ref = 7.0
	$SubViewport/StarField.mag_limit = 7.0


func add_station(station: Ship):
	Logger.log(["Adding station ", station, " to system ", name], Logger.MessageType.QUESTION)
	$SubViewport/stations.add_child(station)
	Logger.log(["Added station ", station, " to system ", name], Logger.MessageType.SUCCESS)
	

func add_ship(ship: Ship):
	Logger.log(["Adding ship ", ship, " to system ", name], Logger.MessageType.QUESTION)
	$SubViewport/ships.add_child(ship)
	Logger.log(["Added shipn ", ship, " to system ", name], Logger.MessageType.SUCCESS)
