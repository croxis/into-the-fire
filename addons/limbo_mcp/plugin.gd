@tool
extends EditorPlugin

const SOURCE := "res://addons/limbo_mcp/plugin.cfg"
const HANDLER := "res://addons/limbo_mcp/bt_handler.gd"

func _enter_tree() -> void:
	var specs: Array = []
	specs.append(_spec("limbo_bt_inspect",
		"Read a LimboAI behavior tree (.tres): returns the task hierarchy with each task's script, name, and exported values, plus the blackboard plan variables.",
		{"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]},
		&"inspect_tree", false, false))
	specs.append(_spec("limbo_bt_edit",
		"Create or modify a LimboAI behavior tree: add a task (BTSequence, BTSelector, BTCheckVar, BTWait, a custom BTAction...) under a branch, remove a task, or replace the root. Writes and saves the .tres.",
		{"type": "object", "properties": {
			"path": {"type": "string"},
			"op": {"type": "string", "enum": ["add_task", "remove_task", "set_root"]},
			"parent_path": {"type": "string", "description": "slash path of child indices, '' = root"},
			"task_script": {"type": "string", "description": "res:// path of a BTTask script"},
			"index": {"type": "integer"},
			"name": {"type": "string", "description": "custom_name shown in the BT editor"},
			"props": {"type": "object"}},
		 "required": ["path", "op"]},
		&"edit_tree", false, true))  # requires_writable = true
	specs.append(_spec("limbo_bt_lint",
		"Validate a LimboAI behavior tree: unresolved BTSubtree paths, BBNode paths that don't resolve in the scene, tasks missing required parameters, blackboard vars referenced but never declared.",
		{"type": "object", "properties": {"path": {"type": "string"}}},
		&"lint_tree", false, false))
	McpToolRegistry.get_instance().batch_register(specs)   # atomic

func _exit_tree() -> void:
	# Removal API lives in custom_tools/ in your installed copy
	# (unregister / unregister_source). If unsure, skip it and rely on the dock toggle.
	McpToolRegistry.get_instance().unregister_source(SOURCE)

func _spec(n: String, d: String, schema: Dictionary, m: StringName,
		promoted: bool, writable: bool) -> McpCustomToolSpec:
	var s := McpCustomToolSpec.new()
	s.name = n
	s.description = d                      # ≤600 chars, agent-facing
	s.params_schema = schema               # ≤8 KB UTF-8
	s.script_path = HANDLER
	s.method = m
	s.source_path = SOURCE
	s.promoted = promoted
	s.requires_writable = writable
	return s
