extends Node3D


func _on_visibility_changed() -> void:
	$HYP_DOORS_DARK/StaticBody3D/CollisionShape3D.disabled = !visible
	$HYP_DOORS_LIGHT/StaticBody3D/CollisionShape3D.disabled = !visible
