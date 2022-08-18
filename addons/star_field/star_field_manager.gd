@tool
extends Node

signal star_debug(message)

var star_db : Node
var camera : Camera3D
var star_render

const AU_IN_PARSEC := 0.000004848
const LY_IN_PARSEC := 0.3066
const PARSEC_IN_AU := 206265
const PARSEC_IN_LY := 3.262


@export var mag_ref : float:
	get:
		return mag_ref
	set(mag):
		# What is the approx screen size of the sun in px at 1 unit distance
		mag_ref = mag
		if is_inside_tree():
			star_render.mag_ref = mag

@export var mag_limit : float:
	get:
		return mag_limit
	set(new_limit):
		if not is_inside_tree():
			await ready
		mag_limit = new_limit
		star_render.mag_limit = mag_limit

@export var star_labels_visible : bool = true:
	get:
		return star_labels_visible
	set(visible):
		star_labels_visible = visible
		if not is_inside_tree():
			await ready
		star_render.star_labels_visible = visible


@export var celestial_coords: Vector3

@export var camera_path : NodePath:
	get:
		return camera_path
	set(cam_path):
		if not is_inside_tree():
			await ready
		camera_path = cam_path
		camera = get_node(cam_path)


func _init():
	star_db = preload("res://addons/star_field/StarDB.tscn").instantiate()
	star_render = preload("res://addons/star_field/StarRender.tscn").instantiate()
	star_db.connect("star_db_debug", Callable(self, "debug"))
	star_render.connect("star_render_debug", Callable(self, "debug"))


# Called when the node enters the scene tree for the first time.
func _ready():
	var start = Time.get_ticks_msec()
	emit_signal("star_debug", "Initalizing Star Field")
	
	# Create Database
	add_child(star_db)
	emit_signal("star_debug", "Initalized Star DB")

	# Construct Stars	
	add_child(star_render)
	emit_signal("star_debug", "Loaded Star Render")
	
	emit_signal("star_debug", "Star Field initalized in " + str(Time.get_ticks_msec() - start) + " ms")


func get_star_hip(hip: String):
	# Return null if not in db
	return star_db.get_star_hip(hip)


func get_star_proper(name: String):
	# Return null if not in db
	return star_db.get_star_proper(name)


func _process(delta):
	if camera:
		star_render.position = camera.position - celestial_coords


func debug(msg):
	emit_signal("star_debug", msg)
