class_name Zones
extends Node
## A world's zones: which exist and who is in each. Star systems for now
## (System, one World3D each); hyperspace and deep-space zones join them later.
## Zones arrive from setup on the server and from the spawner on clients (a
## MultiplayerSpawner spawns into this node); each is handed to the ZoneStepper
## as it enters, which lets it go again when it leaves the tree.

## Emitted when [param system] has entered and is being stepped.
signal zone_added(system: System)

## Steps each zone's physics. Set by Galaxy before any zone arrives.
var stepper: ZoneStepper


func _ready() -> void:
	child_entered_tree.connect(_on_child_entered)


func _on_child_entered(node: Node) -> void:
	if node is System:
		if stepper:
			stepper.add_zone(node)
		zone_added.emit(node)


## Server: adds a system to this world (a client gets its systems from the spawner).
func add_system(system: System) -> void:
	add_child(system)


## This world's star systems.
func systems() -> Array[System]:
	var out: Array[System] = []
	for node in get_children():
		if node is System:
			out.append(node)
	return out


## The system called [param system_name], or null. Names may come from clients,
## so only a system that is one of the zones counts: a path such as "../.."
## would also resolve to a node.
func get_system(system_name: String) -> System:
	if system_name.is_empty() or system_name.contains("/"):
		return null
	var node := get_node_or_null(NodePath(system_name))
	if node is System and node.get_parent() == self:
		return node
	return null


## The loaded system for a system content ID, or null.
func system_for_content(content_id: StringName) -> System:
	var path := Content.path_of(content_id)
	if path.begins_with("uid://"):
		path = ResourceUID.uid_to_path(path)
	for system in systems():
		if system.scene_file_path == path:
			return system
	return null


## The living character of player [param player_id] in any zone, or null.
func player_character(player_id: int) -> Character:
	return SpawnService.find_player_character(self, player_id)


## Every player character played from [param peer], in any zone (a character
## stays in the world while its player is away).
func characters_of_peer(peer: int) -> Array[Character]:
	var out: Array[Character] = []
	for node in find_children("*", "", true, false):
		var c := node as Character
		if c and c.is_player() and c.multiplayer_id == peer:
			out.append(c)
	return out
