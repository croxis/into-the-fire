extends Node3D

@export var damage: float
@export var cooldown: float
# If a projectile weapon, what is the speed of the bolt
@export var speed: float
@export var bolt_resource: PackedScene

# In seconds
var cooldown_timer := 0.0


func can_fire() -> bool:
	if cooldown_timer > 0:
		return false
	return true

func _physics_process(dt: float) -> void:
	if (cooldown_timer > 0):
		cooldown_timer -= dt
	if (cooldown_timer < 0):
		cooldown_timer = 0.0


func fire(damage_mod):
	if ((multiplayer.multiplayer_peer == null or is_multiplayer_authority()) and can_fire()):
		cooldown_timer = cooldown
		var bolt_node: Bolt = bolt_resource.instantiate()
		bolt_node.speed = get_parent().get_parent().linear_velocity.length() + speed
		bolt_node.damage = damage
		get_node('../../../../bolts').add_child(bolt_node, true)
		bolt_node.global_transform.origin = global_transform.origin
		bolt_node.global_transform.basis = Basis(global_transform.basis)
		fire_sound.rpc()


@rpc("call_local")
func fire_sound():
	$AudioStreamPlayer3D.play()
