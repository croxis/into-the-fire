extends Resource
class_name Sensor

@export var name := ""
# Sensitive of 1.0 can detect a signal strength of 1 at 1 km.
@export var em_sensitive := 1.0
@export var neutrino_sensitive := 1.0
