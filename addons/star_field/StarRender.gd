@tool
extends MultiMeshInstance3D

signal star_render_debug(message)

@export var mag_ref: float:
	get:
		return mag_ref
	set(mag):
		mag_ref = mag
		if is_inside_tree():
			generate_stars()

@export var mag_limit: float:
	get:
		return mag_limit
	set(new_limit):
		mag_limit = new_limit
		if is_inside_tree():
			generate_stars()

@export var star_labels_visible: bool:
	# Errors are thrown if we try and get @star_labels directly
	get:
		return star_labels_visible
	set(visible):
		if not is_inside_tree():
			await ready
		star_labels_visible = visible
		$star_labels.visible = visible

var data

func get_star_data():
	return get_node("../StarDB").data


func _init():
	#multimesh.instance_count = 1
	return


# Called when the node enters the scene tree for the first time.
func _ready():
	var start = Time.get_ticks_msec()
	update_data()
	for i in multimesh.instance_count:
		if data[i]["proper"]:
			var label = Label3D.new()
			label.text = data[i]["proper"]
			label.billboard = 1
			label.transform = Transform3D(Basis(), Vector3(float(data[i]["x"].to_float()), float(data[i]["y"].to_float()) + 0.11, float(data[i]["z"].to_float())))
			$star_labels.add_child(label)
	star_labels_visible = $star_labels.visible
	emit_signal("star_render_debug", "Set stars Time elapsed is " + str(Time.get_ticks_msec() - start) + " ms")


func update_data():
	data = get_star_data()
	multimesh.instance_count = data.size()


func generate_stars():
	update_data()
	multimesh.instance_count = data.size()
	emit_signal("star_render_debug", "Generating " + str(multimesh.instance_count) + " Stars")
	for i in multimesh.instance_count:
		multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(float(data[i]["x"].to_float()), float(data[i]["y"].to_float()), float(data[i]["z"].to_float()))))
		# Convert color index to temperature
		# https://en.wikipedia.org/wiki/Color_index#cite_note-PyAstronomy-6
		var color_index = float(data[i]["ci"].to_float())
		var temperature = 4600 * ((1 / (0.92 * color_index + 1.7)) + (1 / (0.92 * color_index + 0.62)))
		
		# Temperature to RGB
		# https://tannerhelland.com/2012/09/18/convert-temperature-rgb-algorithm-code.html
		# and https://gist.github.com/petrklus/b1f427accdf7438606a6
		
		# TODO try vs the gaia sky algorithem
		# http://stackoverflow.com/questions/21977786/star-b-v-color-index-to-apparent-rgb-color
		# https://gitlab.com/langurmonkey/gaiasky/-/blob/master/core/src/gaiasky/util/color/ColorUtils.java#L394
		
		if temperature < 1000:
			temperature = 1000
		elif temperature > 40000:
			temperature = 40000
		
		var tmp_internal = temperature / 100.0
		
		var red = 0.0
		var green = 0.0
		var blue = 0.0
		
		# red 
		if tmp_internal <= 66:
			red = 255
		else:
			var tmp_red = 329.698727446 * pow(tmp_internal - 60, -0.1332047592)
			if tmp_red < 0:
				red = 0
			elif tmp_red > 255:
				red = 255
			else:
				red = tmp_red
		
		# green
		if tmp_internal <=66:
			var tmp_green = 99.4708025861 * log(tmp_internal) - 161.1195681661
			if tmp_green < 0:
				green = 0
			elif tmp_green > 255:
				green = 255
			else:
				green = tmp_green
		else:
			var tmp_green = 288.1221695283 * pow(tmp_internal - 60, -0.0755148492)
			if tmp_green < 0:
				green = 0
			elif tmp_green > 255:
				green = 255
			else:
				green = tmp_green
		
		# blue
		if tmp_internal >=66:
			blue = 255
		elif tmp_internal <= 19:
			blue = 0
		else:
			var tmp_blue = 138.5177312231 * log(tmp_internal - 10) - 305.0447927307
			if tmp_blue < 0:
				blue = 0
			elif tmp_blue > 255:
				blue = 255
			else:
				blue = tmp_blue
		multimesh.set_instance_color(i, Color(red/255.0 , green/255.0, blue/255.0))
		# X is abs magnitude, y relative
		multimesh.set_instance_custom_data(i, Color(data[i]["absmag"].to_float(), float(data[i]["lum"].to_float()), mag_ref, mag_limit))

