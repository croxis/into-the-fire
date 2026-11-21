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
