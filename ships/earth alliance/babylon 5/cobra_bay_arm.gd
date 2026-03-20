extends Node3D

var is_empty := false:
	get:
		if $"loading/loadingexternder/extender-rotating/spawn_point".get_child_count() == 0 and is_ready:
			return true
		return false

var is_ready := true

var ship: Ship


func _process(_delta: float) -> void:
	if ship:
		ship.global_transform = $"loading/loadingexternder/extender-rotating/spawn_point".global_transform


func spawn_ship(_newship: Ship):
	if not is_empty:
		Log.log(["NOT EMPTY!", name], Log.MessageType.WARNING)
		return
	ship = _newship
	ship.freeze = true
	is_ready = false
	$Timer.start()


func _on_timer_timeout() -> void:
	$AnimationPlayer.play("deploy")


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "deploy":
		ship.freeze = false
		# Angular velocity around b5 cobra bays is about 30 m/s
		ship.linear_velocity = -ship.global_transform.basis.z.normalized() * 30.0
		#ship.reparent(target_node)
		#ship.owner = target_node
		ship = null
		$AnimationPlayer.play("return")
	if anim_name == "return":
		is_ready = true
