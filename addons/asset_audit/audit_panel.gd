@tool
extends VBoxContainer

var scanner
var license_detector
var scan_result: Dictionary = {}
var license_data: Dictionary = {}

# UI references
var scan_button: Button
var refresh_button: Button
var search_field: LineEdit
var sort_option: OptionButton
var category_option: OptionButton
var used_tree: Tree
var orphaned_tree: Tree
var tab_container: TabContainer
var status_label: Label
var progress_label: Label
var used_count_label: Label
var orphaned_count_label: Label
var delete_button: Button
var export_button: Button
var select_safe_button: Button
var select_all_button: Button
var info_panel: RichTextLabel

# State
var show_used_tab := true

func _ready() -> void:
	_build_ui()

	scanner = UsageScanner.new()
	license_detector = LicenseDetector.new()

	scan_button.pressed.connect(_on_scan_pressed)
	refresh_button.pressed.connect(_on_scan_pressed)
	search_field.text_changed.connect(_on_search_changed)
	sort_option.item_selected.connect(_on_sort_changed)
	category_option.item_selected.connect(_on_category_changed)
	used_tree.item_selected.connect(_on_used_tree_item_selected)
	orphaned_tree.item_selected.connect(_on_orphaned_tree_item_selected)
	delete_button.pressed.connect(_on_delete_pressed)
	export_button.pressed.connect(_on_export_pressed)
	select_safe_button.pressed.connect(_on_select_safe)
	select_all_button.pressed.connect(_on_select_all_with_warning)

	progress_label.text = "Ready. Click Scan to audit project assets."


func _build_ui() -> void:
	# Toolbar row 1: scan controls
	var toolbar := HBoxContainer.new()
	toolbar.custom_minimum_size.y = 32
	add_child(toolbar)

	scan_button = Button.new()
	scan_button.text = "Scan Project"
	scan_button.custom_minimum_size.x = 110
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
	search_field.placeholder_text = "Search assets..."
	search_field.custom_minimum_size.x = 200
	toolbar.add_child(search_field)

	category_option = OptionButton.new()
	category_option.custom_minimum_size.x = 130
	toolbar.add_child(category_option)

	sort_option = OptionButton.new()
	sort_option.custom_minimum_size.x = 120
	toolbar.add_child(sort_option)

	# Toolbar row 2: actions
	var toolbar2 := HBoxContainer.new()
	toolbar2.custom_minimum_size.y = 28
	add_child(toolbar2)

	select_safe_button = Button.new()
	select_safe_button.text = "Select Safe to Delete"
	select_safe_button.custom_minimum_size.x = 160
	select_safe_button.tooltip_text = "Select only assets marked SAFE (no references, no risk)"
	toolbar2.add_child(select_safe_button)

	select_all_button = Button.new()
	select_all_button.text = "Select ALL Orphaned"
	select_all_button.custom_minimum_size.x = 160
	select_all_button.tooltip_text = "Select ALL orphaned assets including CHECK items (risky)"
	toolbar2.add_child(select_all_button)

	delete_button = Button.new()
	delete_button.text = "Delete Selected"
	delete_button.custom_minimum_size.x = 120
	toolbar2.add_child(delete_button)

	export_button = Button.new()
	export_button.text = "Export Report"
	export_button.custom_minimum_size.x = 110
	toolbar2.add_child(export_button)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar2.add_child(spacer2)

	used_count_label = Label.new()
	used_count_label.text = "Used: 0"
	toolbar2.add_child(used_count_label)

	orphaned_count_label = Label.new()
	orphaned_count_label.text = "Orphaned: 0"
	toolbar2.add_child(orphaned_count_label)

	# Hint label
	var hint_label := Label.new()
	hint_label.text = "Shift+click = range | Ctrl+click = toggle"
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	toolbar2.add_child(hint_label)

	# Main split
	var hsplit := HSplitContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.split_offset = 500
	add_child(hsplit)

	# Left panel - trees
	var left_panel := VBoxContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.65
	hsplit.add_child(left_panel)

	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(tab_container)
	tab_container.tab_changed.connect(_on_tab_changed)

	# Tab: Used Assets
	var used_tab := VBoxContainer.new()
	used_tab.name = "Used Assets"
	tab_container.add_child(used_tab)

	var used_scroll := ScrollContainer.new()
	used_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	used_tab.add_child(used_scroll)

	used_tree = Tree.new()
	used_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	used_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	used_tree.hide_root = false
	used_tree.allow_reselect = true
	used_tree.select_mode = Tree.SELECT_MULTI
	used_scroll.add_child(used_tree)

	# Tab: Orphaned Assets
	var orphaned_tab := VBoxContainer.new()
	orphaned_tab.name = "Orphaned Assets"
	tab_container.add_child(orphaned_tab)

	var orphaned_scroll := ScrollContainer.new()
	orphaned_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	orphaned_tab.add_child(orphaned_scroll)

	orphaned_tree = Tree.new()
	orphaned_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orphaned_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	orphaned_tree.hide_root = false
	orphaned_tree.allow_reselect = true
	orphaned_tree.select_mode = Tree.SELECT_MULTI
	orphaned_scroll.add_child(orphaned_tree)

	# Right panel - info
	var right_panel := VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.35
	hsplit.add_child(right_panel)

	info_panel = RichTextLabel.new()
	info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_panel.bbcode_enabled = true
	info_panel.text = "Select an asset to view details."
	right_panel.add_child(info_panel)

	# Status bar
	var status_bar := HBoxContainer.new()
	status_bar.custom_minimum_size.y = 24
	add_child(status_bar)

	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text = "Ready."
	status_bar.add_child(status_label)

	progress_label = Label.new()
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_label.text = ""
	status_bar.add_child(progress_label)

	_setup_sort_options()
	_setup_category_options()


