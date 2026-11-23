class_name CollisionSimplifier
extends RefCounted
## Simplifies collision triangle meshes (the faces of a ConcavePolygonShape3D)
## with Godot's own mesh simplifier, meshoptimizer, as used for mesh LODs, and
## measures how far each simplified version strays from the original.
##
## Jolt builds a mesh shape when its body joins a physics space, on the main
## thread, in time roughly proportional to its triangles. Collision copied
## straight from a detailed render mesh can take a large part of a second.
## Used by tools/simplify_collision.gd.


## Joins identical corners of a triangle soup: [vertices, indices]. The
## simplifier needs shared vertices to know which triangles are neighbours.
static func weld(faces: PackedVector3Array) -> Array:
	var index_of := {}
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	indices.resize(faces.size())
	for i in faces.size():
		var k: Variant = index_of.get(faces[i])
		if k == null:
			k = vertices.size()
			index_of[faces[i]] = k
			vertices.append(faces[i])
		indices[i] = k
	return [vertices, indices]


## Simplified versions of [param faces], finest first, as triangle soups.
## Normals are ignored (merge angle 180°): only the shape matters for collision.
static func levels(faces: PackedVector3Array) -> Array[PackedVector3Array]:
	var welded := weld(faces)
	var vertices: PackedVector3Array = welded[0]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = welded[1]
	var mesh := ImporterMesh.new()
	mesh.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.generate_lods(180.0, 180.0, [])
	var result: Array[PackedVector3Array] = []
	for lod in mesh.get_surface_lod_count(0):
		var indices := mesh.get_surface_lod_indices(0, lod)
		var soup := PackedVector3Array()
		soup.resize(indices.size())
		for i in indices.size():
			soup[i] = vertices[indices[i]]
		result.append(soup)
	return result


## The largest gap between the two surfaces found at [param samples] random
## points on each, measured both ways: a -> b finds details b lost, b -> a
## finds where b bulges out. In the faces' own units. Sampled, so a gap
## narrower than the sampling can be missed; the seed keeps runs repeatable.
static func measured_error(a: PackedVector3Array, b: PackedVector3Array,
		samples := 3000, seed := 1) -> float:
	var box := _bounds(a).merge(_bounds(b))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var worst := 0.0
	var grid_b := _Grid.new(b, _cell_size(b, box))
	for p in _samples(a, samples, rng):
		worst = maxf(worst, grid_b.distance(p))
	var grid_a := _Grid.new(a, _cell_size(a, box))
	for p in _samples(b, samples, rng):
		worst = maxf(worst, grid_a.distance(p))
	return worst


## Grid cells about as big as the mesh's triangles (but no finer than 1/200 of
## the bounds): a coarse mesh gets big cells, so its nearest triangle is a few
## cells away rather than dozens.
static func _cell_size(faces: PackedVector3Array, box: AABB) -> float:
	var count := faces.size() / 3
	var step := maxi(1, count / 1000)
	var total := 0.0
	var n := 0
	for t in range(0, count, step):
		total += faces[t * 3].distance_to(faces[t * 3 + 1]) + faces[t * 3 + 1].distance_to(faces[t * 3 + 2])
		n += 2
	return maxf(maxf(box.size.length() / 200.0, total / maxi(n, 1)), 1e-6)


## The coarsest level whose measured error, times [param scale] (local units to
## metres), is within [param budget] metres. Returns {faces, error, level};
## level -1 and the original faces when no level fits. [param samples] is
## passed to [method measured_error]. Levels are tried finest
## first and the search stops at the first that does not fit, since coarser
## levels only lose more.
static func pick(faces: PackedVector3Array, scale: float, budget: float,
		samples := 3000) -> Dictionary:
	var best := {faces = faces, error = 0.0, level = -1}
	var all := levels(faces)
	for i in all.size():
		var error := measured_error(faces, all[i], samples) * scale
		if error > budget:
			break
		best = {faces = all[i], error = error, level = i}
	return best


static func _bounds(faces: PackedVector3Array) -> AABB:
	var box := AABB(faces[0], Vector3.ZERO)
	for v in faces:
		box = box.expand(v)
	return box


