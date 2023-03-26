extends Control


func set_acceleration(acceleration):
	$VBoxContainer/Gs.text = "G: %.1f Gs" % abs((acceleration/9.8))


func set_health(new_health: int):
	$VBoxContainer/Health.text = "HEALTH: " + str(new_health)


func set_speed(speed):
	$VBoxContainer/Speed.text = "SPEED: %.1f m/s" % speed