func _setup_sort_options() -> void:
	sort_option.clear()
	sort_option.add_item("Sort by Type", 0)
	sort_option.add_item("Sort by Path", 1)
	sort_option.add_item("Sort by License", 2)


func _setup_category_options() -> void:
	category_option.clear()
	category_option.add_item("All Types", 0)
	category_option.add_item("Scene", 1)
	category_option.add_item("Script", 2)
	category_option.add_item("Resource", 3)
	category_option.add_item("Texture", 4)
	category_option.add_item("Audio", 5)
	category_option.add_item("Model", 6)
	category_option.add_item("Shader", 7)
	category_option.add_item("Font", 8)
	category_option.add_item("Other", 9)


func _on_tab_changed(_tab: int) -> void:
	show_used_tab = (tab_container.current_tab == 0)

	_populate_active_tree()


func _get_category_filter() -> String:
	if category_option.selected <= 0:
		return ""
	return category_option.get_item_text(category_option.selected).to_lower()


func _file_matches_category(file_path: String, category: String) -> bool:
	if category == "":
		return true
	if not scan_result.all_files.has(file_path):
		return false
	var ftype: String = scan_result.all_files[file_path].type
	match category:
		"scene":
			return ftype == "tscn" or ftype == "tres"
		"script":
			return ftype == "gd"
		"resource":
			return ftype == "tres" or ftype == "res"
		"texture":
			return ftype in ["png", "jpg", "jpeg", "webp", "svg", "bmp", "dds", "exr", "hdr"]
		"audio":
			return ftype in ["ogg", "wav", "mp3", "opus"]
		"model":
			return ftype in ["glb", "gltf", "obj", "fbx", "blend", "obj"]
		"shader":
			return ftype == "gdshader" or ftype == "shader"
		"font":
			return ftype in ["ttf", "otf", "woff", "woff2"]
		"other":
			return ftype not in ["tscn", "tres", "res", "gd", "png", "jpg", "jpeg", "webp", "svg", "bmp", "dds", "exr", "hdr", "ogg", "wav", "mp3", "opus", "glb", "gltf", "obj", "fbx", "blend", "gdshader", "shader", "ttf", "otf", "woff", "woff2"]
	return true


## --- Scan ---


func _on_scan_pressed() -> void:
	scan_button.disabled = true
	refresh_button.disabled = true
	progress_label.text = "Scanning..."
	if used_tree:
		used_tree.clear()
	if orphaned_tree:
		orphaned_tree.clear()

	scan_result = {}
	license_data = {}

	call_deferred("_run_scan")


func _run_scan() -> void:
	scan_result = await scanner.scan_project()

	progress_label.text = "Detecting licenses..."
	license_data = license_detector.scan_all_licenses()

	_populate_ui()
	scan_button.disabled = false
	refresh_button.disabled = false


## --- UI Population ---


