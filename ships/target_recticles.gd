extends Node3D

# Camera
var camera: Camera3D

@onready var target_recticle: TextureRect = $TargetRecticle
@onready var offscreen_recticle: TextureRect = $OffscreenRecticle

# Attributes
var reticle_offset: Vector2
var viewport_center: Vector2
var border_offset := Vector2(64, 64)
var max_reticle_postion: Vector2


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	reticle_offset = target_recticle.size/2


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# These three lines could be called only on camera change and screen resize
	camera = $"..".camera
	viewport_center = Vector2(get_viewport().size) / 2.0
	max_reticle_postion = viewport_center - border_offset
	if camera.is_position_in_frustum(global_position):
		target_recticle.show()
		offscreen_recticle.hide()
		var reticle_position := camera.unproject_position(global_position)
		target_recticle.set_global_position(reticle_position - reticle_offset)
	else:
		target_recticle.hide()
		offscreen_recticle.show()
		var local_to_camera := camera.to_local(global_position)
		var reticle_position := Vector2(local_to_camera.x, -local_to_camera.y)
		if reticle_position.abs().aspect() > max_reticle_postion.aspect():
			reticle_position *= max_reticle_postion.x / abs(reticle_position.x)
		else:
			reticle_position *= max_reticle_postion.y / abs(reticle_position.y)
		offscreen_recticle.set_global_position(viewport_center + reticle_position - reticle_offset)
		var angle := Vector2.UP.angle_to(reticle_position)
		offscreen_recticle.rotation = angle
