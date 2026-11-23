@tool
extends EditorExportPlugin
## Adds the pre-built catalogues (*.stars) to every export, servers included:
## Godot does not export files it does not import, and projects using the
## addon should not have to add them to their include filters themselves.
## The CSVs are exported as they are by their import setting ("Keep File").

const DATABASES := "res://addons/star_field/databases/"


func _get_name() -> String:
	return "StarField"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	for file in DirAccess.get_files_at(DATABASES):
		if file.ends_with(StarCatalogCache.EXTENSION):
			add_file(DATABASES + file, FileAccess.get_file_as_bytes(DATABASES + file), false)
