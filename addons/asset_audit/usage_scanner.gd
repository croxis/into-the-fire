@tool
class_name UsageScanner
extends RefCounted

## Core scanning engine for Asset Audit. Walks the project, builds a dependency map,
## and identifies orphaned assets. Works headless (no UI dependencies).
##
## SAFETY PHILOSOPHY:
## Only mark an asset "safe to delete" when we are CERTAIN it is unused.
## When in doubt, mark "check manually". A false positive (deleting a used asset)
## is far worse than a false negative (keeping an unused asset).

## Emitted when scan progress updates.
signal scan_progress(message: String, current: int, total: int)
## Emitted when scan completes.
signal scan_completed(result: Dictionary)

var project_root: String = "res://"

## Scan result structure:
## {
##   "all_files": { "res://path": { "type": "scene"|"resource"|"script"|..., "deps": [...] } },
##   "reverse_deps": { "res://path": ["files that depend on this"] },
##   "used_assets": [ "res://..." ],
##   "orphaned_assets": [ { "path": "res://...", "type": "...", "safe_to_delete": bool, "reason": "..." } ],
##   "dead_folders": [ "res://path/" ],
##   "total_count": int,
##   "used_count": int,
##   "orphaned_count": int,
## }

func scan_project() -> Dictionary:
	var result := {
		"all_files": {},
		"reverse_deps": {},
		"used_assets": [],
		"orphaned_assets": [],
		"dead_folders": [],
		"total_count": 0,
		"used_count": 0,
		"orphaned_count": 0,
	}

	var all_files := _find_all_project_files()
	var total := all_files.size()
	result.total_count = total

	# Phase 1: Parse all files and extract dependencies
	var current := 0
	for file_path in all_files:
		current += 1
		scan_progress.emit("Parsing: %s" % file_path, current, total)

		var deps := _extract_dependencies(file_path)
		var file_type := _get_file_type(file_path)

		result.all_files[file_path] = {
			"type": file_type,
			"deps": deps,
		}

		# Build reverse dependency map
		for dep in deps:
			if not result.reverse_deps.has(dep):
				result.reverse_deps[dep] = []
			if file_path not in result.reverse_deps[dep]:
				result.reverse_deps[dep].append(file_path)

	# Phase 2: Scan project.godot for resource references
	scan_progress.emit("Scanning project settings...", total, total)
	var project_deps := _scan_project_godot()
	for ref in project_deps:
		if not result.reverse_deps.has(ref):
			result.reverse_deps[ref] = []
		if "res://project.godot" not in result.reverse_deps[ref]:
			result.reverse_deps[ref].append("res://project.godot")

	# Phase 3: Build UID-to-file mapping and resolve UID references
	var uid_map := _build_uid_map(all_files)
	_resolve_uid_references(result, uid_map)

	# Phase 4: Resolve .import files - link imported assets to their source .import file
	_scan_import_files(result)

	# Phase 4.5: Resolve class_name references. GDScript files reference each other
	# by global class name far more often than by path, so without this a code-heavy
	# project reports most of its scripts as "orphaned".
	_resolve_class_name_references(all_files, result)

	# Phase 5: Determine used vs orphaned
	scan_progress.emit("Classifying assets...", total, total)

	# Collect special paths that are always "used"
	var always_used := _get_always_used_paths()

	for file_path in all_files:
		# Engine-generated companion metadata (.import/.uid) are not standalone
		# assets - they belong to their source file, Godot regenerates them, and
		# deleting a live script's .uid churns its UID (breaking uid:// refs).
		# They are still parsed above for dependency resolution, but never counted
		# as used/orphaned assets in the report.
		if file_path.ends_with(".import") or file_path.ends_with(".uid"):
			continue

		var is_used := false

		# Check if referenced by any other file (direct dependency)
		# BUT exclude references from its own .import or .uid file
		if result.reverse_deps.has(file_path):
			var referrers: Array = result.reverse_deps[file_path]
			var has_real_ref := false
			for referrer in referrers:
				if referrer != file_path + ".import" and referrer != file_path + ".uid":
					has_real_ref = true
					break
			if has_real_ref:
				is_used = true

		# Check if this is a special path (main scene, autoload, etc.)
		if file_path in always_used:
			is_used = true

		# Check if this asset's path is referenced anywhere (incl. via its .import file)
		if not is_used:
			if _is_asset_referenced_by_path(file_path, result):
				is_used = true

		# Also check if the .import file exists and is referenced
		if not is_used:
			var import_file := file_path + ".import"
			if FileAccess.file_exists(import_file) and result.reverse_deps.has(import_file):
				is_used = true

		# Check if any script contains a string reference to this path
		# (catches dynamic loads, variable assignments, concatenation)
		# NOTE: This is handled per-file in _parse_gdscript_dependencies
		# which catches load(), preload(), variable assignments, ResourceLoader, etc.

		if is_used:
			result.used_assets.append(file_path)
		else:
			var safe_info := _check_safety(file_path, result)
			result.orphaned_assets.append({
				"path": file_path,
				"type": _get_file_type(file_path),
				"safe_to_delete": safe_info.safe,
				"reason": safe_info.reason,
			})

	# Phase 6: Detect dead folders (folders containing only orphaned assets)
	scan_progress.emit("Detecting dead folders...", total, total)
	result.dead_folders = _detect_dead_folders(result)

	result.used_count = result.used_assets.size()
	result.orphaned_count = result.orphaned_assets.size()
	# Report the count of real assets, excluding the .import/.uid companion
	# metadata that was skipped during classification.
	result.total_count = result.used_count + result.orphaned_count

	scan_completed.emit(result)
	return result


