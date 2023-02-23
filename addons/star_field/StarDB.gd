@tool
extends Node

signal star_db_debug(message)

var data : Array = []
# Lookups to speed up search
var hip_to_index := {}
var proper_to_index := {}

func _ready():
	var start = Time.get_ticks_msec()
	var stars = parse("res://addons/star_field/databases/hygdata_v3_reduced.csv")
	emit_signal("star_db_debug", "CSV parsed in " + str(Time.get_ticks_msec() - start) + " ms")
	start = Time.get_ticks_msec()
	for i in stars.size():
		if str(i) in stars:
			data.append(stars[str(i)])
			if stars[str(i)]['hip']:
				hip_to_index[stars[str(i)]['hip']] = stars[str(i)]['id'].to_int()
			if stars[str(i)]['proper']:
				proper_to_index[stars[str(i)]['proper']] = stars[str(i)]['id'].to_int()
	emit_signal("star_db_debug", "Database built in " + str(Time.get_ticks_msec() - start) + " ms")


func get_star_hip(hip: String):
	# Return data for star by Hipparcos catalog number
	# Return null if not in db
	if hip in hip_to_index:
		return data[hip_to_index[hip]]

func get_star_proper(name: String):
	# Return data for star by proper name
	# Return null if not in db
	if name in proper_to_index:
		return data[proper_to_index[name]]
	
# From godot-csv-to-dictionary
func parse(
	file_path: String,
	id_column: String = "id",
	delimiter: String = ","
) -> Dictionary:
	var file = FileAccess.open(file_path, FileAccess.READ)
	#var content = file.get_as_text()

	var dict_data: Dictionary = {}

	var line_index: int = -1
	var column_headers: PackedStringArray
	while not file.eof_reached():
		line_index += 1
		var line: PackedStringArray = file.get_csv_line(delimiter)

		if line_index == 0:
			column_headers = line
		else:
			var entry: Dictionary = {}
			if line.size() <= 1:
				break
			for column_index in column_headers.size():
				var value = line[column_index]
				if value.is_valid_int():
					pass
				#	print(str(column_headers[column_index]) + " INT: ", str(value))
					#value = value.to_int()
				#	print(value)
				elif value.is_valid_float():
					pass
					#value = value.to_float()
				# Detect bools.
				#elif value is String:
				if value is String:
					var value_lower: String = value.to_lower()
					if value_lower == "true":
						value = true
					elif value_lower == "false":
						value = false

				entry[column_headers[column_index]] = value
				if column_headers[column_index] == id_column:
					dict_data[entry[id_column]] = entry

	file = null

	return dict_data
