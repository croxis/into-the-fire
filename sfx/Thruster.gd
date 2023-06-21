@tool
extends Node3D

var max_force_vector: Vector3
var max_torque_vector: Vector3
# In newtons...
@export var max_force := 0.0
# Reduction to force based on damage. 0-1. 1 is 100% reduction/destroyed
var health := 1.0:
	set(new_health):
		health = clamp(new_health, 0.0, 1.0)
		calculate_force()
# Dec. percent. 0-100% is 0-1.0.
@export var power := 0.0:
	set(new_power):
		if new_power < 0.0:
			new_power = 0.0
		power = new_power
		$engine_plume2/OmniLight3D.light_energy = power * 4.0
		calculate_force()
var force_vector: Vector3:
	get:
		return max_force_vector * power * health
var torque_vector: Vector3:
	get:
		return max_torque_vector * power * health


# Called when the node enters the scene tree for the first time.
func _ready():
	calculate_vectors()


func calculate_force() -> float:
	var force = maxf(max_force * power * health, 0.0)
	if force > 0.0:
		$engine_plume2.visible = true
	else:
		$engine_plume2.visible = false
	return force


func calculate_vectors() -> void:
	# https://github.com/XEonAX/PolitePonderous/blob/master/Assets/Scripts/Thruster.cs
	# Called whenever 
	var spaceship: RigidBody3D = get_parent().get_parent()
	var force_forward := transform.basis.z.dot(spaceship.transform.basis.z)
	var force_right := transform.basis.z.dot(spaceship.transform.basis.x)
	var force_up := transform.basis.z.dot(spaceship.transform.basis.y)
	
	var torque_cross := (position - spaceship.center_of_mass).cross(global_transform.basis.z)
	var torque_forward := torque_cross.dot(spaceship.global_transform.basis.z)
	var torque_right := torque_cross.dot(spaceship.global_transform.basis.x)
	var torque_up := torque_cross.dot(spaceship.global_transform.basis.y)
	
	max_force_vector = Vector3(force_right, force_up, force_forward) * max_force
	max_torque_vector = Vector3(torque_right, torque_up, torque_forward) * max_force
