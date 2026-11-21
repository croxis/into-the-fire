@tool
extends RefCounted

# ---- inspect -------------------------------------------------------------
func inspect_tree(params: Dictionary, ctx: McpCallContext) -> Dictionary:
	var tree := _load_tree(params)
	if tree == null:
		return _err("RESOURCE_NOT_FOUND", "No BehaviorTree at %s" % params.get("path", ""))
	var root := tree.get_root_task()
	return _ok({
		"path": params["path"],
		"blackboard_plan": _dump_plan(tree.get_blackboard_plan()),
		"root": _dump_task(root, ""),
	})

func _dump_task(task: BTTask, path: String) -> Dictionary:
	if task == null:
		return {}
	var script := task.get_script()
	var out := {
		"path": path,
		"class": task.get_class(),
		"script": script.resource_path if script else "",
		"name": task.get_task_name(),
		"custom_name": task.custom_name,
		"props": _dump_props(task),
		"children": [],
	}
	for i in task.get_child_count():
		out.children.append(_dump_task(task.get_child(i), ("%s/%d" % [path, i]).trim_prefix("/")))
	return out

func _dump_props(task: Object) -> Dictionary:
	# Script-declared exported vars only; BBParam values unwrapped to plain Variants
	var out := {}
	for p in task.get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var v: Variant = task.get(p.name)
		out[p.name] = _unwrap(v)
	return out

func _unwrap(v: Variant) -> Variant:
	if v is BBParam:
		var p := v as BBParam
		if p.value_source == BBParam.BLACKBOARD_VAR:
			return {"_bbparam": "variable", "variable": String(p.variable)}
		return {"_bbparam": "value", "value": _jsonable(p.saved_value)}
	return _jsonable(v)

# ---- edit ---------------------------------------------------------------
func edit_tree(params: Dictionary, ctx: McpCallContext) -> Dictionary:
	var tree := _load_tree(params)
	if tree == null:
		return _err("RESOURCE_NOT_FOUND", "No BehaviorTree at %s" % params.get("path", ""))
	match String(params.get("op", "")):
		"add_task":
			var parent_path := String(params.get("parent_path", ""))
			var parent := tree.get_root_task() if parent_path.is_empty() else _resolve(tree, parent_path)
			if parent == null:
				return _err("TASK_NOT_FOUND", "No task at branch '%s'" % parent_path)
			var made := _make_task(params)
			if made == null:
				return _err("BAD_TASK", "Could not instantiate task_script '%s'" % params.get("task_script", ""))
			if params.has("index"):
				parent.add_child_at_index(made, int(params["index"]))
			else:
				parent.add_child(made)
		"remove_task":
			var target := _resolve(tree, String(params.get("parent_path", "")))
			if target == null:
				return _err("TASK_NOT_FOUND", "No task at that branch")
			var p := target.get_parent()
			if p == null:
				tree.set_root_task(null)
			else:
				p.remove_child(target)
		"set_root":
			var root := _make_task(params)
			if root == null:
				return _err("BAD_TASK", "Could not instantiate task_script")
			tree.set_root_task(root)
		_:
			return _err("BAD_OP", "op must be add_task, remove_task, or set_root")
	var save_err := ResourceSaver.save(tree, String(params["path"]))
	if save_err != OK:
		return _err("SAVE_FAILED", "ResourceSaver error %d" % save_err)
	return _ok({"saved": params["path"], "root": _dump_task(tree.get_root_task(), "")})

func _make_task(params: Dictionary) -> BTTask:
	var sp := String(params.get("task_script", ""))
	if sp.is_empty() or not ResourceLoader.exists(sp):
		return null
	var scr := load(sp)
	if scr == null:
		return null
	var task := scr.new() as BTTask
	if task == null:
		return null
	task.custom_name = String(params.get("name", ""))
	var props: Dictionary = params.get("props", {})
	for k in props:
		task.set(k, _coerce(task.get(k), props[k]))
	return task

