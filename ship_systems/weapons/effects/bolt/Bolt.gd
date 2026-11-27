extends Node3D
class_name Bolt
## How a Shot looks: drawn each frame where the shot is at the moment this
## machine shows (Galaxy.shown_tick), growing as it weakens. Nothing else: the
## shot itself is data in its system's ShotField, and hits are the server's.

var shot: Shot
## The bolt mesh's own radius: scaled so the bolt is drawn its shot's size.
var _mesh_radius := 0.0
## Its gun's sound has played: once, the first frame the bolt is drawn at or
## after its fire tick. At once for this machine's own and the host's shots;
## for other ships' shots the fire event arrives before this machine draws the
## moment they fired, and the sound waits for the bolt.
var _sounded := false


func _ready() -> void:
	var mesh := get_node_or_null(^"MeshInstance3D") as MeshInstance3D
	if mesh and mesh.mesh is CapsuleMesh:
		_mesh_radius = (mesh.mesh as CapsuleMesh).radius


## The tick this machine draws the shot at: its own for a shot it predicted,
## else the moment it shows other ships (Galaxy.shown_tick).
func drawn_tick() -> float:
	if shot and shot.predicted:
		return NetworkTime.tick + NetworkTime.tick_factor
	return Galaxy.shown_tick(self)


func _process(_delta: float) -> void:
	if shot == null:
		return
	var at := drawn_tick()
	if not _sounded and at >= shot.fire_tick:
		_sounded = true
		var gun := ShotField._gun_of(shot)
		if gun:
			gun.play_fire_sound()
	var grow := shot.size_at(at)
	if shot.radius > 0.0 and _mesh_radius > 0.0:
		grow = shot.radius_at(at) / _mesh_radius  # Drawn the size it hits.
	var along := shot.velocity.normalized() if shot.velocity else Vector3.FORWARD
	var up := Vector3.UP if absf(along.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	# The capsule lies along the root's z (its mesh is turned): point that along the flight.
	global_transform = Transform3D(Basis.looking_at(along, up).scaled(Vector3.ONE * grow),
			shot.position_at(at))
