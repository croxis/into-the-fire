extends Node
class_name PID
	
@export var kp : float = 0.0
@export var ki = 0.0
@export var kd = 0.0
var prev = 0.0
var inte_d = 0.0
var minimum_clamp = -1
var maximum_clamp = 1
var prop_d
var diff_d
	

func _set_range(minimum,maximum):
	self.minimum_clamp = minimum
	self.maximum_clamp = maximum

func _reset_integral():
	self.inte_d = 0.0

func sumval():
	return clamp(self.kp*prop_d + self.ki*inte_d + self.kd*diff_d,minimum_clamp,maximum_clamp);

func _update(err, dt):
	prop_d = err*self.kp 
	diff_d = (err - self.prev)/dt
	inte_d = self.inte_d + err*dt
	self.prev = err
	if(inte_d > self.maximum_clamp or inte_d < self.minimum_clamp):
		self._reset_integral()
	return clamp(self.kp*prop_d + self.ki*inte_d + self.kd*diff_d, minimum_clamp, maximum_clamp);
	#return clamp(prop_d + self.ki*inte_d + self.kd*diff_d,minimum_clamp,maximum_clamp);