## --- File discovery ---

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
			if file_name not in [".godot", ".git", "__pycache__", ".import"]:
				_scan_directory(full_path, files)
		else:
			if _is_scannable_file(file_name):
				files.append(full_path)

		file_name = dir.get_next()
	dir.list_dir_end()


func _is_scannable_file(file_name: String) -> bool:
	var extensions := [
		".tscn", ".tres", ".gd", ".cs",
		".png", ".jpg", ".jpeg", ".webp", ".svg",
		".wav", ".ogg", ".mp3",
		".glb", ".gltf", ".obj", ".fbx",
		".ttf", ".otf", ".woff",
		".import", ".cfg", ".uid",
	]
	for ext in extensions:
		if file_name.ends_with(ext):
			return true
	return false


## --- File type classification ---

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
	elif file_path.ends_with(".uid"):
		return "uid"
	return "other"


## --- Dependency extraction ---

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
		"uid":
			deps = _parse_uid_dependencies(file_path)

	return deps


func _parse_godot_text_dependencies(file_path: String) -> Array[String]:
	var deps: Array[String] = []
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return deps

	while not file.eof_reached():
		var line := file.get_line()

		# Match res:// paths in ext_resource and sub_resource
		var ext_match := RegEx.create_from_string("path=\"(res://[^\"]+)\"")
		var result := ext_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# Match uid:// references
		var uid_match := RegEx.create_from_string("uid=\"(uid://[^\"]+)\"")
		result = uid_match.search(line)
		if result:
			var uid := result.get_string(1)
			if uid not in deps:
				deps.append(uid)

		# Match load() and preload() calls in scene scripts
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

	var full_content := file.get_as_text()
	file.close()

	var lines := full_content.split("\n")

	# Track string variable assignments for dynamic path detection
	var string_vars: Dictionary = {}  # var_name -> "res://..." value

	for line in lines:
		var stripped := line.strip_edges()

		# Skip comments
		if stripped.begins_with("#"):
			continue

		# --- Direct load/preload ---
		var load_match := RegEx.create_from_string("(?:load|preload)\\s*\\(\\s*\"(res://[^\"]+)\"\\s*\\)")
		var result := load_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# --- @export and @onready with type hints ---
		# @export var texture: Texture2D = preload("res://...")
		# @onready var sprite = $Sprite2D
		var export_match := RegEx.create_from_string("^@export\\s+var\\s+(\\w+)")
		result = export_match.search(stripped)
		if result:
			# @export vars can be set in the editor inspector to any resource
			# We cannot know which resource, so we must be conservative
			# and NOT mark assets as orphaned if they could be set via export
			pass

		# --- Variable assignment with string literal ---
		# var path = "res://some/asset.png"
		var var_assign := RegEx.create_from_string("^var\\s+(\\w+)\\s*=\\s*\"(res://[^\"]+)\"")
		result = var_assign.search(stripped)
		if result:
			var var_name := result.get_string(1)
			var res_path := result.get_string(2)
			string_vars[var_name] = res_path
			if res_path not in deps:
				deps.append(res_path)

		# --- String concatenation ---
		# var path = "res://" + "some/asset.png"
		# var path = "res://some/" + "asset.png"
		var concat_match := RegEx.create_from_string("\"(res://[^\"]*)\"\\s*\\+\\s*\"([^\"]+)\"")
		result = concat_match.search(stripped)
		if result:
			var full_path := result.get_string(1) + result.get_string(2)
			if full_path not in deps:
				deps.append(full_path)

		# --- Variable used in load() ---
		# load(some_var) where some_var = "res://..."
		var load_var_match := RegEx.create_from_string("(?:load|preload)\\s*\\(\\s*(\\w+)\\s*\\)")
		result = load_var_match.search(stripped)
		if result:
			var var_name := result.get_string(1)
			if string_vars.has(var_name):
				var ref: String = string_vars[var_name]
				if ref not in deps:
					deps.append(ref)

		# --- ResourceLoader.load() ---
		var rl_match := RegEx.create_from_string("ResourceLoader\\.load\\s*\\(\\s*\"(res://[^\"]+)\"")
		result = rl_match.search(stripped)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# --- ResourceLoader.exists() ---
		var rle_match := RegEx.create_from_string("ResourceLoader\\.exists\\s*\\(\\s*\"(res://[^\"]+)\"")
		result = rle_match.search(stripped)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# --- get_node / $ path references ---
		var getnode_match := RegEx.create_from_string("get_node\\s*\\(\\s*\"(res://[^\"]+)\"")
		result = getnode_match.search(stripped)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# --- $ shorthand node path ---
		var dollar_match := RegEx.create_from_string("\\$\\s*\"(res://[^\"]+)\"")
		result = dollar_match.search(stripped)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# --- has_node / find_node / get_node_or_null ---
		var hasnode_match := RegEx.create_from_string("(?:has_node|find_node|get_node_or_null)\\s*\\(\\s*\"(res://[^\"]+)\"")
		result = hasnode_match.search(stripped)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# --- load_threaded_request ---
		var threaded_match := RegEx.create_from_string("load_threaded_request\\s*\\(\\s*\"(res://[^\"]+)\"")
		result = threaded_match.search(stripped)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

	return deps


