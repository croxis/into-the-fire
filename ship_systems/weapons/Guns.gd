extends Node3D

@export var damage := 0.0

#func _physics_process(_dt: float) -> void:
#	if $"../Crew".pilot:
#		if $"../Crew".pilot.get_node("InputsSync").fire_primary and is_multiplayer_authority():
#			# Pew, fire all guns. For now
#			for gun in get_children():
#				gun.fire(damage)

func fire():
	# Pew, fire all guns. For now
	for gun in get_children():
		gun.fire(damage)
