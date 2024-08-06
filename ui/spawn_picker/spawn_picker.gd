extends VBoxContainer

signal request_spawn(system_name, spawner_name)


func show_spawn(spawn_points: Dictionary) -> void:
	$Tree.clear()
	var root = $Tree.create_item()
	$Tree.set_column_title(0, "test")
	root.set_text(0, "ROOT")
	for system in spawn_points:
		var system_child = $Tree.create_item(root)
		system_child.set_text(0, system.name)
		system_child.set_selectable(0, false)
		for point in spawn_points[system]:
			var spawn_child = $Tree.create_item(system_child)
			spawn_child.set_text(0, point.name)
	visible = true
	queue_sort()


func _on_tree_item_selected():
	$SpawnButton.disabled = false


func _on_spawn_button_pressed():
	var selected = $Tree.get_selected()
	var spawn_name = selected.get_text(0)
	var system_name = selected.get_parent().get_text(0)
	print_debug("Client Requesting spawn")
	emit_signal("request_spawn", system_name, spawn_name)
	
