class_name HitFlash
extends OmniLight3D
## A brief flash where a shot hit (ShotField.show_hit), fading out over
## SECONDS, then gone. Built in code: a light, nothing to collide or sync.

const SECONDS := 0.3
const ENERGY := 8.0

var _left := SECONDS


func _ready() -> void:
	light_color = Color(0.6, 0.95, 1.0)
	omni_range = 25.0
	light_energy = ENERGY


func _process(delta: float) -> void:
	_left -= delta
	light_energy = ENERGY * maxf(_left, 0.0) / SECONDS
	if _left <= 0.0:
		queue_free()
