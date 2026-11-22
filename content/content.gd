extends Node
## Autoload "Content": the game's ContentRegistry, filled from the manifests below
## at startup.
##
## Later, mod pcks will add their manifests here as they load (design doc:
## packaging). For now the Babylon 5 content is the only manifest.

const MANIFESTS: PackedStringArray = [
	"res://content/babylon5.cfg",
]

var registry := ContentRegistry.new()


func _enter_tree() -> void:
	for manifest in MANIFESTS:
		var count := registry.load_manifest(manifest)
		Log.log(["Content: ", count, " entries from ", manifest], Log.MessageType.INFO)


## Shorthands for the registry, so callers can write Content.instantiate(id).
func instantiate(id: StringName) -> Node:
	return registry.instantiate(id)


func path_of(id: StringName) -> String:
	return registry.path_of(id)


func has(id: StringName) -> bool:
	return registry.has(id)