func _populate_ui() -> void:
	used_count_label.text = "Used: %d" % scan_result.used_count
	orphaned_count_label.text = "Orphaned: %d" % scan_result.orphaned_count
	status_label.text = "Scan complete. %d total assets, %d used, %d orphaned." % [
		scan_result.total_count,
		scan_result.used_count,
		scan_result.orphaned_count
	]
	_populate_active_tree()
	_info_welcome()


func _populate_active_tree() -> void:
	if not used_tree or not orphaned_tree:
		return
	if show_used_tab:
		_populate_used_tree()
	else:
		_populate_orphaned_tree()


func _populate_used_tree() -> void:
	used_tree.clear()
	if scan_result.is_empty():
		return

	var root := used_tree.create_item()
	root.set_text(0, "Asset Audit")

	var filter_text := search_field.text.to_lower()
	var sort_mode: int = sort_option.get_item_id(sort_option.selected)
	var category := _get_category_filter()

	var type_groups := {}
	for file_path in scan_result.used_assets:
		if filter_text != "" and not file_path.to_lower().contains(filter_text):
			continue
		if not _file_matches_category(file_path, category):
			continue
		var file_type: String = scan_result.all_files[file_path].type
		if not type_groups.has(file_type):
			type_groups[file_type] = []
		type_groups[file_type].append(file_path)

	var sorted_types := type_groups.keys()
	sorted_types.sort()

	for file_type in sorted_types:
		var type_item := used_tree.create_item(root)
		type_item.set_text(0, "%s (%d)" % [file_type.capitalize(), type_groups[file_type].size()])

		var files: Array = type_groups[file_type]
		_sort_files(files, sort_mode)

		for file_path in files:
			var file_item := used_tree.create_item(type_item)
			var short_path: String = file_path.replace("res://", "")
			var license_info := _get_license_info(file_path)
			var license_text := ""
			if license_info.license != "Unknown" and license_info.license != "":
				license_text = " [%s]" % license_info.license
			file_item.set_text(0, "%s%s" % [short_path, license_text])
			file_item.set_metadata(0, file_path)
			file_item.set_tooltip_text(0, file_path)

	root.collapsed = false


func _populate_orphaned_tree() -> void:
	orphaned_tree.clear()
	if scan_result.is_empty():
		return

	var root := orphaned_tree.create_item()
	root.set_text(0, "Asset Audit")

	var filter_text := search_field.text.to_lower()
	var sort_mode: int = sort_option.get_item_id(sort_option.selected)
	var category := _get_category_filter()

	var safe_group := {}
	var manual_group := {}

	for orphan in scan_result.orphaned_assets:
		var o_path: String = orphan.path
		if filter_text != "" and not o_path.to_lower().contains(filter_text):
			continue
		if not _file_matches_category(o_path, category):
			continue
		if orphan.safe_to_delete:
			if not safe_group.has(orphan.type):
				safe_group[orphan.type] = []
			safe_group[orphan.type].append(orphan)
		else:
			if not manual_group.has(orphan.type):
				manual_group[orphan.type] = []
			manual_group[orphan.type].append(orphan)

	if safe_group.size() > 0:
		var safe_header := orphaned_tree.create_item(root)
		safe_header.set_text(0, "Safe to Delete (%d)" % _count_group(safe_group))
		safe_header.set_custom_color(0, Color(0.3, 0.8, 0.3))
		var sorted_types := safe_group.keys()
		sorted_types.sort()
		for o_type in sorted_types:
			var type_item := orphaned_tree.create_item(safe_header)
			type_item.set_text(0, "%s (%d)" % [o_type.capitalize(), safe_group[o_type].size()])
			var orphans: Array = safe_group[o_type]
			_sort_orphans(orphans, sort_mode)
			for orphan in orphans:
				_add_orphan_item(type_item, orphan)
		safe_header.collapsed = false

	if manual_group.size() > 0:
		var manual_header := orphaned_tree.create_item(root)
		manual_header.set_text(0, "Check Manually (%d)" % _count_group(manual_group))
		manual_header.set_custom_color(0, Color(0.8, 0.6, 0.2))
		var sorted_types := manual_group.keys()
		sorted_types.sort()
		for o_type in sorted_types:
			var type_item := orphaned_tree.create_item(manual_header)
			type_item.set_text(0, "%s (%d)" % [o_type.capitalize(), manual_group[o_type].size()])
			var orphans: Array = manual_group[o_type]
			_sort_orphans(orphans, sort_mode)
			for orphan in orphans:
				_add_orphan_item(type_item, orphan)
		manual_header.collapsed = false

	if scan_result.dead_folders.size() > 0:
		var dead_header := orphaned_tree.create_item(root)
		dead_header.set_text(0, "Dead Folders (%d)" % scan_result.dead_folders.size())
		dead_header.set_custom_color(0, Color(0.8, 0.3, 0.3))
		for folder in scan_result.dead_folders:
			var folder_item := orphaned_tree.create_item(dead_header)
			folder_item.set_text(0, folder.replace("res://", "") + "/")
			folder_item.set_metadata(0, folder)
		dead_header.collapsed = false

	root.collapsed = false


