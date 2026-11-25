extends GutTest
## Helm turns pilot input into engine thrust requests.

const HelmScene := preload("res://ship_systems/workstations/helm.tscn")


## Stands in for the Engines node and records the last request.
class EnginesStub extends Node:
	var linear := Vector3.ZERO
	var rotation_request := Vector3.ZERO

	func request_thrust(linear_throttle: Vector3, rotation_throttle: Vector3) -> void:
		linear = linear_throttle
		rotation_request = rotation_throttle


var engines: EnginesStub


func _helm() -> HelmCapability:
	var helm: HelmCapability = HelmScene.instantiate()
	add_child_autofree(helm)
	helm.set_physics_process(false)  # Ticked by hand below.
	engines = autofree(EnginesStub.new())
	helm.system = engines
	return helm


func test_assist_is_what_a_tick_requests() -> void:
	# A replay works out thrust again with assist(), from the replayed state.
	var helm := _helm()
	for pid: PID in helm.get_node("PIDS").get_children():
		pid.kp = 2.0  # As the Starfury's helm has; the bare helm scene has none.
	var input := {"throttle": Vector3(0, 0, -1), "rotation": Vector3.ZERO,
			"autospin": true, "autobreak": true}
	var throttles := helm.assist(input, Vector3(0.5, 0, -3), Vector3(0, 0.2, 0), 1.0 / 60.0)
	assert_eq(throttles[0].z, -1.0, "input on an axis isn't touched")
	assert_ne(throttles[0].x, 0.0, "autobreak pushes against sideways drift")
	assert_ne(throttles[1].y, 0.0, "autospin pushes against the spin")


func test_input_record_is_what_the_pilot_set() -> void:
	var helm := _helm()
	helm.throttle = Vector3(0, 0, -1)
	helm.input_rotation_throttle = Vector3(0, 1, 0)
	helm.autospin = true
	assert_eq(helm.input_record(), {"throttle": Vector3(0, 0, -1), "rotation": Vector3(0, 1, 0),
			"autospin": true, "autobreak": false})


func test_manual_rotation_reaches_engines() -> void:
	var helm := _helm()
	helm.input_rotation_throttle = Vector3(0, 1, 0)
	helm._rollback_tick(1.0 / 60.0, 0, true)
	assert_eq(engines.rotation_request, Vector3(0, 1, 0))


func test_linear_throttle_reaches_engines() -> void:
	var helm := _helm()
	helm.throttle = Vector3(0, 0, -1)
	helm._rollback_tick(1.0 / 60.0, 0, true)
	assert_eq(engines.linear, Vector3(0, 0, -1))


func test_releasing_rotation_input_stops_rotation_request() -> void:
	var helm := _helm()
	helm.input_rotation_throttle = Vector3(0, 1, 0)
	helm._rollback_tick(1.0 / 60.0, 0, true)
	helm.input_rotation_throttle = Vector3.ZERO
	helm._rollback_tick(1.0 / 60.0, 0, true)
	assert_eq(engines.rotation_request, Vector3.ZERO, "no autospin: no input means no torque")
