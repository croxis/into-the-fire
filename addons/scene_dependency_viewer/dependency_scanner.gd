@tool
class_name DependencyScanner
extends RefCounted

## Emitted when scan progress updates.
signal scan_progress(message: String, current: int, total: int)
## Emitted when scan completes.
signal scan_completed(result: Dictionary)

## The project root path.
var project_root: String = "res://"

## Scan result structure:
## {
##   "files": { "res://path": { "type": "scene"|"resource"|"script"|"texture"|..., "deps": [...], "uid": "..." } },
##   "reverse_deps": { "res://path": ["files that depend on this"] },
##   "broken_refs": [ { "file": "res://...", "missing_ref": "res://...", "line": int } ],
##   "unused_assets": [ "res://..." ]
## }

func scan_project() -> Dictionary:
	var result := {
		"files": {},
		"reverse_deps": {},
		"broken_refs": [],
		"unused_assets": []
	}

	var all_files := _find_all_project_files()
	var total := all_files.size()
	var current := 0

	for file_path in all_files:
		current += 1
		scan_progress.emit("Scanning: %s" % file_path, current, total)

		var deps := _extract_dependencies(file_path)
		var file_type := _get_file_type(file_path)
		var uid := _extract_uid(file_path)

		result.files[file_path] = {
			"type": file_type,
			"deps": deps,
			"uid": uid
		}

		# Build reverse dependency map
		for dep in deps:
			if not result.reverse_deps.has(dep):
				result.reverse_deps[dep] = []
			if file_path not in result.reverse_deps[dep]:
				result.reverse_deps[dep].append(file_path)

		# Check for broken references
		for dep in deps:
			if not ResourceLoader.exists(dep) and not dep.begins_with("uid://"):
				result.broken_refs.append({
					"file": file_path,
					"missing_ref": dep,
					"line": 0
				})

	scan_progress.emit("Finding unused assets...", total, total)

	# Find unused assets: files that are never referenced by anything
	for file_path in all_files:
		var is_used := false
		# Check if any file depends on this one
		if result.reverse_deps.has(file_path):
			is_used = true
		# Check if it's a main scene or autoload
		if file_path == ProjectSettings.get_setting("application/run/main_scene", ""):
			is_used = true
		# Check autoloads
		var autoload_count: int = ProjectSettings.get_setting("autoload/item_count", 0) if ProjectSettings.has_setting("autoload/item_count") else 0
		for i in range(autoload_count):
			var autoload_path: String = ProjectSettings.get_setting("autoload/item_%d/path" % i, "")
			if autoload_path == file_path:
				is_used = true
		# Scripts can be used via class_name - check if any file references this script's class
		if file_path.ends_with(".gd"):
			# Check if this script defines a class_name that others reference
			var script_content := FileAccess.get_file_as_string(file_path)
			if script_content:
				var class_match := RegEx.create_from_string("^class_name\\s+(\\w+)")
				var result_match := class_match.search(script_content)
				if result_match:
					var my_class := "class_name:" + result_match.get_string(1)
					if result.reverse_deps.has(my_class):
						is_used = true

		if not is_used:
			result.unused_assets.append(file_path)

	scan_completed.emit(result)
	return result


func _find_all_project_files() -> Array[String]:
	var files: Array[String] = []
	_scan_directory(project_root, files)
	return files


