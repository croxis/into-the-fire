extends Node3D

# Called when the node enters the scene tree for the first time.
func _ready():
	#DiscordRPC.state = "Main menu"
	#DiscordRPC.refresh()
	get_tree().get_root().get_node("entry").get_node("MainMenu").visible = true
	# $StarField places the sky near Ran itself (anchor_star in the scene).
	$AnimationPlayer.play("Camera")
	
