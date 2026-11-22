extends GutTest
## A star system is a zone: a SubViewport with its own World3D, and its ships,
## bolts and spawners directly under it (zone slice 2).

const ShipScene := preload("res://ships/Ship.tscn")
const SystemScene := preload("res://systems/system_template.tscn")
const TestSystemScene := preload("res://systems/test_system/test_system.tscn")


func _system(scene: PackedScene = SystemScene) -> System:
	var system: System = scene.instantiate()
	add_child_autofree(system)
	return system


func test_system_is_a_zone_with_its_own_world() -> void:
	var system := _system()
	assert_true(system is SubViewport)
	assert_true(system.own_world_3d)
	assert_ne(system.find_world_3d(), get_viewport().find_world_3d())


func test_zone_parts_sit_under_the_root() -> void:
	var system := _system()
	for part in ["ships", "bolts", "ShipSpawner", "BoltSpawner", "StarField", "RTSCameras"]:
		assert_true(system.has_node(part), part)


func test_test_system_keeps_its_scenery() -> void:
	# The playtest system adds lights, an environment and music on top of the template.
	var system := _system(TestSystemScene)
	for part in ["WorldEnvironment", "DirectionalLight3D", "AudioStreamPlayer", "RTSCameras/RtsCamera"]:
		assert_true(system.has_node(part), part)


func test_add_ship_places_it_in_ships() -> void:
	var system := _system()
	var ship: Ship = ShipScene.instantiate()
	system.add_ship(ship)
	assert_eq(ship.get_parent(), system.get_node("ships"))
	assert_has(system.get_ships(), ship)


func test_ship_finds_its_system() -> void:
	var system := _system()
	var ship: Ship = ShipScene.instantiate()
	system.add_ship(ship)
	assert_eq(ship.get_current_system(), system)
	assert_eq(System.find_for(ship), system)


func test_find_for_outside_a_system_is_null() -> void:
	var node := Node3D.new()
	add_child_autofree(node)
	assert_null(System.find_for(node))


func test_a_gun_puts_its_bolt_in_the_system() -> void:
	# Gun.fire finds the system's bolts node by a relative path
	# (Gun > Guns > ship > ships > system), so it depends on the system layout.
	var system := _system()
	var ship: Ship = ShipScene.instantiate()
	system.add_ship(ship)
	var gun: Gun = preload("res://ship_systems/weapons/Gun.tscn").instantiate()
	gun.bolt_resource = preload("res://ship_systems/weapons/effects/bolt/Bolt.tscn")
	ship.get_node("Guns").add_child(gun)
	ship.get_node("Guns").fire()
	assert_eq(system.get_node("bolts").get_child_count(), 1)
