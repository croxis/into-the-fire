class_name ZoneStepper
extends Node
## Steps each zone's physics space itself, instead of leaving it to the engine.
##
## Every zone (a SubViewport with its own World3D) has its own physics space.
## The engine steps every active space once per physics tick. A zone added here
## is made inactive, and this node steps it instead, using the physics stepping
## patch in the custom engine (PhysicsServer3D.space_step / space_flush_queries,
## godot PR 76462). That lets the game decide per zone: step it, pause it, and
## later step it at a lower rate or re-simulate it for netcode.
##
## Order within a tick matches the engine's: every node's _physics_process runs
## first (this node has the highest priority, so it goes last), then each zone
## is stepped, then its results are flushed to the nodes (body transforms,
## _integrate_forces, area signals), ready for the next tick.
##
## Not here yet: a reduced step rate. Nodes push forces every tick, so a zone
## stepped every other tick would need its nodes to tick at that rate too.

enum Mode {
	FULL,  ## Stepped every physics tick.
	PAUSED,  ## Not stepped. The zone's nodes are disabled too, or thrusters would
			## keep adding force and release it all in one kick on resume.
}

var _modes: Dictionary[SubViewport, Mode] = {}


func _init() -> void:
	name = "ZoneStepper"
	process_physics_priority = 1000


## Takes over stepping [param zone]'s physics. The zone must have its own world.
func add_zone(zone: SubViewport, mode := Mode.FULL) -> void:
	if _modes.has(zone):
		set_mode(zone, mode)
		return
	PhysicsServer3D.space_set_active(_space(zone), false)
	_modes[zone] = mode
	_apply_mode(zone, mode)
	zone.tree_exiting.connect(_forget.bind(zone), CONNECT_ONE_SHOT)


## Hands [param zone] back to the engine.
func remove_zone(zone: SubViewport) -> void:
	if not _modes.has(zone):
		return
	zone.tree_exiting.disconnect(_forget.bind(zone))
	_modes.erase(zone)
	zone.process_mode = Node.PROCESS_MODE_INHERIT
	PhysicsServer3D.space_set_active(_space(zone), true)


func has_zone(zone: SubViewport) -> bool:
	return _modes.has(zone)


func get_mode(zone: SubViewport) -> Mode:
	return _modes.get(zone, Mode.FULL)


func set_mode(zone: SubViewport, mode: Mode) -> void:
	if not _modes.has(zone):
		return
	_modes[zone] = mode
	_apply_mode(zone, mode)


func _physics_process(delta: float) -> void:
	for zone in _modes:
		if _modes[zone] == Mode.FULL:
			var space := _space(zone)
			PhysicsServer3D.space_step(space, delta)
			PhysicsServer3D.space_flush_queries(space)


func _apply_mode(zone: SubViewport, mode: Mode) -> void:
	zone.process_mode = Node.PROCESS_MODE_DISABLED if mode == Mode.PAUSED \
			else Node.PROCESS_MODE_INHERIT


## The zone is leaving the tree. Its world (and space) may be freed with it; if
## not, the engine steps it again, so a zone added back elsewhere isn't frozen.
func _forget(zone: SubViewport) -> void:
	_modes.erase(zone)
	zone.process_mode = Node.PROCESS_MODE_INHERIT
	PhysicsServer3D.space_set_active(_space(zone), true)


static func _space(zone: SubViewport) -> RID:
	return zone.find_world_3d().space