func _parse_csharp_dependencies(file_path: String) -> Array[String]:
	var deps: Array[String] = []
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return deps

	while not file.eof_reached():
		var line := file.get_line()

		# ResourceLoader.Load("res://...")
		var rl_match := RegEx.create_from_string("ResourceLoader\\.Load\\s*\\(\\s*\"(res://[^\"]+)\"")
		var result := rl_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# GD.Load("res://...")
		var gd_match := RegEx.create_from_string("GD\\.Load\\s*[<(]\\s*\"(res://[^\"]+)\"")
		result = gd_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# Load<T>("res://...")
		var generic_match := RegEx.create_from_string("Load\\s*<[^>]+>\\s*\\(\\s*\"(res://[^\"]+)\"")
		result = generic_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# ResourceLoader.LoadThreadedRequest("res://...")
		var threaded_match := RegEx.create_from_string("ResourceLoader\\.LoadThreadedRequest\\s*\\(\\s*\"(res://[^\"]+)\"")
		result = threaded_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

		# General res:// string
		var general_res := RegEx.create_from_string("\"(res://[^\"]+)\"")
		result = general_res.search(line)
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
		# The import file links the source to the imported destination
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
		var res_match := RegEx.create_from_string("\"(res://[^\"]+)\"")
		var result := res_match.search(line)
		if result:
			var ref := result.get_string(1)
			if ref not in deps:
				deps.append(ref)

	file.close()
	return deps


