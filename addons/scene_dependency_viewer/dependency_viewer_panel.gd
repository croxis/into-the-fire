@tool
extends Control

const DependencyScannerClass = preload("res://addons/scene_dependency_viewer/dependency_scanner.gd")

var scanner: DependencyScannerClass
var scan_result: Dictionary = {}
var selected_file: String = ""

# UI references (created in code)
var scan_button: Button
var refresh_button: Button
var search_field: LineEdit
var filter_option: OptionButton
var tree: Tree
var info_label: RichTextLabel
var broken_refs_list: ItemList
var unused_list: ItemList
var tab_container: TabContainer
var progress_label: Label

func _ready() -> void:
	_build_ui()

	scanner = DependencyScannerClass.new()
	scan_button.pressed.connect(_on_scan_pressed)
	refresh_button.pressed.connect(_on_scan_pressed)
	search_field.text_changed.connect(_on_search_changed)
	filter_option.item_selected.connect(_on_filter_changed)
	tree.item_selected.connect(_on_tree_item_selected)
	broken_refs_list.item_selected.connect(_on_broken_ref_selected)
	unused_list.item_selected.connect(_on_unused_selected)

	_setup_filter_options()
	progress_label.text = "Ready. Click Scan to analyze project dependencies."


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "MainVBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(vbox)

	# Toolbar
	var toolbar := HBoxContainer.new()
	toolbar.custom_minimum_size.y = 32
	vbox.add_child(toolbar)

	scan_button = Button.new()
	scan_button.text = "Scan Project"
	scan_button.custom_minimum_size.x = 100
	toolbar.add_child(scan_button)

	refresh_button = Button.new()
	refresh_button.text = "Refresh"
	refresh_button.custom_minimum_size.x = 80
	toolbar.add_child(refresh_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	var search_label := Label.new()
	search_label.text = "Filter:"
	toolbar.add_child(search_label)

	search_field = LineEdit.new()
	search_field.placeholder_text = "Search files..."
	search_field.custom_minimum_size.x = 200
	toolbar.add_child(search_field)

	filter_option = OptionButton.new()
	filter_option.custom_minimum_size.x = 120
	toolbar.add_child(filter_option)

	# Main split
	var hsplit := HSplitContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.split_offset = 400
	vbox.add_child(hsplit)

	# Left panel - tabs
	var left_panel := VBoxContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.6
	hsplit.add_child(left_panel)

	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(tab_container)

	# Tab 1: Tree
	var tree_tab := VBoxContainer.new()
	tree_tab.name = "Dependencies"
	tab_container.add_child(tree_tab)

	tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.hide_root = false
	tree_tab.add_child(tree)

	# Tab 2: Broken References
	var broken_tab := VBoxContainer.new()
	broken_tab.name = "Broken Refs"
	tab_container.add_child(broken_tab)

	broken_refs_list = ItemList.new()
	broken_refs_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	broken_refs_list.allow_reselect = true
	broken_tab.add_child(broken_refs_list)

	# Tab 3: Unused Assets
	var unused_tab := VBoxContainer.new()
	unused_tab.name = "Unused Assets"
	tab_container.add_child(unused_tab)

	unused_list = ItemList.new()
	unused_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	unused_list.allow_reselect = true
	unused_tab.add_child(unused_list)

	# Right panel - info
	var right_panel := VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.4
	hsplit.add_child(right_panel)

	info_label = RichTextLabel.new()
	info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_label.bbcode_enabled = true
	info_label.text = "Select a file to view its dependencies."
	right_panel.add_child(info_label)

	# Progress bar
	progress_label = Label.new()
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.text = "Ready."
	vbox.add_child(progress_label)


func _setup_filter_options() -> void:
	filter_option.clear()
	filter_option.add_item("All Files", 0)
	filter_option.add_item("Scenes (.tscn)", 1)
	filter_option.add_item("Resources (.tres)", 2)
	filter_option.add_item("Scripts (.gd/.cs)", 3)
	filter_option.add_item("Textures", 4)
	filter_option.add_item("Audio", 5)
	filter_option.add_item("Models", 6)


func _on_scan_pressed() -> void:
	scan_button.disabled = true
	refresh_button.disabled = true
	progress_label.text = "Scanning project..."
	tree.clear()
	broken_refs_list.clear()
	unused_list.clear()
	scan_result = {}

	call_deferred("_run_scan")


func _run_scan() -> void:
	scan_result = await scanner.scan_project()
	_populate_ui()
	scan_button.disabled = false
	refresh_button.disabled = false


func _on_scan_completed(result: Dictionary) -> void:
	scan_result = result
	progress_label.text = "Scan complete. %d files analyzed." % result.files.size()


func _populate_ui() -> void:
	_populate_tree()
	_populate_broken_refs()
	_populate_unused()
	progress_label.text = "Scan complete. %d files, %d broken refs, %d unused." % [
		scan_result.files.size(),
		scan_result.broken_refs.size(),
		scan_result.unused_assets.size()
	]


func _populate_tree() -> void:
	tree.clear()
	var root := tree.create_item()
	root.set_text(0, "Project Dependencies")

	var filter_text := search_field.text.to_lower()
	var filter_type := filter_option.get_item_id(filter_option.selected)

	var type_groups := {}
	for file_path in scan_result.files:
		var file_data: Dictionary = scan_result.files[file_path]
		var file_type: String = file_data.type

		if filter_type != 0:
			var type_name := filter_option.get_item_text(filter_option.selected).to_lower()
			if not file_type.contains(type_name.get_slice(" ", 0).to_lower()):
				continue

		if filter_text != "" and not file_path.to_lower().contains(filter_text):
			continue

		if not type_groups.has(file_type):
			type_groups[file_type] = []
		type_groups[file_type].append(file_path)

	var sorted_types := type_groups.keys()
	sorted_types.sort()

	for file_type in sorted_types:
		var type_item := tree.create_item(root)
		type_item.set_text(0, "%s (%d)" % [file_type.capitalize(), type_groups[file_type].size()])

		var files: Array = type_groups[file_type]
		files.sort()

		for file_path in files:
			var file_item := tree.create_item(type_item)
			var short_path: String = file_path.replace("res://", "")
			file_item.set_text(0, short_path)
			file_item.set_metadata(0, file_path)

			var deps: Array = scan_result.files[file_path].deps
			if deps.size() > 0:
				file_item.set_suffix(0, "(%d deps)" % deps.size())

	root.set_expanded(true)


func _populate_broken_refs() -> void:
	broken_refs_list.clear()
	if not scan_result.has("broken_refs"):
		return

	for ref in scan_result.broken_refs:
		var text := "%s -> %s" % [ref.file.replace("res://", ""), ref.missing_ref]
		broken_refs_list.add_item(text)
		broken_refs_list.set_item_metadata(broken_refs_list.item_count - 1, ref)

	if broken_refs_list.item_count == 0:
		broken_refs_list.add_item("No broken references found!")


func _populate_unused() -> void:
	unused_list.clear()
	if not scan_result.has("unused_assets"):
		return

	for file_path in scan_result.unused_assets:
		var short_path: String = file_path.replace("res://", "")
		unused_list.add_item(short_path)
		unused_list.set_item_metadata(unused_list.item_count - 1, file_path)

	if unused_list.item_count == 0:
		unused_list.add_item("No unused assets found!")


func _on_search_changed(_new_text: String) -> void:
	_populate_tree()


func _on_filter_changed(_index: int) -> void:
	_populate_tree()


func _on_tree_item_selected() -> void:
	var item := tree.get_selected()
	if not item:
		return

	var file_path: String = item.get_metadata(0)
	if file_path.is_empty():
		return

	selected_file = file_path
	_show_file_dependencies(file_path)


func _show_file_dependencies(file_path: String) -> void:
	if not scan_result.has("files"):
		return
	if not scan_result.files.has(file_path):
		return

	var file_data: Dictionary = scan_result.files[file_path]
	var deps: Array = file_data.deps

	var reverse_deps: Array = []
	if scan_result.reverse_deps.has(file_path):
		reverse_deps = scan_result.reverse_deps[file_path]

	var text := "[b]File:[/b] %s\n" % file_path
	text += "[b]Type:[/b] %s\n" % file_data.type
	text += "[b]Dependencies:[/b] %d\n" % deps.size()
	text += "[b]Referenced by:[/b] %d files\n" % reverse_deps.size()

	if reverse_deps.size() > 0:
		text += "\n[b]Who uses this:[/b]"
		for rd in reverse_deps:
			var status := "[color=green]OK[/color]"
			if scan_result.files.has(rd) and scan_result.files[rd].type == "broken":
				status = "[color=red]BROKEN[/color]"
			text += "\n  <- %s %s" % [rd.replace("res://", ""), status]

	if deps.size() > 0:
		text += "\n\n[b]Depends on:[/b]"
		for dep in deps:
			var exists: bool = ResourceLoader.exists(dep) or dep.begins_with("uid://")
			var status := "[color=green]OK[/color]" if exists else "[color=red]MISSING[/color]"
			var display_dep: String = dep if not dep.begins_with("uid://") else dep
			text += "\n  -> [%s] %s" % [status, display_dep]

	info_label.text = text


func _on_broken_ref_selected(index: int) -> void:
	if index < 0 or index >= broken_refs_list.item_count:
		return
	var ref: Dictionary = broken_refs_list.get_item_metadata(index)
	if ref.has("file"):
		_select_file_in_tree(ref.file)


func _on_unused_selected(index: int) -> void:
	if index < 0 or index >= unused_list.item_count:
		return
	var file_path: String = unused_list.get_item_metadata(index)
	if not file_path.is_empty():
		_select_file_in_tree(file_path)


func _select_file_in_tree(file_path: String) -> void:
	var root := tree.get_root()
	if not root:
		return
	_select_item_recursive(root, file_path)


func _select_item_recursive(item: TreeItem, file_path: String) -> bool:
	for i in range(item.get_child_count()):
		var child := item.get_child(i)
		var metadata = child.get_metadata(0)
		if metadata == file_path:
			tree.set_selected(child, 0)
			child.select(0)
			var parent := child.get_parent()
			while parent:
				parent.set_expanded(true)
				parent = parent.get_parent()
			return true
		if _select_item_recursive(child, file_path):
			return true
	return false
