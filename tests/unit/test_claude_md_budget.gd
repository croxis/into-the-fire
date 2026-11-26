extends GutTest
## Keeps the CLAUDE.md files small. The top-level one loads into every Claude
## session and a folder's loads whenever Claude works there, so each byte is
## paid for again in every session. When one grows past its budget, move
## feature detail into the CLAUDE.md of the folder its code lives in (or trim)
## rather than raising the budget.

const TOP_LEVEL_BUDGET := 10 * 1024
const FOLDER_BUDGET := 8 * 1024
## Not ours, or not code we work in.
const SKIPPED_FOLDERS := [".godot", ".git", "addons", "demo"]


func test_top_level_claude_md_is_within_budget() -> void:
	var size := _size("res://CLAUDE.md")
	assert_gt(size, 0, "res://CLAUDE.md should exist")
	assert_lte(size, TOP_LEVEL_BUDGET,
		"CLAUDE.md is %d bytes, over its %d byte budget" % [size, TOP_LEVEL_BUDGET])


func test_folder_claude_md_files_are_within_budget() -> void:
	for folder in DirAccess.get_directories_at("res://"):
		if folder in SKIPPED_FOLDERS:
			continue
		var path := "res://%s/CLAUDE.md" % folder
		if not FileAccess.file_exists(path):
			continue
		var size := _size(path)
		assert_lte(size, FOLDER_BUDGET,
			"%s is %d bytes, over its %d byte budget" % [path, size, FOLDER_BUDGET])


func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	return file.get_length()
