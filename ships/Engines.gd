extends Node3D

var thrusters: Array[Node]
var main_thrusters: Array[Node]
var reverse_thrusters: Array[Node]
var left_lateral_thrusters: Array[Node]
var right_lateral_thrusters: Array[Node]
var dorsal_thrusters: Array[Node]
var ventral_thrusters: Array[Node]
var thruster_vector_matrix: Array[Array]
var thruster_control_vector: Array[float]
var thruster_control_vectors: Array[Array]
var twelve_control_vectors: Array[Array]

var min_control_vector := []
var max_control_vector := []
var initial_guess_control_vector := []

var linear_force: Vector3:
	get:
		var force := Vector3(0.0, 0.0, 0.0)
		for thruster in thrusters:
			force += thruster.force_vector
		return force
var torque_force: Vector3:
	get:
		var force := Vector3(0.0, 0.0, 0.0)
		for thruster in thrusters:
			force += thruster.torque_vector
		return force


# Called when the node enters the scene tree for the first time.
func _ready():
	#bootup_thrusters()
	calculate_thrusters()


func calculate_thrusters():
	thrusters = get_children()
	# Lateral Calculation
	main_thrusters = thrusters.filter(func(thruster): return thruster.transform.basis.z.normalized().dot(transform.basis.z.normalized()) < -0.9)
	reverse_thrusters = thrusters.filter(func(thruster): return thruster.transform.basis.z.normalized().dot(transform.basis.z.normalized()) > 0.9)
	dorsal_thrusters = thrusters.filter(func(thruster): return thruster.transform.basis.z.normalized().dot(transform.basis.y.normalized()) < -0.9)
	ventral_thrusters = thrusters.filter(func(thruster): return thruster.transform.basis.z.normalized().dot(transform.basis.y.normalized()) > 0.9)
	left_lateral_thrusters = thrusters.filter(func(thruster): return thruster.transform.basis.z.normalized().dot(transform.basis.x.normalized()) > 0.9)
	right_lateral_thrusters = thrusters.filter(func(thruster): return thruster.transform.basis.z.normalized().dot(transform.basis.x.normalized()) < -0.9)
	
	for thruster in thrusters:
		thruster.calculate_vectors()


func request_thrust(linear_throttle: Vector3, rotation_throttle: Vector3):
	# NOTE: I am cheating here. We're just summing up the appropriate vectors
	# instead of modeling actual ship orientation software
	for thruster in thrusters:
		thruster.power = 0
	
	if linear_throttle.z > 0:
		# Backwards
		for thruster in reverse_thrusters:
			thruster.requested_power = linear_throttle.z
	elif linear_throttle.z < 0:
		# Forward
		for thruster in main_thrusters:
			thruster.requested_power = -linear_throttle.z
	
	if linear_throttle.y > 0:
		# Backwards
		for thruster in ventral_thrusters:
			thruster.requested_power = linear_throttle.y
	elif linear_throttle.y < 0:
		# Forward
		for thruster in dorsal_thrusters:
			thruster.requested_power = -linear_throttle.y
			
	if linear_throttle.x > 0:
		# Backwards
		for thruster in left_lateral_thrusters:
			thruster.requested_power = linear_throttle.x
	elif linear_throttle.x < 0:
		# Forward
		for thruster in right_lateral_thrusters:
			thruster.requested_power = -linear_throttle.x
	
	for thruster in thrusters:
		if rotation_throttle.x < 0 && thruster.max_torque_vector.normalized().x > 0.4:
			thruster.requested_power = abs(rotation_throttle.x)
		elif rotation_throttle.x > 0 && thruster.max_torque_vector.normalized().x < -0.4:
			thruster.requested_power = abs(rotation_throttle.x)
		if rotation_throttle.y < 0 && thruster.max_torque_vector.normalized().y < -0.4:
			thruster.requested_power = abs(rotation_throttle.y)
		elif rotation_throttle.y > 0 && thruster.max_torque_vector.normalized().y > 0.4:
			thruster.requested_power = abs(rotation_throttle.y)
		if rotation_throttle.z < 0 && thruster.max_torque_vector.normalized().z > 0.4:
			thruster.requested_power = abs(rotation_throttle.z)
		elif rotation_throttle.z > 0 && thruster.max_torque_vector.normalized().z < -0.4:
			thruster.requested_power = abs(rotation_throttle.z)
	
	for thruster in thrusters:
		thruster.power = thruster.requested_power
		thruster.requested_power = 0


