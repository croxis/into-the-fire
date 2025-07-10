extends VBoxContainer

signal request_spawn(faction_name: String, system_name: String, spawner_name: String)
signal request_faction(faction_name: String)

@onready var faction_tree := $HBoxContainer/FactionVBoxContainer/FactionTree
@onready var spawn_tree := $HBoxContainer/SpawnVBoxContainer/SpawnTree


func build_faction_menu() -> void:
	faction_tree.clear()
	faction_tree.set_column_title(0, "Factions")
	var root = faction_tree.create_item()
	root.set_text(0, "ROOT")
	for faction: Faction in Faction.factions.values():
		if not faction.parent_faction:
			build_faction_tree(root, faction)
	visible = true
	queue_sort()


func build_faction_tree(parent_node, faction):
	var faction_child = faction_tree.create_item(parent_node)
	faction_child.set_text(0, faction.resource_name)
	if not faction.accept_players:
		faction_child.set_selectable(0, false)
	for child in faction.get_children():
		build_faction_tree(faction_child, child)
			

func show_spawn(spawn_points: Dictionary) -> void:
	spawn_tree.clear()
	var root = spawn_tree.create_item()
	spawn_tree.set_column_title(0, "test")
	root.set_text(0, "ROOT")
	for system in spawn_points:
		var system_child = spawn_tree.create_item(root)
		system_child.set_text(0, system.name)
		system_child.set_selectable(0, false)
		for point in spawn_points[system]:
			var spawn_child = spawn_tree.create_item(system_child)
			spawn_child.set_text(0, point.name)
	visible = true
	queue_sort()


func _on_faction_tree_item_selected() -> void:
	var selected = faction_tree.get_selected()
	var faction_name = selected.get_text(0)
	emit_signal("request_faction", faction_name)


func _on_join_faction_button_pressed() -> void:
	var selected = spawn_tree.get_selected()
	var spawn_name = selected.get_text(0)
	var system_name = selected.get_parent().get_text(0)
	
	selected = faction_tree.get_selected()
	var faction_name = selected.get_text(0)
	emit_signal("request_spawn", faction_name, system_name, spawn_name)


func _on_spawn_tree_item_selected() -> void:
	#TODO: on clicking the different spawnpoints, the camera switches views
	$JoinFactionButton.disabled = false
