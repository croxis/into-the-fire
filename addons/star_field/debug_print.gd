extends Control

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


func _on_star_field_star_debug(message):
	print("DEBUG: " + str(message))
