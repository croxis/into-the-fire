@tool
extends Node
## Background stars of the real sky (or a modded one), seen from
## [member celestial_coords]. Set [member anchor_star] to put the viewer near a
## named star; the position is filled in once the catalogue has loaded.
##
## Stars come from the [code]StarCatalogs[/code] autoload (StarCatalogService),
## loaded in the background. Where there is no autoload, such as in the editor,
## the star field loads its own.

signal star_debug(message)
## Emitted each time a catalogue is shown: after the first load, and again when
## the sources change.
signal catalog_applied(catalog: StarCatalog)

const StarRenderScene := preload("res://addons/star_field/StarRender.tscn")

const AU_IN_PARSEC := 0.000004848
const LY_IN_PARSEC := 0.3066
const PARSEC_IN_AU := 206265
const PARSEC_IN_LY := 3.262

@export var use_active_camera := false

## Apparent magnitude drawn at intensity 1; brighter stars get bigger points.
@export var mag_ref: float:
	set(value):
		mag_ref = value
		star_render.mag_ref = value

## Stars fainter than this apparent magnitude are not drawn.
@export var mag_limit: float:
	set(value):
		mag_limit = value
		star_render.mag_limit = value

@export var star_labels_visible: bool = true:
	set(value):
		star_labels_visible = value
		star_render.star_labels_visible = value

## Where the viewer is among the stars, in parsecs. Overwritten from
## [member anchor_star] when that is set.
@export var celestial_coords: Vector3

@export var camera_path: NodePath

## Proper name of the star the viewer is near, e.g. "Sol". Empty to use
## [member celestial_coords] as set.
@export var anchor_star := "":
	set(value):
		anchor_star = value
		_place_on_anchor()

## The viewer's offset from [member anchor_star], in AU.
@export var anchor_offset_au := Vector3.ZERO:
	set(value):
		anchor_offset_au = value
		_place_on_anchor()

## Where the stars come from. Defaults to the StarCatalogs autoload; set it
## before the node enters the tree to use another one (tests do).
var catalog_service: StarCatalogService
## The catalogue shown, or null until it has loaded.
var catalog: StarCatalog
var star_render: MultiMeshInstance3D
var camera: Camera3D


func _init() -> void:
	star_render = StarRenderScene.instantiate()
	star_render.star_render_debug.connect(debug)


func _ready() -> void:
	add_child(star_render)
	if not camera_path.is_empty():
		camera = get_node(camera_path)
	if catalog_service == null:
		catalog_service = _find_service()
	catalog_service.catalog_ready.connect(_apply)
	if catalog_service.catalog:
		_apply(catalog_service.catalog)
	else:
		catalog_service.request()


## Position of the named star in parsecs, or null (also before the catalogue
## has loaded; see [signal catalog_applied]).
func get_star_position(proper_name: String) -> Variant:
	return catalog.get_star_position(proper_name) if catalog else null


func _process(_delta: float) -> void:
	if use_active_camera:
		var active_camera := get_viewport().get_camera_3d()
		if active_camera:
			star_render.position = active_camera.global_position - celestial_coords
	elif camera:
		star_render.position = camera.global_position - celestial_coords


func debug(msg) -> void:
	star_debug.emit(msg)


func _find_service() -> StarCatalogService:
	var service := get_node_or_null(^"/root/StarCatalogs") as StarCatalogService
	if service == null:
		service = StarCatalogService.new()
		add_child(service, false, INTERNAL_MODE_BACK)
	return service


func _apply(new_catalog: StarCatalog) -> void:
	catalog = new_catalog
	star_render.apply_catalog(catalog)
	_place_on_anchor()
	catalog_applied.emit(catalog)


func _place_on_anchor() -> void:
	if anchor_star.is_empty() or catalog == null:
		return
	var position: Variant = catalog.get_star_position(anchor_star)
	if position == null:
		push_warning("Star field: no star named \"%s\" in the catalogue" % anchor_star)
		return
	celestial_coords = position + anchor_offset_au * AU_IN_PARSEC