func _parse_uid_dependencies(file_path: String) -> Array[String]:
	var deps: Array[String] = []
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return deps

	while not file.eof_reached():
		var line := file.get_line()
		var uid_match := RegEx.create_from_string("uid=\"?(uid://[^\"]+)\"?")
		var result := uid_match.search(line)
		if result:
			var uid := result.get_string(1)
			if uid not in deps:
				deps.append(uid)
		else:
			var plain_uid := RegEx.create_from_string("^(uid://\\S+)$")
			result = plain_uid.search(line.strip_edges())
			if result:
				var uid := result.get_string(1)
				if uid not in deps:
					deps.append(uid)

	file.close()
	return deps


## --- Project.godot scanning ---

func _scan_project_godot() -> Array[String]:
	## Scan project.godot for resource references (themes, shaders, input maps, etc.)
	var refs: Array[String] = []
	var file := FileAccess.open("res://project.godot", FileAccess.READ)
	if not file:
		return refs

	var content := file.get_as_text()
	file.close()

	# Match all res:// paths
	var res_match := RegEx.create_from_string("\"(res://[^\"]+)\"")
	var result := res_match.search(content)
	while result:
		var ref := result.get_string(1)
		if ref not in refs:
			refs.append(ref)
		result = res_match.search(content, result.get_end())

	return refs


## --- Import file resolution ---

func _scan_import_files(result: Dictionary) -> void:
	for file_path in result.all_files:
		if not file_path.ends_with(".import"):
			continue

		var file_data: Dictionary = result.all_files[file_path]
		for dep in file_data.deps:
			if not result.reverse_deps.has(dep):
				result.reverse_deps[dep] = []
			if file_path not in result.reverse_deps[dep]:
				result.reverse_deps[dep].append(file_path)


## --- UID mapping ---

func _build_uid_map(all_files: Array[String]) -> Dictionary:
	var uid_map := {}

	for file_path in all_files:
		if file_path.ends_with(".import"):
			var file := FileAccess.open(file_path, FileAccess.READ)
			if not file:
				continue

			var uid := ""
			var dest_path := ""

			while not file.eof_reached():
				var line := file.get_line()

				if uid == "":
					var uid_match := RegEx.create_from_string("uid=\"(uid://[^\"]+)\"")
					var uid_result := uid_match.search(line)
					if uid_result:
						uid = uid_result.get_string(1)

				if dest_path == "":
					var dest_match := RegEx.create_from_string("dest_files=\\[\"([^\"]+)\"\\]")
					var dest_result := dest_match.search(line)
					if dest_result:
						dest_path = dest_result.get_string(1)

			file.close()

			if uid != "" and dest_path != "":
				uid_map[uid] = dest_path

		elif file_path.ends_with(".uid"):
			var file := FileAccess.open(file_path, FileAccess.READ)
			if not file:
				continue

			var uid := ""
			while not file.eof_reached():
				var line := file.get_line().strip_edges()
				if uid == "":
					var uid_match := RegEx.create_from_string("^(uid://\\S+)$")
					var uid_result := uid_match.search(line)
					if uid_result:
						uid = uid_result.get_string(1)
				elif line.begins_with("path="):
					var path_match := RegEx.create_from_string("path=\"(res://[^\"]+)\"")
					var path_result := path_match.search(line)
					if path_result:
						var mapped_path := path_result.get_string(1)
						if uid != "" and mapped_path != "":
							uid_map[uid] = mapped_path

			file.close()

			if uid != "":
				var mapped_path := file_path.trim_suffix(".uid")
				if not uid_map.has(uid):
					uid_map[uid] = mapped_path

	return uid_map


func _resolve_uid_references(result: Dictionary, uid_map: Dictionary) -> void:
	for uid in uid_map:
		var file_path: String = uid_map[uid]
		if result.reverse_deps.has(uid):
			if not result.reverse_deps.has(file_path):
				result.reverse_deps[file_path] = []
			for referrer in result.reverse_deps[uid]:
				if referrer not in result.reverse_deps[file_path]:
					result.reverse_deps[file_path].append(referrer)


## --- Always-used paths ---