# BBParam exports (BBVariant, BBFloat, BBNode, BBString...) won't take a raw
# JSON float/dict through set() — wrap it. This is the fiddliest part of the bridge.
func _coerce(current: Variant, incoming: Variant) -> Variant:
	if not (current is BBParam):
		return incoming
	var dup := (current as BBParam).duplicate() as BBParam
	if typeof(incoming) == TYPE_DICTIONARY and incoming.has("_bbparam"):
		if String(incoming["_bbparam"]) == "variable":
			dup.value_source = BBParam.BLACKBOARD_VAR
			dup.variable = StringName(incoming.get("variable", ""))
			return dup
		incoming = incoming.get("value")
	return _write_saved(dup, incoming)

func _write_saved(p: BBParam, v: Variant) -> BBParam:
	p.value_source = BBParam.SAVED_VALUE
	match p.get_type():
		TYPE_INT:         p.saved_value = int(v)
		TYPE_FLOAT:       p.saved_value = float(v)
		TYPE_BOOL:        p.saved_value = bool(v)
		TYPE_STRING:      p.saved_value = String(v)
		TYPE_STRING_NAME: p.saved_value = StringName(v)
		_:                p.saved_value = v
	return p


func _resolve(tree: BehaviorTree, branch: String) -> BTTask:
	var task := tree.get_root_task()
	if branch.is_empty():
		return task
	for seg in branch.split("/", false):
		if task == null:
			return null
		var idx := int(seg)
		if idx < 0 or idx >= task.get_child_count():
			return null
		task = task.get_child(idx)
	return task

# ---- helpers -------------------------------------------------------------
func _load_tree(params: Dictionary) -> BehaviorTree:
	var p := String(params.get("path", ""))
	if p.is_empty() or not ResourceLoader.exists(p):
		return null
	return load(p) as BehaviorTree

func _ok(data: Dictionary) -> Dictionary:
	return {"data": data}

func _err(code: String, msg: String) -> Dictionary:
	return {"error": {"code": code, "message": msg}}

func _json_safe(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			var f := float(v)
			return not (is_nan(f) or is_inf(f))   # JSON has no NaN/Inf
		TYPE_ARRAY:
			for e in v:
				if not _json_safe(e):
					return false
			return true
		TYPE_DICTIONARY:
			for k in v:
				if typeof(k) != TYPE_STRING and typeof(k) != TYPE_STRING_NAME:
					return false
				if not _json_safe(v[k]):
					return false
			return true
		_:
			return false   # Vector3, Color, NodePath, Object refs, packed arrays…

func _jsonable(v: Variant) -> Variant:
	match typeof(v):
		TYPE_ARRAY:
			var a: Array = []
			for e in v:
				a.append(_jsonable(e))
			return a
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = _jsonable(v[k])
			return d
		TYPE_FLOAT:
			var f := float(v)
			return f if not (is_nan(f) or is_inf(f)) else str(f)
		_:
			return v if _json_safe(v) else var_to_str(v)

func _dump_plan(plan: BlackboardPlan) -> Array:
	var out: Array = []
	if plan == null:
		return out
	# Walk the base-plan chain first; derived plans only store *modified* vars,
	# so the base holds everything else.
	var chain: Array = []
	var p: BlackboardPlan = plan
	while p != null:
		chain.push_front(p)
		p = p.get_base_plan()
	var by_name := {}
	for pl: BlackboardPlan in chain:
		for entry in _plan_entries(pl):
			by_name[entry.name] = entry
	var names := by_name.keys()
	names.sort()
	for n in names:
		out.append(by_name[n])
	return out

func _plan_entries(plan: BlackboardPlan) -> Array:
	var out: Array = []
	for prop in plan.get_property_list():
		var pname := String(prop.name)
		if not pname.begins_with("var/") or not pname.ends_with("/name"):
			continue
		var stem := pname.trim_suffix("/name")        # "var/<var_name>"
		out.append({
			"name": stem.trim_prefix("var/"),
			"type": type_string(int(plan.get(stem + "/type"))),
			"value": _jsonable(plan.get(stem + "/value")),
			"hint": int(plan.get(stem + "/hint")),
			"hint_string": String(plan.get(stem + "/hint_string")),
		})
	return out