# One of these days I'll properly simulate the thrusters
# https://github.com/XEonAX/PolitePonderous/blob/master/Assets/Scripts/Spaceship.cs
func bootup_thrusters():
	thrusters = get_children()
	main_thrusters = thrusters.filter(func(thruster): return thruster.transform.basis.z.dot(transform.basis.z) > 0.9)
	reverse_thrusters = thrusters.filter(func(thruster): return thruster.transform.basis.z.dot(- transform.basis.z) > 0.9)
	dorsal_thrusters = thrusters.filter(func(thruster): return thruster.transform.basis.z.dot(- transform.basis.y) > 0.9)
	ventral_thrusters = thrusters.filter(func(thruster): return thruster.transform.basis.z.dot(transform.basis.y) > 0.9)
	left_lateral_thrusters = thrusters.filter(func(thruster): return thruster.transform.basis.z.dot(transform.basis.x) > 0.9)
	right_lateral_thrusters = thrusters.filter(func(thruster): return thruster.transform.basis.z.dot(- transform.basis.x) > 0.9)
	
	print_debug("Main Thrusters: ", main_thrusters)
	print_debug(reverse_thrusters)
	print_debug(dorsal_thrusters)
	print_debug(ventral_thrusters)
	print_debug(left_lateral_thrusters)
	print_debug(right_lateral_thrusters)
	
	for thruster in thrusters:
		thruster.calculate_vectors()
		thruster_vector_matrix.append([thruster.torque_vector.x,
									thruster.torque_vector.y,
									thruster.torque_vector.z,
									thruster.force_vector.x,
									thruster.force_vector.y,
									thruster.force_vector.z])
	
	#NormalizeRows
	#https://github.com/mathnet/mathnet-numerics/blob/c05c32645c43cb80db45a59a6e99d09bd8a1fab0/src/Numerics/LinearAlgebra/Double/Matrix.cs#L693
	var norminv: Array[float]
	
	for row in thruster_vector_matrix:
		var sum := 0.0
		for n in row:
			sum += abs(n)
		norminv.append(sum)
	
	for i in range(norminv.size()):
		if norminv[i] == 0:
			norminv[i] == 1.0
		else:
			norminv[i] = 1.0/norminv[i]
	
	for i in range(norminv.size()):
		for y in range(thruster_vector_matrix[i].size()):
			thruster_vector_matrix[i][y] *= norminv[i]
	
	#Resume PolitePonderous
	min_control_vector.resize(thrusters.size())
	min_control_vector.fill(0)
	max_control_vector.resize(thrusters.size())
	max_control_vector.fill(1)
	initial_guess_control_vector.resize(thrusters.size())
	initial_guess_control_vector.fill(0)
	#12 = 6 Components (Tx,Ty,Tz,Fx,Fy,Fz) in 2 (+,-) directions
	#{Tx,Ty,Tz,Fx,Fy,Fz}
	var twelve_input_vectors := [
		[ 1, 0, 0, 0, 0, 0],
		[-1, 0, 0, 0, 0, 0],
		[ 0, 1, 0, 0, 0, 0],
		[ 0,-1, 0, 0, 0, 0],
		[ 0, 0, 1, 0, 0, 0],
		[ 0, 0,-1, 0, 0, 0],
		[ 0, 0, 0, 1, 0, 0],
		[ 0, 0, 0,-1, 0, 0],
		[ 0, 0, 0, 0, 1, 0],
		[ 0, 0, 0, 0,-1, 0],
		[ 0, 0, 0, 0, 0, 1],
		[ 0, 0, 0, 0, 0,-1],
	]
	
	twelve_control_vectors.resize(12)
	for i in range(twelve_control_vectors.size()):
		twelve_control_vectors[i] = []
		twelve_control_vectors[i].resize(thrusters.size())
	
	var i := 0
	for row in twelve_input_vectors:
		# Find minimum of function constrained
		twelve_control_vectors[i] = ["TODO", min_control_vector, max_control_vector, initial_guess_control_vector]
	print_debug(thruster_vector_matrix)
	print_debug(twelve_control_vectors)
