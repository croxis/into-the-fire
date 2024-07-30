extends VBoxContainer

signal request_faction(faction_name: String)


func build_faction_menu(factions: Node) -> void:
	$Tree.clear()
	$Tree.set_column_title(0, "Factions")
	var root = $Tree.create_item()
	root.set_text(0, "ROOT")
	build_tree(root, factions)
	visible = true
	queue_sort()


func build_tree(parent_node, parent_faction):
	for faction in parent_faction.get_children():
		if faction is Faction:
			var faction_child = $Tree.create_item(parent_node)
			faction_child.set_text(0, faction.name)
			if not faction.accept_players:
				faction_child.set_selectable(0, false)
			build_tree(faction_child, faction)
			

func _on_tree_item_selected():
	$JoinFactionButton.disabled = false


func _on_faction_button_pressed():
	var selected = $Tree.get_selected()
	var faction_name = selected.get_text(0)
	emit_signal("request_faction", faction_name)
	

func _on_factions_child_entered_tree(node):
	print("_on_factions_child_entered_tree: ", node)
