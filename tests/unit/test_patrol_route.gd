extends GutTest
## PatrolRoute: default patrol routes authored in capital ship and station
## scenes (Marker3D waypoints under PatrolRoutes), and the ring a commander
## builds when none fits. Routes travel in objectives relative to their anchor
## ship, so a moving carrier's patrol moves with it.


func _anchor() -> Node3D:
	var anchor := Node3D.new()
	add_child_autofree(anchor)
	return anchor


func _route(anchor: Node3D, points: Array) -> PatrolRoute:
	var routes := anchor.get_node_or_null("PatrolRoutes")
	if routes == null:
		routes = Node3D.new()
		routes.name = "PatrolRoutes"
		anchor.add_child(routes)
	var route := PatrolRoute.new()
	routes.add_child(route)
	for p: Vector3 in points:
		var marker := Marker3D.new()
		marker.position = p
		route.add_child(marker)
	return route


func test_waypoints_are_the_markers_in_order() -> void:
	var anchor := _anchor()
	var route := _route(anchor, [Vector3(1000, 0, 0), Vector3(0, 0, 2000), Vector3(-1000, 0, 0)])
	assert_eq(route.waypoints(anchor), [Vector3(1000, 0, 0), Vector3(0, 0, 2000), Vector3(-1000, 0, 0)])


func test_waypoints_are_relative_to_the_anchor_however_it_is_placed() -> void:
	var anchor := _anchor()
	var route := _route(anchor, [Vector3(1000, 0, 0)])
	anchor.global_transform = Transform3D(Basis(Vector3.UP, PI / 2), Vector3(50000, 0, 0))
	var local := route.waypoints(anchor)
	assert_almost_eq(local[0], Vector3(1000, 0, 0), Vector3.ONE * 0.01, "in the anchor's own frame")
	var world := PatrolRoute.from_anchor(anchor, local)
	assert_almost_eq(world[0], Vector3(50000, 0, -1000), Vector3.ONE * 0.01, "back where the marker is")


func test_a_scaled_anchor_does_not_stretch_a_route() -> void:
	# Ships are placed by position and rotation only, but parts of some sit
	# under a scale (Babylon 5's arms at 0.81).
	var anchor := _anchor()
	var route := _route(anchor, [Vector3(1000, 0, 0)])
	anchor.scale = Vector3.ONE * 2.0
	var local := route.waypoints(anchor)
	assert_almost_eq(local[0].length(), 2000.0, 0.01, "metres from the anchor, as the marker sits")
	assert_almost_eq(PatrolRoute.from_anchor(anchor, local)[0], route.get_child(0).global_position,
			Vector3.ONE * 0.01)


func test_a_ring_around_the_anchor() -> void:
	var ring := PatrolRoute.ring(12000.0, 6)
	assert_eq(ring.size(), 6)
	for p in ring:
		assert_almost_eq(p.length(), 12000.0, 0.01)
		assert_almost_eq(p.y, 0.0, 0.01, "level with the anchor")
	assert_ne(PatrolRoute.ring(12000.0, 6, 0.5)[0], ring[0], "a phase turns it")


func test_routes_fit_within_a_radius() -> void:
	assert_true(PatrolRoute.fits_within([Vector3(15000, 0, 0), Vector3(0, 0, -19000)], 20000.0))
	assert_false(PatrolRoute.fits_within([Vector3(25000, 0, 0)], 20000.0))
	assert_false(PatrolRoute.fits_within([], 20000.0), "no waypoints is no route")


func test_a_commander_takes_an_authored_route_that_fits_else_builds_one() -> void:
	var anchor := _anchor()
	assert_eq(PatrolRoute.pick(anchor, 20000.0).size(), PatrolRoute.RING_POINTS, "none authored: a ring")
	_route(anchor, [Vector3(30000, 0, 0), Vector3(0, 0, 30000)])  # Too far out.
	_route(anchor, [Vector3(9000, 0, 0), Vector3(0, 0, 9000)])
	assert_eq(PatrolRoute.pick(anchor, 20000.0), [Vector3(9000, 0, 0), Vector3(0, 0, 9000)])
	assert_eq(PatrolRoute.pick(anchor, 5000.0).size(), PatrolRoute.RING_POINTS, "neither fits 5 km")
	for p in PatrolRoute.pick(anchor, 5000.0):
		assert_lt(p.length(), 5000.0, "the ring stays inside")


func test_the_station_and_capital_ship_have_default_routes() -> void:
	for id in [&"b5:babylon_5", &"b5:hyperion"]:
		var ship: Ship = Content.instantiate(id)
		add_child_autofree(ship)
		var routes := PatrolRoute.routes_of(ship)
		assert_gt(routes.size(), 0, "%s has a patrol route" % id)
		for route in routes:
			assert_true(PatrolRoute.fits_within(route.waypoints(ship), 20000.0),
					"%s's %s is within 20 km" % [id, route.name])
