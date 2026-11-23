extends GutTest
## CollisionSimplifier (tools/): collision meshes simplified with Godot's mesh
## simplifier, keeping the coarsest version within an error budget in metres.

## Fewer sample points than the tool uses (3000): enough for these simple
## shapes, and the measuring runs in GDScript.
const SAMPLES := 300


## Triangle soup of a sphere (the faces a ConcavePolygonShape3D holds).
func _sphere(radius := 10.0) -> PackedVector3Array:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 32
	mesh.rings = 16
	var arrays := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var soup := PackedVector3Array()
	for i: int in arrays[Mesh.ARRAY_INDEX]:
		soup.append(verts[i])
	return soup


## Flat square, [param n] by [param n] cells of two triangles.
func _plane(n := 40, size := 10.0) -> PackedVector3Array:
	var soup := PackedVector3Array()
	var step := size / n
	for x in n:
		for z in n:
			var a := Vector3(x * step, 0, z * step)
			var b := a + Vector3(step, 0, 0)
			var c := a + Vector3(0, 0, step)
			var d := a + Vector3(step, 0, step)
			soup.append_array([a, b, c, b, d, c])
	return soup


func test_weld_joins_shared_corners() -> void:
	var a := Vector3(0, 0, 0)
	var b := Vector3(1, 0, 0)
	var c := Vector3(0, 0, 1)
	var d := Vector3(1, 0, 1)
	var welded := CollisionSimplifier.weld(PackedVector3Array([a, b, c, b, d, c]))
	assert_eq(welded[0], PackedVector3Array([a, b, c, d]))
	assert_eq(welded[1], PackedInt32Array([0, 1, 2, 1, 3, 2]))


func test_levels_get_coarser() -> void:
	var levels := CollisionSimplifier.levels(_sphere())
	assert_gt(levels.size(), 1)
	var last := _sphere().size()
	for faces in levels:
		assert_lt(faces.size(), last, "each level has fewer triangles")
		assert_eq(faces.size() % 3, 0)
		last = faces.size()


func test_flat_surface_simplifies_without_error() -> void:
	var plane := _plane()
	var coarsest: PackedVector3Array = CollisionSimplifier.levels(plane)[-1]
	assert_lt(coarsest.size(), plane.size() / 4)
	assert_almost_eq(CollisionSimplifier.measured_error(plane, coarsest, SAMPLES), 0.0, 1e-4)


func test_measured_error_finds_the_gap_between_surfaces() -> void:
	var plane := _plane(10)
	assert_almost_eq(CollisionSimplifier.measured_error(plane, plane, SAMPLES), 0.0, 1e-6)
	var lifted := PackedVector3Array()
	for v in plane:
		lifted.append(v + Vector3(0, 0.5, 0))
	assert_almost_eq(CollisionSimplifier.measured_error(plane, lifted, SAMPLES), 0.5, 1e-4)


func test_degenerate_triangles_do_not_spoil_the_measurement() -> void:
	# Zero-area triangles (two corners the same, as at a sphere's poles) once
	# gave NaN distances, and one NaN through minf() reset the nearest found.
	var plane := _plane(10)
	var spoiled := PackedVector3Array()
	for t in plane.size() / 3:
		spoiled.append_array([plane[t * 3], plane[t * 3], plane[t * 3 + 1]])  # Degenerate.
		spoiled.append_array(plane.slice(t * 3, t * 3 + 3))
	assert_almost_eq(CollisionSimplifier.measured_error(plane, spoiled, SAMPLES), 0.0, 1e-6)
	assert_almost_eq(CollisionSimplifier.measured_error(spoiled, plane, SAMPLES), 0.0, 1e-6)


func test_pick_keeps_the_coarsest_level_within_budget() -> void:
	var sphere := _sphere()
	var loose := CollisionSimplifier.pick(sphere, 1.0, 100.0, SAMPLES)
	assert_eq(loose.faces, CollisionSimplifier.levels(sphere)[-1], "a huge budget takes the coarsest")
	var tight := CollisionSimplifier.pick(sphere, 1.0, 0.0, SAMPLES)
	assert_eq(tight.faces, sphere, "no budget keeps the original")
	assert_eq(tight.level, -1)
	# This sphere (radius 10) is off by about 1 at its finest level and 8 at its
	# coarsest, so a budget of 2 lands in between.
	var mid := CollisionSimplifier.pick(sphere, 1.0, 2.0, SAMPLES)
	assert_lte(mid.error, 2.0)
	assert_lt(mid.faces.size(), sphere.size())
	assert_gt(mid.faces.size(), loose.faces.size())


func test_pick_measures_in_world_units() -> void:
	# The same mesh scaled up 100 times: errors grow with it, so less is removed.
	var sphere := _sphere(0.1)
	var small := CollisionSimplifier.pick(sphere, 1.0, 0.2, SAMPLES)
	var scaled := CollisionSimplifier.pick(sphere, 100.0, 0.2, SAMPLES)
	assert_gte(scaled.faces.size(), small.faces.size())
	assert_lte(scaled.error, 0.2)


## Babylon 5: the reactor and main cylinder use simplified collision.

const B5 := "res://ships/earth alliance/babylon 5/"


func _section_shape(scene: String) -> ConcavePolygonShape3D:
	var section: Node = load(B5 + scene).instantiate()
	var shapes := section.find_children("*", "CollisionShape3D", true, false)
	var shape := (shapes[0] as CollisionShape3D).shape as ConcavePolygonShape3D
	section.free()
	return shape


func test_babylon_5_reactor_and_cylinder_collision_is_simplified() -> void:
	# Full detail was 260k and 243k triangles, 265 ms of Jolt building on load.
	for scene in ["reactor_section.scn", "main_cylinder.scn"]:
		var shape := _section_shape(scene)
		assert_true(shape.resource_path.begins_with(B5 + "collision/"), scene)
		assert_lt(shape.get_faces().size() / 3, 80000, scene)
