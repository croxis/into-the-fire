extends GutTest
## Sitting characters at consoles.

const CharacterScene := preload("res://characters/character.tscn")


## A console like the Starfury cockpit: capabilities mixed with other children.
func _console() -> Console:
	var console := Console.new()
	console.name = "Cockpit"
	var camera := Camera3D.new()
	camera.name = "Camera"
	console.add_child(camera)
	console.camera_path = NodePath("Camera")
	var helm := ConsoleCapability.new()
	helm.name = "Helm"
	console.add_child(helm)
	var reticles := Node3D.new()  # Not a capability.
	reticles.name = "TargetRecticles"
	console.add_child(reticles)
	add_child_autofree(console)
	return console


func _character() -> Character:
	var c: Character = CharacterScene.instantiate()
	c.name = "Pilot"
	c.multiplayer_id = multiplayer.get_unique_id()
	add_child_autofree(c)
	return c


func test_occupy_ignores_children_that_are_not_capabilities() -> void:
	var console := _console()
	var pilot := _character()

	assert_true(console.occupy(pilot))
	assert_eq(console.occupant, pilot)
	assert_eq(pilot.current_console, console)


func test_occupied_console_refuses_a_second_character() -> void:
	var console := _console()
	console.occupy(_character())
	var second := _character()
	assert_false(console.occupy(second))
	assert_null(second.current_console)


func test_get_capability_finds_by_type_not_node_name() -> void:
	var console := _console()
	var command := CommandCapability.new()
	command.name = "CapabilityCommand"  # Node names vary between scenes.
	console.add_child(command)

	assert_eq(console.get_capability(CommandCapability), command)
	assert_null(console.get_capability(WeaponsCapability), "no weapons on this console")


func test_has_capability_is_case_insensitive() -> void:
	var console := _console()
	assert_true(console.has_capability("helm"))
	assert_false(console.has_capability("TargetRecticles"), "only capabilities count")