func _add_orphan_item(parent: TreeItem, orphan: Dictionary) -> void:
	var o_path: String = orphan.path
	var short_path: String = o_path.replace("res://", "")
	var license_info := _get_license_info(o_path)
	var license_text := ""
	if license_info.license != "Unknown" and license_info.license != "":
		license_text = " [%s]" % license_info.license

	var tree_item := orphaned_tree.create_item(parent)
	tree_item.set_text(0, "%s%s" % [short_path, license_text])
	tree_item.set_metadata(0, o_path)
	tree_item.set_tooltip_text(0, orphan.reason)


func _count_group(group: Dictionary) -> int:
	var total := 0
	for key in group:
		total += group[key].size()
	return total


func _sort_files(files: Array, sort_mode: int) -> void:
	match sort_mode:
		0:
			files.sort()
		1:
			files.sort()
		2:
			files.sort_custom(func(a, b):
				var la: String = _get_license_info(a).license
				var lb: String = _get_license_info(b).license
				if la == lb:
					return a < b
				return la < lb
			)


func _sort_orphans(orphans: Array, sort_mode: int) -> void:
	match sort_mode:
		0, 1:
			orphans.sort_custom(func(a, b): return a.path < b.path)
		2:
			orphans.sort_custom(func(a, b):
				var la: String = _get_license_info(a.path).license
				var lb: String = _get_license_info(b.path).license
				if la == lb:
					return a.path < b.path
				return la < lb
			)


func _get_license_info(file_path: String) -> Dictionary:
	if license_data.has(file_path):
		return license_data[file_path]
	return {"license": "Unknown", "source_file": ""}


## --- Search / Filter ---


func _on_search_changed(_new_text: String) -> void:
	_populate_active_tree()


func _on_sort_changed(_index: int) -> void:
	_populate_active_tree()


func _on_category_changed(_index: int) -> void:
	_populate_active_tree()


## --- Multi-select logic ---


func _on_used_tree_item_selected() -> void:
	_show_info_for_current_tree()


func _on_orphaned_tree_item_selected() -> void:
	_show_info_for_current_tree()


func _show_info_for_current_tree() -> void:
	var current_tree := used_tree if show_used_tab else orphaned_tree
	var item := current_tree.get_selected()
	if not item:
		return
	var file_path: String = item.get_metadata(0)
	if not file_path.is_empty():
		_show_asset_info(file_path)


## --- Tree selection ---


func _show_asset_info(file_path: String) -> void:
	var text := "[b]Asset:[/b] %s\n" % file_path

	var file_type := "unknown"
	if scan_result.all_files.has(file_path):
		file_type = scan_result.all_files[file_path].type
	text += "[b]Type:[/b] %s\n" % file_type.capitalize()

	var license_info := _get_license_info(file_path)
	text += "[b]License:[/b] %s\n" % license_info.license
	if license_info.source_file != "":
		text += "[b]License source:[/b] %s\n" % license_info.source_file

	var ref_count := 0
	if scan_result.reverse_deps.has(file_path):
		ref_count = scan_result.reverse_deps[file_path].size()
	text += "[b]Referenced by:[/b] %d files\n" % ref_count

	var dep_count := 0
	if scan_result.all_files.has(file_path):
		dep_count = scan_result.all_files[file_path].deps.size()
	text += "[b]Depends on:[/b] %d files\n" % dep_count

	if scan_result.reverse_deps.has(file_path):
		var refs: Array = scan_result.reverse_deps[file_path]
		if refs.size() > 0:
			text += "\n[b]Referenced by:[/b]"
			for ref in refs:
				text += "\n  <- %s" % ref.replace("res://", "")

	if scan_result.all_files.has(file_path):
		var deps: Array = scan_result.all_files[file_path].deps
		if deps.size() > 0:
			text += "\n\n[b]Depends on:[/b]"
			for dep in deps:
				text += "\n  -> %s" % dep

	for orphan in scan_result.orphaned_assets:
		if orphan.path == file_path:
			text += "\n\n[b]Status:[/b] [color=red]ORPHANED[/color]"
			text += "\n[b]Reason:[/b] %s" % orphan.reason
			if orphan.safe_to_delete:
				text += "\n[color=green]Safe to delete[/color]"
			else:
				text += "\n[color=yellow]Review before deleting[/color]"
			break

	var sel_count := _count_selected(orphaned_tree)
	if sel_count > 1:
		text += "\n\n[b]Selected:[/b] %d items" % sel_count

	info_panel.text = text


