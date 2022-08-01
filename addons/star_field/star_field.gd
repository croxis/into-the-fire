@tool
extends EditorPlugin


func _enter_tree():
	add_custom_type("StarField", "Node3D", preload("star_field_manager.gd"), preload("icon.png"))
	print("Addded type")


func _exit_tree():
	remove_custom_type("Star Field")
