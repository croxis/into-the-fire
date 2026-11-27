extends Node3D
## A ship's guns, fired together by a console's WeaponsCapability.

@export var damage := 0.0


## Fires every gun ready at [param tick] (each has its own cooldown).
func fire_at(tick: int, rewind := 0, client_tick := -1) -> void:
	for gun in get_children():
		if gun is Gun:
			gun.fire_at(tick, rewind, client_tick)
