@tool
class_name LicenseDetector
extends RefCounted

## Scans asset directories for LICENSE/CREDITS files and detects known license patterns.
## Returns a dictionary mapping asset paths to their detected license info.

var project_root: String = "res://"

## License file names to search for (checked top-down in each directory).
const LICENSE_FILE_NAMES: Array[String] = [
	"LICENSE.txt",
	"LICENSE.md",
	"LICENSE",
	"LICENSE-MIT",
	"LICENSE-MIT.txt",
	"license.txt",
	"license",
	"kenney_license.txt",
	"CREDITS.txt",
	"CREDITS.md",
	"CREDITS",
	"LICENCE.txt",
	"LICENCE.md",
	"LICENCE",
]

## Patterns to match in license file content. Keys are display names, values are
## regex patterns matched case-insensitively against the first 2000 chars of the file.
const LICENSE_PATTERNS: Dictionary = {
	"CC0": "(?i)creative\\s+common[s]?\\s+zero|CC0\\s+1\\.0",
	"CC-BY": "(?i)creative\\s+common[s]?\\s+attribution[^-]|CC[-\\s]?BY\\s+4\\.0",
	"CC-BY-SA": "(?i)creative\\s+common[s]?\\s+attribution[-\\s]?sharealike|CC[-\\s]?BY[-\\s]?SA",
	"CC-BY-NC": "(?i)creative\\s+common[s]?\\s+attribution[-\\s]?noncommercial|CC[-\\s]?BY[-\\s]?NC",
	"MIT": "(?i)\\bMIT\\b\\s+license|permission\\s+is\\s+hereby\\s+granted.*?\\bMIT\\b",
	"GPL-3": "(?i)GNU\\s+general\\s+public\\s+license.*?version\\s+3|GPL[-\\s]?3",
	"GPL-2": "(?i)GNU\\s+general\\s+public\\s+license.*?version\\s+2|GPL[-\\s]?2",
	"LGPL": "(?i)GNU\\s+lesser\\s+general\\s+public\\s+license|LGPL",
	"Apache-2": "(?i)apache\\s+license.*?version\\s+2\\.0|Apache[-\\s]?2\\.0",
	"BSD-3": "(?i)BSD[-\\s]?3[-\\s]?clause",
	"BSD-2": "(?i)BSD[-\\s]?2[-\\s]?clause",
	"Unlicense": "(?i)\\bunlicense|public\\s+domain\\s+dedication",
}


func scan_all_licenses() -> Dictionary:
	## Returns { "res://path/to/asset.png": { "license": "MIT", "source_file": "res://LICENSE" }, ... }
	var result := {}
	var license_cache := {}  # directory path -> license info

	_scan_directory(project_root, result, license_cache)
	return result


func _scan_directory(path: String, result: Dictionary, cache: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return

	# Check for license files in this directory
	var license_info := _detect_license_in_dir(path)
	if license_info.license != "Unknown":
		cache[path] = license_info

	# Walk files and assign the closest license
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		var full_path := path.path_join(file_name)

		if dir.current_is_dir():
			if file_name not in [".godot", ".git", ".import", "addons"]:
				_scan_directory(full_path, result, cache)
		else:
			# Only assign licenses to actual asset files (not license files themselves)
			if not _is_license_file(file_name):
				var license := _find_closest_license(full_path, cache)
				result[full_path] = license

		file_name = dir.get_next()
	dir.list_dir_end()


func _detect_license_in_dir(dir_path: String) -> Dictionary:
	var info := {"license": "Unknown", "source_file": ""}

	for license_name in LICENSE_FILE_NAMES:
		var license_path := dir_path.path_join(license_name)
		if FileAccess.file_exists(license_path):
			var content := FileAccess.get_file_as_string(license_path)
			if content.is_empty():
				continue
			# Only check first 2000 chars for performance
			if content.length() > 2000:
				content = content.substr(0, 2000)
			var detected := _match_license_pattern(content)
			if detected != "Unknown":
				info.license = detected
				info.source_file = license_path
				return info
			else:
				# License file exists but pattern not recognized
				info.license = "Unknown (check manually)"
				info.source_file = license_path
				return info

	return info


func _match_license_pattern(content: String) -> String:
	for license_name in LICENSE_PATTERNS:
		var pattern: String = LICENSE_PATTERNS[license_name]
		var regex := RegEx.create_from_string(pattern)
		if regex.search(content):
			return license_name
	return "Unknown"


func _find_closest_license(asset_path: String, cache: Dictionary) -> Dictionary:
	## Walk up directories from the asset to find the nearest cached license.
	var dir := asset_path.get_base_dir()

	while dir != "" and dir != "res://" and dir != "res:":
		if cache.has(dir):
			return cache[dir]
		# Also check the root
		var parent := dir.get_base_dir()
		if parent == dir:
			break
		dir = parent

	# Check project root
	if cache.has(project_root):
		return cache[project_root]

	return {"license": "Unknown", "source_file": ""}


func _is_license_file(file_name: String) -> bool:
	var lower := file_name.to_lower()
	for ln in LICENSE_FILE_NAMES:
		if lower == ln.to_lower():
			return true
	return false
