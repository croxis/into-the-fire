extends GutTest
## Thrusters work out their push in the ship's own frame, however the ship was
## turned when it entered the tree. The server places a launching ship in its
## bay before adding it; a client's spawner adds it first and moves it after:
## the same ship must push and turn the same on both, or the pilot's own
## prediction disagrees with the server on every tick of a turn.

const SystemScene := preload("res://systems/system_template.tscn")

var system: System


func before_each() -> void:
	system = SystemScene.instantiate()
	add_child_autofree(system)


func _starfury(turned: Basis) -> Ship:
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	ship.transform = Transform3D(turned, Vector3(0, 0, randf() * 1000.0))
	system.add_ship(ship)
	return ship


## [force, torque] in the ship's own frame for these throttles.
func _push(ship: Ship, linear: Vector3, rotation: Vector3) -> Array[Vector3]:
	ship.get_node("Engines").request_thrust(linear, rotation)
	var basis := ship.global_basis
	var push := ship.thrust(basis * Vector3(0, 0, 1.3), basis)
	return [basis.inverse() * push[0], basis.inverse() * push[1]]


func test_a_ship_turned_as_it_enters_pushes_the_same_way() -> void:
	var straight := _starfury(Basis())
	var turned := _starfury(Basis.from_euler(Vector3(0.7, -2.1, 0.4)))
	for throttles in [[Vector3(0, 0, -1), Vector3.ZERO], [Vector3.ZERO, Vector3(-1, 1, 0)],
			[Vector3(0, 0, -1), Vector3(0, 0, 1)], [Vector3(1, 0, 0), Vector3(1, 0, -1)]]:
		var a := _push(straight, throttles[0], throttles[1])
		var b := _push(turned, throttles[0], throttles[1])
		assert_almost_eq(b[0], a[0], Vector3.ONE * 1e-3, "force for %s" % [throttles])
		assert_almost_eq(b[1], a[1], Vector3.ONE * 1e-2, "torque for %s" % [throttles])