func _info_welcome() -> void:
	info_panel.text = "[b]Asset Audit[/b]\n\nSelect an asset to view details.\n\n[color=gray]Tip: Use the Orphaned Assets tab to find dead weight.\nShift+click = range select\nCtrl+click = toggle individual items[/color]"


## --- Delete selected ---


func _on_delete_pressed() -> void:
	var paths := _get_selected_orphaned_paths()
	if paths.is_empty():
		return

	var safe_count := 0
	var check_count := 0
	for path in paths:
		for orphan in scan_result.orphaned_assets:
			if orphan.path == path:
				if orphan.safe_to_delete:
					safe_count += 1
				else:
					check_count += 1
				break

	var dialog := ConfirmationDialog.new()
	dialog.title = "Confirm Delete"

	if check_count > 0:
		dialog.dialog_text = "DELETE %d ASSET(S)?\n\n" % paths.size()
		dialog.dialog_text += "SAFE to delete: %d (green - no references)\n" % safe_count
		dialog.dialog_text += "CHECK first:    %d (red - MAY be in use)\n\n" % check_count
		dialog.dialog_text += "WARNING: CHECK items could break your project\n"
		dialog.dialog_text += "if they are loaded dynamically or used by class_name.\n\n"
		dialog.dialog_text += "This action CANNOT be undone."
		dialog.get_ok_button().text = "Delete All %d" % paths.size()
		dialog.get_ok_button().add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		dialog.dialog_text = "Delete %d safe-to-delete asset(s)?\n\n" % safe_count
		dialog.dialog_text += "These have no references and are safe to remove.\n\n"
		dialog.dialog_text += "This action CANNOT be undone."

	dialog.confirmed.connect(func():
		_delete_paths(paths)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(500, 280))


func _delete_paths(paths: Array) -> void:
	for path in paths:
		if path.ends_with("/"):
			_delete_directory_recursive(path)
		else:
			DirAccess.remove_absolute(path)
			var import_file: String = path + ".import"
			if FileAccess.file_exists(import_file):
				DirAccess.remove_absolute(import_file)
			var uid_file: String = path + ".uid"
			if FileAccess.file_exists(uid_file):
				DirAccess.remove_absolute(uid_file)
	_on_scan_pressed()