## Random points spread over the triangles (triangles picked uniformly, then a
## uniform point on each).
static func _samples(faces: PackedVector3Array, n: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var out := PackedVector3Array()
	var count := faces.size() / 3
	for i in n:
		var t := rng.randi_range(0, count - 1) * 3
		var u := rng.randf()
		var v := rng.randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		out.append(faces[t] + (faces[t + 1] - faces[t]) * u + (faces[t + 2] - faces[t]) * v)
	return out


## Triangles bucketed in a uniform grid, for nearest-surface distances.
class _Grid:
	var cell: float
	# Vector3i -> Array of triangle indices. Not PackedInt32Array: a packed array
	# read from a Dictionary is a copy, so appending to it would be lost.
	var cells := {}
	var faces: PackedVector3Array

	func _init(p_faces: PackedVector3Array, p_cell: float) -> void:
		faces = p_faces
		cell = p_cell
		for t in faces.size() / 3:
			var box := AABB(faces[t * 3], Vector3.ZERO).expand(faces[t * 3 + 1]).expand(faces[t * 3 + 2])
			var lo := Vector3i((box.position / cell).floor())
			var hi := Vector3i((box.end / cell).floor())
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					for z in range(lo.z, hi.z + 1):
						var key := Vector3i(x, y, z)
						if not cells.has(key):
							cells[key] = []
						cells[key].append(t)

	## Distance from [param p] to the nearest triangle. Searches rings of cells
	## outward; a triangle in ring r is at least (r - 1) cells away, so the
	## search stops once the best found is closer than that.
	func distance(p: Vector3, max_rings := 8) -> float:
		var c := Vector3i((p / cell).floor())
		var best := INF
		for r in max_rings + 1:
			for x in range(c.x - r, c.x + r + 1):
				for y in range(c.y - r, c.y + r + 1):
					for z in range(c.z - r, c.z + r + 1):
						if maxi(maxi(absi(x - c.x), absi(y - c.y)), absi(z - c.z)) != r:
							continue  # Inner rings are done.
						var list: Variant = cells.get(Vector3i(x, y, z))
						if list == null:
							continue
						for t: int in list:
							best = minf(best, _distance(p, t))
			if best <= r * cell:
				return best
		# Nothing close: check every triangle.
		for t in faces.size() / 3:
			best = minf(best, _distance(p, t))
		return best

	func _distance(p: Vector3, t: int) -> float:
		return p.distance_to(_closest(p, faces[t * 3], faces[t * 3 + 1], faces[t * 3 + 2]))

	## Closest point on triangle abc to p (Ericson, Real-Time Collision
	## Detection, 5.1.5). A degenerate triangle (no area: meshes have them, e.g.
	## at a sphere's poles) is treated as its edges: the formula would divide by
	## zero and return NaN, and one NaN through minf() silently resets a
	## running minimum.
	static func _closest(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
		if (b - a).cross(c - a).length_squared() < 1e-20:
			var candidates := [Geometry3D.get_closest_point_to_segment(p, a, b),
					Geometry3D.get_closest_point_to_segment(p, b, c),
					Geometry3D.get_closest_point_to_segment(p, c, a)]
			var nearest: Vector3 = candidates[0]
			for q: Vector3 in candidates:
				if p.distance_squared_to(q) < p.distance_squared_to(nearest):
					nearest = q
			return nearest
		var ab := b - a
		var ac := c - a
		var ap := p - a
		var d1 := ab.dot(ap)
		var d2 := ac.dot(ap)
		if d1 <= 0 and d2 <= 0:
			return a
		var bp := p - b
		var d3 := ab.dot(bp)
		var d4 := ac.dot(bp)
		if d3 >= 0 and d4 <= d3:
			return b
		var vc := d1 * d4 - d3 * d2
		if vc <= 0 and d1 >= 0 and d3 <= 0:
			return a + ab * (d1 / (d1 - d3))
		var cp := p - c
		var d5 := ab.dot(cp)
		var d6 := ac.dot(cp)
		if d6 >= 0 and d5 <= d6:
			return c
		var vb := d5 * d2 - d1 * d6
		if vb <= 0 and d2 >= 0 and d6 <= 0:
			return a + ac * (d2 / (d2 - d6))
		var va := d3 * d6 - d5 * d4
		if va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0:
			return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
		var denom := 1.0 / (va + vb + vc)
		return a + ab * (vb * denom) + ac * (vc * denom)
