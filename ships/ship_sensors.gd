class_name ShipSensors
extends RefCounted
## What a ship gives off to others' sensors and whether a sensor picks a ship
## up (fog of war). Functions only, no state: Ship keeps its outputs, its cached
## visual radius and its detected_ships, and calls these.


## What a ship gives off with [param thrust_newtons] of thrust: its base plus
## its drive's share, as (EM, neutrino, gravimetric).
static func emissions(em_base: float, neutrino_base: float, drive: DriveProfile,
		thrust_newtons: float) -> Vector3:
	var out := Vector3(em_base, neutrino_base, 0.0)
	if drive:
		var mn := thrust_newtons / 1e6
		out += Vector3(drive.em_per_meganewton, drive.neutrino_per_meganewton,
				drive.gravimetric_per_meganewton) * mn
	return out


## The thrust all of [param ship]'s thrusters are putting out now, in newtons:
## every one that is firing burns, whichever way it pushes.
static func thrust_now(ship: Node3D) -> float:
	if not ship.has_node("Engines"):
		return 0.0
	var total := 0.0
	for thruster in ship.get_node("Engines").thrusters:
		total += (thruster.force_vector as Vector3).length()
	return total


## How far [param ship] reaches from its origin, in metres: the radius of a
## sphere around everything it is made of, for visual detection. Its own
## collision shapes and those of physics bodies inside it (the Hyperion's hull
## is static bodies in its model), never areas (docks, launch bays). Read from
## the physics server, so it works with no renderer. -1 when it has no shapes
## yet.
static func reach(ship: PhysicsBody3D) -> float:
	var radius := 0.0
	var shapes := 0
	var to_ship := ship.global_transform.affine_inverse()
	var bodies: Array[Node] = [ship]
	bodies.append_array(ship.find_children("*", "PhysicsBody3D", true, false))
	for body: PhysicsBody3D in bodies:
		var rid := body.get_rid()
		var body_in_ship := to_ship * body.global_transform if body != ship else Transform3D()
		for i in PhysicsServer3D.body_get_shape_count(rid):
			shapes += 1
			radius = maxf(radius, _shape_reach(PhysicsServer3D.body_get_shape(rid, i),
					body_in_ship * PhysicsServer3D.body_get_shape_transform(rid, i)))
	return radius if shapes > 0 else -1.0


## Whether [param sensor] at [param from] picks up [param other] now. Each
## signature falls off with the square of the distance (in km: an output of
## 1.0 is a signal of 1.0 at 1 km). Higher sensitivity is better: sensitivity
## S picks up signals down to 1/S, so 0 is blind. It is also seen when it looks
## bigger than the sensor's visual acuity (degrees across), whatever it emits.
static func detects(sensor: Sensor, from: Vector3, other: Ship) -> bool:
	var distance_squared := from.distance_squared_to(other.global_position)
	var km_squared := distance_squared / 1e6
	var em_signal := other.em_output / km_squared
	var neutrino_signal := other.neutron_output / km_squared
	var gravimetric_signal := other.gravimetric_output / km_squared
	if em_signal * sensor.em_sensitive > 1.0 or neutrino_signal * sensor.neutrino_sensitive > 1.0 \
			or gravimetric_signal * sensor.gravametric_sensitive > 1.0:
		return true
	if sensor.visual_acuity_degrees > 0.0:
		var across := rad_to_deg(2.0 * atan2(other.visual_radius(), sqrt(distance_squared)))
		return across > sensor.visual_acuity_degrees
	return false


## How far [param shape], placed at [param at] in the body, reaches from the
## body's origin.
static func _shape_reach(shape: RID, at: Transform3D) -> float:
	var data: Variant = PhysicsServer3D.shape_get_data(shape)
	var stretch := at.basis.get_scale()
	var widest := maxf(absf(stretch.x), maxf(absf(stretch.y), absf(stretch.z)))
	match PhysicsServer3D.shape_get_type(shape):
		PhysicsServer3D.SHAPE_SPHERE:
			return at.origin.length() + float(data) * widest
		PhysicsServer3D.SHAPE_BOX:
			return at.origin.length() + (data as Vector3).length() * widest
		PhysicsServer3D.SHAPE_CAPSULE, PhysicsServer3D.SHAPE_CYLINDER:
			var d: Dictionary = data
			return at.origin.length() + Vector2(d["radius"], d["height"] / 2.0).length() * widest
		PhysicsServer3D.SHAPE_CONVEX_POLYGON:
			return _points_reach(data, at)
		PhysicsServer3D.SHAPE_CONCAVE_POLYGON:
			return _points_reach((data as Dictionary)["faces"], at)
	return 0.0


static func _points_reach(points: PackedVector3Array, at: Transform3D) -> float:
	var furthest := 0.0
	for p in points:
		furthest = maxf(furthest, (at * p).length())
	return furthest
