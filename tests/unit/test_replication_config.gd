extends GutTest
## Every property a MultiplayerSynchronizer replicates must exist on its node.
##
## If one doesn't, the server can't build the spawn state ("Unable to retrieve
## spawn state") and clients silently never receive the node. Nothing else
## fails, so this test catches properties that were moved or renamed.

const ENGINE_SCENES := [
	"res://ships/Ship.tscn",
	"res://characters/character.tscn",
	"res://ship_systems/workstations/helm.tscn",
]


func _scenes() -> Array[String]:
	var paths: Array[String] = []
	paths.assign(ENGINE_SCENES)
	var registry := ContentRegistry.new()
	registry.load_manifest("res://content/babylon5.cfg")
	for id in registry.ids(&"ship"):
		paths.append(registry.path_of(id))
	return paths


func _synchronizers(node: Node, found: Array[MultiplayerSynchronizer]) -> void:
	if node is MultiplayerSynchronizer:
		found.append(node)
	for child in node.get_children():
		_synchronizers(child, found)


func test_synced_properties_exist() -> void:
	for scene_path in _scenes():
		if scene_path.begins_with("uid://"):
			scene_path = ResourceUID.uid_to_path(scene_path)
		var root: Node = autofree(load(scene_path).instantiate())
		var syncs: Array[MultiplayerSynchronizer] = []
		_synchronizers(root, syncs)
		for sync in syncs:
			if sync.replication_config == null:
				continue
			var sync_root := sync.get_node_or_null(sync.root_path)
			assert_not_null(sync_root, "%s: %s root_path resolves" % [scene_path, sync.name])
			if sync_root == null:
				continue
			for path: NodePath in sync.replication_config.get_properties():
				var target := sync_root.get_node_or_null(NodePath(path.get_concatenated_names()))
				var property := StringName(path.get_subname(0))
				assert_true(target != null and property in target,
						"%s: %s replicates %s, which exists" % [scene_path, sync.name, path])
