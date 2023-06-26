extends Control


func set_autobreak(autobreak):
	if autobreak:
		$VBoxContainer/AutoBreak.text = "Autobreak: On"
	else:
		$VBoxContainer/AutoBreak.text = "Autobreak: Off"


func set_autospin(autospin):
	if autospin:
		$VBoxContainer/AutoSpin.text = "Autospin: On"
	else:
		$VBoxContainer/AutoSpin.text = "Autospin: Off"


func set_acceleration(acceleration):
	$VBoxContainer/Gs.text = "G: %.1f Gs" % abs((acceleration/9.8))


func set_health(new_health: int):
	$VBoxContainer/Health.text = "HEALTH: " + str(new_health)


func set_speed(speed):
	$VBoxContainer/Speed.text = "SPEED: %.1f m/s" % speed
