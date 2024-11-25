extends HBoxContainer


signal request_launch


func _on_launch_pressed() -> void:
	emit_signal("request_launch")