func _scan_directory(path: String, files: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		var full_path := path.path_join(file_name)

		if dir.current_is_dir():
			# Skip hidden dirs and addon dirs we don't need
			if file_name not in [".godot", ".git", ".import"]:
				_scan_directory(full_path, files)
		else:
			if _is_scannable_file(file_name):
				files.append(full_path)

		file_name = dir.get_next()
	dir.list_dir_end()


func _is_scannable_file(file_name: String) -> bool:
	var extensions := [".tscn", ".tres", ".gd", ".cs", ".cfg", ".import",
		".png", ".jpg", ".jpeg", ".webp", ".svg",
		".wav", ".ogg", ".mp3",
		".glb", ".gltf", ".obj", ".fbx",
		".ttf", ".otf", ".woff"]
	for ext in extensions:
		if file_name.ends_with(ext):
			return true
	return false


func _get_file_type(file_path: String) -> String:
	if file_path.ends_with(".tscn"):
		return "scene"
	elif file_path.ends_with(".tres"):
		return "resource"
	elif file_path.ends_with(".gd"):
		return "script"
	elif file_path.ends_with(".cs"):
		return "script_csharp"
	elif file_path.ends_with(".png") or file_path.ends_with(".jpg") or file_path.ends_with(".jpeg") or file_path.ends_with(".webp") or file_path.ends_with(".svg"):
		return "texture"
	elif file_path.ends_with(".wav") or file_path.ends_with(".ogg") or file_path.ends_with(".mp3"):
		return "audio"
	elif file_path.ends_with(".glb") or file_path.ends_with(".gltf") or file_path.ends_with(".obj") or file_path.ends_with(".fbx"):
		return "model"
	elif file_path.ends_with(".ttf") or file_path.ends_with(".otf") or file_path.ends_with(".woff"):
		return "font"
	elif file_path.ends_with(".import"):
		return "import"
	elif file_path.ends_with(".cfg"):
		return "config"
	return "other"


func _extract_uid(file_path: String) -> String:
	var import_file := file_path + ".import"
	if FileAccess.file_exists(import_file):
		var content := FileAccess.get_file_as_string(import_file)
		var uid_match := RegEx.create_from_string("uid=\"(uid://[^\"]+)\"")
		var result := uid_match.search(content)
		if result:
			return result.get_string(1)
	return ""


func _extract_dependencies(file_path: String) -> Array[String]:
	var deps: Array[String] = []

	match file_path.get_extension():
		"tscn", "tres":
			deps = _parse_godot_text_dependencies(file_path)
		"gd":
			deps = _parse_gdscript_dependencies(file_path)
		"cs":
			deps = _parse_csharp_dependencies(file_path)
		"import":
			deps = _parse_import_dependencies(file_path)
		"cfg":
			deps = _parse_cfg_dependencies(file_path)

	return deps


func _parse_godot_text_dependencies(file_path: String) -> Array[String]:
	var deps: Array[String] = []
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return deps

	var line_number := 0
	while not file.eof_reached():
		var line := file.get_line()
		line_number += 1

		# Match ext_resource and sub_resource references
		# ext_resource type="..." uid="uid://..." path="res://..."
		var ext_match := RegEx.create_from_string("path=\"(res://[^\"]+)\"")
		var result := ext_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# Also match uid:// references
		var uid_match := RegEx.create_from_string("uid=\"(uid://[^\"]+)\"")
		result = uid_match.search(line)
		if result:
			var uid := result.get_string(1)
			if uid not in deps:
				deps.append(uid)

		# Match load() and preload() calls in scripts embedded in scenes
		var load_match := RegEx.create_from_string("(?:load|preload)\\s*\\(\\s*\"(res://[^\"]+)\"\\s*\\)")
		result = load_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

	file.close()
	return deps


func _parse_gdscript_dependencies(file_path: String) -> Array[String]:
	var deps: Array[String] = []
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return deps

	while not file.eof_reached():
		var line := file.get_line()

		# Skip comments
		if line.strip_edges().begins_with("#") or line.strip_edges().begins_with("##"):
			continue

		# Match preload("res://...") and load("res://...")
		var load_match := RegEx.create_from_string("(?:load|preload)\\s*\\(\\s*\"(res://[^\"]+)\"\\s*\\)")
		var result := load_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# Match class_name declarations (not references in comments)
		var class_match := RegEx.create_from_string("^class_name\\s+(\\w+)")
		result = class_match.search(line)
		if result:
			var class_name_str := result.get_string(1)
			if class_name_str not in deps:
				deps.append("class_name:" + class_name_str)

		# Match const SOME preload
		var const_match := RegEx.create_from_string("const\\s+\\w+\\s*=\\s*(?:load|preload)\\s*\\(\\s*\"(res://[^\"]+)\"\\s*\\)")
		result = const_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

	file.close()
	return deps


func _parse_csharp_dependencies(file_path: String) -> Array[String]:
	var deps: Array[String] = []
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return deps

	while not file.eof_reached():
		var line := file.get_line()

		# Match ResourceLoader.Load("res://...")
		var load_match := RegEx.create_from_string("ResourceLoader\\.Load\\s*\\(\\s*\"(res://[^\"]+)\"\\s*\\)")
		var result := load_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# Match [Export] with Resource types
		var export_match := RegEx.create_from_string("\\[Export\\].*\"(res://[^\"]+)\"")
		result = export_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

	file.close()
	return deps


func _parse_import_dependencies(file_path: String) -> Array[String]:
	var deps: Array[String] = []
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return deps

	while not file.eof_reached():
		var line := file.get_line()
		# The import file points to the source file
		if line.begins_with("[remap]"):
			continue
		var dest_match := RegEx.create_from_string("dest_files=\\[\"([^\"]+)\"\\]")
		var result := dest_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

	file.close()
	return deps


func _parse_cfg_dependencies(file_path: String) -> Array[String]:
	var deps: Array[String] = []
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return deps

	while not file.eof_reached():
		var line := file.get_line()
		# Match res:// references in config
		var res_match := RegEx.create_from_string("\"(res://[^\"]+)\"")
		var result := res_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

	file.close()
	return deps
