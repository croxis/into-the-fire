extends Area3D
class_name Bolt

@export var speed: float
@export var damage: float

@export var KILL_TIMER := 10.0
@export var timer := 0.0

var hit_something = false


func _ready():
	connect("body_entered", Callable(self, "collided"))


func _physics_process(delta):
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
