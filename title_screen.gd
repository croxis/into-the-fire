extends Node3D

# Called when the node enters the scene tree for the first time.
func _ready():
	#print(get_tree().get_root().get_children())
	get_tree().get_root().get_node("entry").get_node("MainMenu").visible = true

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass