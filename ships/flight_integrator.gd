class_name FlightIntegrator
extends RefCounted
## Ship motion maths, without nodes: thrust and torque go in, velocity and
## position come out.
##
## Ships use it instead of Jolt's own force integration (design doc: ship
## flight), so that a ship's motion can be computed without stepping its whole
## zone: own-ship prediction will replay a few ticks with it. It matches what
## Jolt does to a free body in one step, so a replay lands where Jolt would:
## - semi-implicit Euler: velocity first, then position with the new velocity;
## - the world-space inertia turns with the ship;
## - rotation is about the centre of mass;
## - speed and spin are clamped to Jolt's limits (project settings);
## - no gyroscopic term, no damping, no gravity (this project has neither).
## Collisions are not modelled; Jolt handles them and the next tick starts from
## whatever velocity they left.

const MAX_LINEAR_SETTING := "physics/jolt_physics_3d/limits/max_linear_velocity"
const MAX_ANGULAR_SETTING := "physics/jolt_physics_3d/limits/max_angular_velocity"


## Where a ship is and how it moves. Positions are the body's origin.
class FlightState:
	var transform := Transform3D.IDENTITY
	var linear_velocity := Vector3.ZERO  ## World space, of the centre of mass.
	var angular_velocity := Vector3.ZERO  ## World space, radians per second.

	func duplicate() -> FlightState:
		var s := FlightState.new()
		s.transform = transform
		s.linear_velocity = linear_velocity
		s.angular_velocity = angular_velocity
		return s


var inverse_mass := 0.0
## The inverse inertia tensor in the ship's own frame, about its centre of mass.
var inverse_inertia := Basis.from_scale(Vector3.ZERO)
## The centre of mass in the ship's own frame.
var center_of_mass_local := Vector3.ZERO
var max_linear_velocity := 500.0
var max_angular_velocity := deg_to_rad(2700.0)


## An integrator with the mass, inertia and centre of mass Jolt computed for a
## body (from its shapes), and Jolt's speed limits.
static func from_body(state: PhysicsDirectBodyState3D) -> FlightIntegrator:
	var f := FlightIntegrator.new()
	f.inverse_mass = state.inverse_mass
	f.center_of_mass_local = state.center_of_mass_local
	# Take the world-space tensor and turn it back into the ship's own frame
	# (Rᵀ * T * R). Not inverse_inertia with principal_inertia_axes: in Godot
	# 4.7.2 with Jolt those two don't pair up (the axes come out permuted).
	var r := state.transform.basis.orthonormalized()
	f.inverse_inertia = r.transposed() * state.inverse_inertia_tensor * r
	f.max_linear_velocity = ProjectSettings.get_setting(MAX_LINEAR_SETTING, 500.0)
	f.max_angular_velocity = ProjectSettings.get_setting(MAX_ANGULAR_SETTING, deg_to_rad(2700.0))
	return f


## One full step: new velocities, then the new transform. [param force] and
## [param torque] are world space; torque is about the centre of mass.
func step(state: FlightState, force: Vector3, torque: Vector3, dt: float) -> FlightState:
	var s := step_velocity(state, force, torque, dt)
	var basis := state.transform.basis
	var com := state.transform.origin + basis * center_of_mass_local + s.linear_velocity * dt
	var turn := s.angular_velocity * dt
	if turn.length() > 1e-12:
		basis = (Basis(turn.normalized(), turn.length()) * basis).orthonormalized()
	s.transform = Transform3D(basis, com - basis * center_of_mass_local)
	return s


## New velocities only. Ships use this: Jolt then moves them and handles contacts.
func step_velocity(state: FlightState, force: Vector3, torque: Vector3, dt: float) -> FlightState:
	var s := state.duplicate()
	s.linear_velocity = (state.linear_velocity + force * inverse_mass * dt).limit_length(max_linear_velocity)
	s.angular_velocity = (state.angular_velocity + inverse_inertia_world(state.transform.basis) * torque * dt) \
			.limit_length(max_angular_velocity)
	return s


## The inverse inertia tensor in world space for a ship turned to [param basis].
func inverse_inertia_world(basis: Basis) -> Basis:
	var r := basis.orthonormalized()
	return r * inverse_inertia * r.transposed()