func _delete_directory_recursive(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			_delete_directory_recursive(full_path)
		else:
			DirAccess.remove_absolute(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)


func _get_selected_orphaned_paths() -> Array:
	var paths: Array = []
	# Collect from orphaned tree directly
	_collect_selected_paths(orphaned_tree.get_root(), paths)
	return paths


func _collect_selected_paths(item: TreeItem, out: Array) -> void:
	if not item:
		return
	if item.is_selected(0):
		var fp: String = item.get_metadata(0)
		if not fp.is_empty():
			for orphan in scan_result.orphaned_assets:
				if orphan.path == fp:
					out.append(fp)
					break
	for i in range(item.get_child_count()):
		_collect_selected_paths(item.get_child(i), out)


func _count_selected(tree_ref: Tree) -> int:
	var items: Array[TreeItem] = []
	var sel := tree_ref.get_next_selected(null)
	while sel:
		items.append(sel)
		sel = tree_ref.get_next_selected(sel)
	return items.size()


## --- Select orphaned ---


func _on_select_safe() -> void:
	tab_container.current_tab = 1
	show_used_tab = false
	_populate_active_tree()

	var root := orphaned_tree.get_root()
	if root:
		_select_only_safe_items(root)


func _select_only_safe_items(item: TreeItem) -> void:
	if not item:
		return
	for i in range(item.get_child_count()):
		var child := item.get_child(i)
		var fp: String = child.get_metadata(0)
		if not fp.is_empty():
			for orphan in scan_result.orphaned_assets:
				if orphan.path == fp and orphan.safe_to_delete:
					child.select(0)
					break
		_select_only_safe_items(child)


func _on_select_all_with_warning() -> void:
	var check_count := 0
	var safe_count := 0
	for orphan in scan_result.orphaned_assets:
		if orphan.safe_to_delete:
			safe_count += 1
		else:
			check_count += 1

	if check_count > 0:
		var dialog := AcceptDialog.new()
		dialog.title = "Warning: CHECK Items Selected"
		dialog.dialog_text = "You are about to select ALL orphaned assets,\nincluding %d items marked CHECK (red).\n\n" % check_count
		dialog.dialog_text += "CHECK items MAY be in use via:\n"
		dialog.dialog_text += "  - Dynamic load() in scripts\n"
		dialog.dialog_text += "  - class_name references\n"
		dialog.dialog_text += "  - Editor-only entry points\n\n"
		dialog.dialog_text += "Deleting CHECK items can break your project.\n"
		dialog.dialog_text += "Only delete them if you are CERTAIN they are unused."
		add_child(dialog)
		dialog.confirmed.connect(func():
			dialog.queue_free()
			_do_select_all()
		)
		dialog.canceled.connect(func():
			dialog.queue_free()
		)
		dialog.popup_centered(Vector2i(480, 320))
	else:
		_do_select_all()


func _do_select_all() -> void:
	tab_container.current_tab = 1
	show_used_tab = false
	_populate_active_tree()

	var root := orphaned_tree.get_root()
	if root:
		_select_all_tree_items(root)


func _select_all_tree_items(item: TreeItem) -> void:
	if not item:
		return
	for i in range(item.get_child_count()):
		var child := item.get_child(i)
		var fp: String = child.get_metadata(0)
		if not fp.is_empty():
			child.select(0)
		_select_all_tree_items(child)


## --- Export report ---


func _on_export_pressed() -> void:
	if scan_result.is_empty():
		return

	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["csv (*.csv)", "txt (*.txt)"])
	dialog.title = "Export Audit Report"
	dialog.file_selected.connect(_do_export)
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


func _do_export(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		status_label.text = "Failed to write to: %s" % path
		return

	if path.ends_with(".csv"):
		_export_csv(f)
	else:
		_export_txt(f)

	f.close()
	status_label.text = "Report exported to: %s" % path


func _export_csv(f: FileAccess) -> void:
	f.store_line("Status,Type,Path,License,Reason")
	for file_path in scan_result.used_assets:
		var ft: String = scan_result.all_files[file_path].type
		var li := _get_license_info(file_path)
		f.store_line("used,%s,%s,%s," % [ft, file_path, li.license])
	for orphan in scan_result.orphaned_assets:
		var li := _get_license_info(orphan.path)
		f.store_line("orphaned,%s,%s,%s,%s" % [orphan.type, orphan.path, li.license, orphan.reason])


func _export_txt(f: FileAccess) -> void:
	f.store_line("Asset Audit Report")
	f.store_line("=" .repeat(60))
	f.store_line("Total: %d  |  Used: %d  |  Orphaned: %d" % [
		scan_result.total_count, scan_result.used_count, scan_result.orphaned_count
	])
	f.store_line("")

	f.store_line("--- Used Assets ---")
	for file_path in scan_result.used_assets:
		var ft: String = scan_result.all_files[file_path].type
		var li := _get_license_info(file_path)
		f.store_line("  [%s] %s  (%s)" % [ft, file_path, li.license])

	f.store_line("")
	f.store_line("--- Orphaned Assets ---")
	for orphan in scan_result.orphaned_assets:
		var li := _get_license_info(orphan.path)
		var safe_str := "SAFE" if orphan.safe_to_delete else "CHECK"
		f.store_line("  [%s] %s  (%s) -- %s [%s]" % [orphan.type, orphan.path, li.license, orphan.reason, safe_str])

	if scan_result.dead_folders.size() > 0:
		f.store_line("")
		f.store_line("--- Dead Folders ---")
		for folder in scan_result.dead_folders:
			f.store_line("  %s/" % folder)
