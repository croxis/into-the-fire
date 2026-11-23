@tool
extends MultiMeshInstance3D
## Draws a StarCatalog as points. Brightness and cut-off are per-node shader
## parameters, so the star buffer never changes and every star field showing
## the same catalogue shares one MultiMesh.

signal star_render_debug(message)

## Apparent magnitude drawn at intensity 1; brighter stars get bigger points.
@export var mag_ref := 4.0:
	set(value):
		mag_ref = value
		set_instance_shader_parameter(&"mag_ref", value)

## Stars fainter than this apparent magnitude are not drawn.
@export var mag_limit := 8.0:
	set(value):
		mag_limit = value
		set_instance_shader_parameter(&"mag_limit", value)

## Names of the catalogue's named stars. Made the first time they are shown.
@export var star_labels_visible := true:
	set(value):
		star_labels_visible = value
		_update_labels()

var catalog: StarCatalog

var _star_mesh: Mesh
var _labels_for: StarCatalog


func _ready() -> void:
	_update_labels()


func apply_catalog(new_catalog: StarCatalog) -> void:
	if _star_mesh == null and multimesh:
		_star_mesh = multimesh.mesh  # The point mesh and star material from the scene.
	catalog = new_catalog
	multimesh = catalog.get_multimesh(_star_mesh)
	_update_labels()
	star_render_debug.emit("Showing %d stars" % catalog.get_star_count())


func _update_labels() -> void:
	var labels := get_node_or_null(^"star_labels") as Node3D
	if labels == null:
		return  # Not built yet; _ready calls again.
	labels.visible = star_labels_visible
	if not star_labels_visible or catalog == null or _labels_for == catalog:
		return
	for old in labels.get_children():
		labels.remove_child(old)
		old.queue_free()
	for proper_name: String in catalog.names:
		var label := Label3D.new()
		label.text = proper_name
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = catalog.get_position(catalog.names[proper_name]) + Vector3(0, 0.11, 0)
		labels.add_child(label)
	_labels_for = catalog
