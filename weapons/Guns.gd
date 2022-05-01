extends Node3D

@export
var damage := 0.0
var fire = false


func _physics_process(dt: float) -> void:
	# Make sure this is the last part of the physics function because of the return!
	if get_node("../Inputs").fire_primary and is_multiplayer_authority():
		# Pew, fire only one gun. For now
		for gun in get_children():
			gun.fire(damage)