func _get_always_used_paths() -> Array[String]:
	var paths: Array[String] = []

	# Main scene
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_scene != "":
		paths.append(main_scene)

	# Autoloads
	var autoload_count: int = ProjectSettings.get_setting("autoload/item_count", 0) if ProjectSettings.has_setting("autoload/item_count") else 0
	for i in range(autoload_count):
		var autoload_path: String = ProjectSettings.get_setting("autoload/item_%d/path" % i, "")
		if autoload_path != "":
			paths.append(autoload_path)

	# All enabled addon plugin files (scanner discovers all addons)
	var addon_dir := DirAccess.open("res://addons")
	if addon_dir:
		addon_dir.list_dir_begin()
		var addon_name := addon_dir.get_next()
		while addon_name != "":
			if addon_name == "." or addon_name == "..":
				addon_name = addon_dir.get_next()
				continue
			if addon_dir.current_is_dir():
				# Check if this addon has a plugin.cfg (is a real plugin)
				var plugin_cfg := "res://addons/%s/plugin.cfg" % addon_name
				if FileAccess.file_exists(plugin_cfg):
					# Mark all files in this addon as always-used
					_scan_addon_directory("res://addons/%s" % addon_name, paths)
			addon_name = addon_dir.get_next()
		addon_dir.list_dir_end()

	return paths


