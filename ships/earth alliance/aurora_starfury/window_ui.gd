extends Control

var velocity: Vector3:
	set(v):
		$Velocity.current_velocity = -int(v.z)
		$X_Velocity.current_velocity = int(v.x)
		$Y_Velocity.current_velocity = int(v.y)

