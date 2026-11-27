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
		if new_power < 0.009:
			new_power = 0.0
		power = new_power
		$OmniLight3D.light_energy = power * 4.0
		calculate_force()
var requested_power := 0.0:
	set(new_power):
		if new_power < 0.0:
			new_power = 0.0
		if new_power > requested_power:
			requested_power = new_power
		if new_power == 0.0:
			requested_power = 0.0
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
		$engine_plume.visible = true
	else:
		$engine_plume.visible = false
	return force


func calculate_vectors() -> void:
	# https://github.com/XEonAX/PolitePonderous/blob/master/Assets/Scripts/Thruster.cs
	# In the ship's own frame (Engines' transform x ours), never from the ship's
	# world orientation: the server and a client add the same ship to the tree
	# turned differently (the server places it in its bay first), and the push
	# must come out the same on both, or own-ship prediction disagrees with the
	# server on every tick of a turn.
	var spaceship: RigidBody3D = get_parent().get_parent()
	var in_ship: Transform3D = (get_parent() as Node3D).transform * transform
	var along := in_ship.basis.z  # Which way it pushes: (right, up, forward) in the ship's frame.
	max_force_vector = along * max_force
	max_torque_vector = (in_ship.origin - spaceship.center_of_mass).cross(along) * max_force
