extends HBoxContainer


signal request_launch


func _on_launch_pressed() -> void:
	Log.log(["Emmit signal: request_launch"], Log.MessageType.INFO)
	emit_signal("request_launch")
