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


func fire(damage):
	if can_fire():
		$AudioStreamPlayer3D.play()
	if ((multiplayer.multiplayer_peer == null or is_multiplayer_authority()) and can_fire()):
		# Path to system or reference frame with Bolt Spawner as a child
		#get_node('../../../../BoltSpawner').spawn({"origin": global_transform.origin,
		#										"basis": global_transform.basis,
		#										"speed": get_parent().get_parent().linear_velocity.length() + speed,
		#										"damage": damage,
		#										"bolt_resource": bolt_resource})
		cooldown_timer = cooldown		
		var bolt_node: Bolt = bolt_resource.instantiate()
		bolt_node.speed = get_parent().get_parent().linear_velocity.length() + speed
		bolt_node.damage = damage
		get_node('../../../../Bolts').add_child(bolt_node, true)
		bolt_node.global_transform.origin = global_transform.origin
		bolt_node.global_transform.basis = Basis(global_transform.basis)
		cooldown_timer = cooldown
