extends Area3D
class_name Bolt

var speed: float
var damage: float

const KILL_TIMER = 10
var timer := 0.0
var sync_timer := 0.0
var sync_position: Vector3
var sync_speed: float
var sync_orientation

var hit_something = false


func _ready():
	connect("body_entered", Callable(self, "collided"))
	if multiplayer.multiplayer_peer == null or is_multiplayer_authority():
		sync_position = global_transform.origin
		sync_orientation = global_transform.basis.get_rotation_quaternion()
		sync_timer = timer
		sync_speed = speed


func _physics_process(delta):
	# Snapshot current state
	# Server will set the values to sync to the clients
	# TODO: Really we only need to spawn this and not update every frame
	if multiplayer.multiplayer_peer == null or is_multiplayer_authority():
		sync_position = global_transform.origin
		sync_orientation = global_transform.basis.get_rotation_quaternion()
		sync_timer = timer
		sync_speed = speed
	else:
		global_transform.origin = sync_position
		global_transform.basis = Basis(sync_orientation)
		timer = sync_timer
		speed = sync_speed
	
	var forward_dir = global_transform.basis.z.normalized()
	global_translate(forward_dir * speed * delta)
	timer += delta
	var n = 1 + 0.2 * timer
	scale = Vector3(n, n, n)
	if timer >= KILL_TIMER:
		despawn()


func collided(body):
	if not is_multiplayer_authority():
		# Explode only on authority.
		return
	if hit_something == false:
		if body.has_method("bullet_hit"):
			body.bullet_hit(damage/scale.x, global_transform)

	hit_something = true
	despawn()


func despawn():
	if is_multiplayer_authority():
		queue_free()
