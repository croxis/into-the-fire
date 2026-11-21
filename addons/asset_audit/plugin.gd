@tool
extends EditorPlugin

var dock: Control

func _enter_tree() -> void:
	dock = preload("res://addons/asset_audit/audit_panel.tscn").instantiate()
	add_control_to_bottom_panel(dock, "Asset Audit")

func _exit_tree() -> void:
	if dock:
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
		dock = null
