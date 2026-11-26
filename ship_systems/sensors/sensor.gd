extends Resource
class_name Sensor

@export var name := ""
## Higher is better: a sensitivity of S picks up signals down to 1/S. A ship's
## output of 1.0 is a signal of 1.0 at 1 km, falling off with the square of the
## distance, so sensitivity 1 sees it within 1 km and 100 within 10 km. 0 is blind.
@export var em_sensitive := 1.0
@export var neutrino_sensitive := 1.0
@export var gravametric_sensitive := 1.0
## Visual: a ship is seen when it looks wider than this many degrees (2 x
## atan(radius / distance)). At 1, a 50 m ship is seen within about 5.7 km.
## 0: no visual sensor.
@export var visual_acuity_degrees := 1.0