func _scan_addon_directory(path: String, paths: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var full_path := path.path_join(file_name)
		if dir.current_is_dir():
			_scan_addon_directory(full_path, paths)
		else:
			paths.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


## --- Class name reference resolution ---

func _resolve_class_name_references(all_files: Array[String], result: Dictionary) -> void:
	## GDScript files reference each other primarily by their global class_name
	## (e.g. "Breeder.new()", "var g: Genome", "extends SpeciesDef"), not by path.
	## Build a class_name -> defining-file map, then add a real dependency edge from
	## every script that mentions a known class name to the file that defines it.
	## We err toward marking a script USED (a loose word match): a false "used" only
	## keeps a file, while a false "orphaned" risks deleting live code.
	var class_defs := {}          # "ClassName" -> "res://path.gd"
	var script_contents := {}     # "res://path.gd" -> source text (read once)

	for file_path in all_files:
		if not file_path.ends_with(".gd"):
			continue
		var file := FileAccess.open(file_path, FileAccess.READ)
		if not file:
			continue
		var content := file.get_as_text()
		file.close()
		script_contents[file_path] = content
		var cn_match := RegEx.create_from_string("(?m)^\\s*class_name\\s+(\\w+)")
		var m := cn_match.search(content)
		if m:
			class_defs[m.get_string(1)] = file_path

	if class_defs.is_empty():
		return

	# Pre-compile a word-boundary matcher per class name (class names are \w+,
	# so no regex escaping is needed).
	var matchers := {}
	for cn in class_defs:
		matchers[cn] = RegEx.create_from_string("\\b" + cn + "\\b")

	for file_path in script_contents:
		var content: String = script_contents[file_path]
		for cn in class_defs:
			var def_path: String = class_defs[cn]
			if def_path == file_path:
				continue  # a class declaring itself is not "using" itself
			var re: RegEx = matchers[cn]
			if re.search(content):
				if not result.reverse_deps.has(def_path):
					result.reverse_deps[def_path] = []
				if file_path not in result.reverse_deps[def_path]:
					result.reverse_deps[def_path].append(file_path)


## --- Path-based reference check ---

func _is_asset_referenced_by_path(file_path: String, result: Dictionary) -> bool:
	## Check if any file in the project references this asset by its res:// path.
	## Exclude references from its own .import or .uid file.
	if result.reverse_deps.has(file_path):
		var referrers: Array = result.reverse_deps[file_path]
		for referrer in referrers:
			if referrer != file_path + ".import" and referrer != file_path + ".uid":
				return true

	# Also check with .import suffix (imported assets are referenced via their .import file)
	var import_file := file_path + ".import"
	if result.reverse_deps.has(import_file):
		return true

	return false


## --- Safety check for orphaned assets ---

func _check_safety(file_path: String, result: Dictionary) -> Dictionary:
	## STRICT RULES: Only mark safe when CERTAIN.
	## When in doubt, mark "check manually".
	var file_type := _get_file_type(file_path)

	# .import files: safe if the imported asset is unused
	if file_type == "import":
		return {"safe": true, "reason": "Import file not referenced; imported asset is unused"}

	# .uid files: safe to delete (auto-generated metadata)
	if file_type == "uid":
		return {"safe": true, "reason": "Auto-generated UID metadata file"}

	# Check if the only referrer is its own .import or .uid file (import-only asset)
	var has_real_ref := false
	if result.reverse_deps.has(file_path):
		var referrers: Array = result.reverse_deps[file_path]
		for referrer in referrers:
			if referrer != file_path + ".import" and referrer != file_path + ".uid":
				has_real_ref = true
				break

	# Scripts with class_name are NEVER safe (used by name anywhere)
	if file_type == "script" or file_type == "script_csharp":
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file:
			var content := file.get_as_text()
			file.close()
			if content.find("class_name") >= 0:
				return {"safe": false, "reason": "Defines class_name; may be used by name"}
		if has_real_ref:
			return {"safe": false, "reason": "Script may be loaded dynamically"}
		# Script with no real referrers - likely safe but verify
		return {"safe": false, "reason": "Script has no references; likely unused but verify before deleting"}

	# Config files are NEVER safe
	if file_type == "config":
		return {"safe": false, "reason": "Config file; may be needed by engine"}

	# Scenes: safe if no real referrers (standalone entry points are a known pattern)
	if file_type == "scene":
		if has_real_ref:
			return {"safe": false, "reason": "Scene may be loaded dynamically at runtime"}
		return {"safe": false, "reason": "Scene has no references; may be an editor entry point"}

	# Resources (.tres): safe if no real referrers
	if file_type == "resource":
		if has_real_ref:
			return {"safe": false, "reason": "Resource may be loaded dynamically at runtime"}
		return {"safe": true, "reason": "Resource has no references; likely unused"}

	# Fonts: safe if no real referrers
	if file_type == "font":
		if has_real_ref:
			return {"safe": false, "reason": "Font may be used by UI themes or code"}
		return {"safe": true, "reason": "Font has no references; likely unused"}

	# 3D models: safe if no real referrers
	if file_type == "model":
		if has_real_ref:
			return {"safe": false, "reason": "Model may be loaded dynamically at runtime"}
		return {"safe": true, "reason": "Model has no references; likely unused"}

	# Textures: safe if no real referrers and not in addons/
	if file_type == "texture":
		if file_path.begins_with("res://addons/"):
			return {"safe": false, "reason": "Addon asset; part of a plugin"}
		if has_real_ref:
			return {"safe": false, "reason": "Texture may be used by sprites, materials, or UI"}
		return {"safe": true, "reason": "Texture has no references; likely unused"}

	# Audio: safe if no real referrers and not in addons/
	if file_type == "audio":
		if file_path.begins_with("res://addons/"):
			return {"safe": false, "reason": "Addon asset; part of a plugin"}
		if has_real_ref:
			return {"safe": false, "reason": "Audio may be loaded dynamically or used by AudioStreamPlayer"}
		return {"safe": true, "reason": "Audio has no references; likely unused"}

	# Everything else: NOT safe (too risky)
	return {"safe": false, "reason": "Cannot determine safety; review manually"}


## --- Dead folder detection ---

func _detect_dead_folders(result: Dictionary) -> Array[String]:
	var dead: Array[String] = []
	var folder_children := {}

	for orphan in result.orphaned_assets:
		var path: String = orphan.path
		var dir := path.get_base_dir()
		while dir != "" and dir != "res://" and dir != "res:":
			if not folder_children.has(dir):
				folder_children[dir] = []
			if path not in folder_children[dir]:
				folder_children[dir].append(path)
			var parent := dir.get_base_dir()
			if parent == dir:
				break
			dir = parent

	for folder in folder_children:
		var children: Array = folder_children[folder]
		if children.size() < 2:
			continue
		var all_orphaned := true
		for used_path in result.used_assets:
			if used_path.begins_with(folder + "/") or used_path == folder:
				all_orphaned = false
				break
		if all_orphaned and folder not in dead:
			dead.append(folder)

	return dead
