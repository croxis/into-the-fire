extends SceneTree
## Writes simplified copies of a scene's collision meshes, each the coarsest
## version within an error budget in metres (CollisionSimplifier).
##
##   godot --headless --path . -s tools/simplify_collision.gd -- \
##       <scene> <budget in m> <source .shape> <node path> [<source .shape> <node path> ...]
##
## Each source is the full-detail shape; the node path is the CollisionShape3D
## in <scene> it belongs to, which gives its scale in the game world. The
## result goes to collision/<same file name> beside the source, keeping that
## file's uid when it already exists. Point the CollisionShape3D at it in the
## editor. Sources are never changed, so running again starts from full detail.
##
## Babylon 5 (reactor and main cylinder):
##   godot --headless --path . -s tools/simplify_collision.gd -- \
##       "res://ships/earth alliance/babylon 5/babylon_5.tscn" 10 \
##       "res://ships/earth alliance/babylon 5/babylon_5_scale_reactor.shape" \
##       Reactor_Section/StaticBody3D/CollisionShape3D \
##       "res://ships/earth alliance/babylon 5/babylon_5_scale_main_cylinder.shape" \
##       rotation/Main_Cylinder/StaticBody3D/__272572


func _init() -> void:
	# Ship scripts use autoloads, which exist only once the main loop runs.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4 or args.size() % 2 != 0:
		push_error("usage: <scene> <budget m> <source .shape> <node path> ...")
		quit(1)
		return
	var scene: Node3D = load(args[0]).instantiate()
	root.add_child(scene)  # For global (world) scale.
	var budget := args[1].to_float()
	var failed := false
	for i in range(2, args.size(), 2):
		failed = not _simplify(scene, args[i], args[i + 1], budget) or failed
	scene.free()
	quit(1 if failed else 0)


func _simplify(scene: Node3D, source_path: String, node_path: String, budget: float) -> bool:
	var source := load(source_path) as ConcavePolygonShape3D
	var node := scene.get_node_or_null(node_path) as Node3D
	if source == null or node == null:
		push_error("%s or %s not found" % [source_path, node_path])
		return false
	var s := node.global_transform.basis.get_scale()
	var scale := maxf(s.x, maxf(s.y, s.z))  # Errors in the most stretched direction.
	var start := Time.get_ticks_msec()
	var picked := CollisionSimplifier.pick(source.get_faces(), scale, budget)
	var out_path := source_path.get_base_dir().path_join("collision").path_join(source_path.get_file())
	var shape := source.duplicate() as ConcavePolygonShape3D  # Keeps backface_collision etc.
	shape.set_faces(picked.faces)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	# Headless saves get no uid from the editor: keep the file's, or make one.
	var uid := ResourceLoader.get_resource_uid(out_path) if FileAccess.file_exists(out_path) else ResourceUID.INVALID_ID
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	# Compressed: a double-precision build stores vertices as 64-bit floats.
	var err := ResourceSaver.save(shape, out_path, ResourceSaver.FLAG_COMPRESS)
	if err == OK:
		err = ResourceSaver.set_uid(out_path, uid)
	if err != OK:
		push_error("%s: save failed (%s)" % [out_path, error_string(err)])
		return false
	var before := source.get_faces().size() / 3
	var after: int = picked.faces.size() / 3
	print("%s: %d -> %d triangles (%.0f%%, level %d), largest measured gap %.2f m of %.0f m allowed, %d ms -> %s (%s)" % [
			source_path.get_file(), before, after, 100.0 * after / before, picked.level,
			picked.error, budget, Time.get_ticks_msec() - start, out_path, ResourceUID.id_to_text(uid)])
	return true
