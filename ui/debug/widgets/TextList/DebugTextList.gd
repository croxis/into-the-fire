extends DebugWidget


const WIDGET_KEYWORDS = {
  'ADD_LABEL': 'add_label',
  'REMOVE_LABEL': 'remove_label'
}

@onready var listNode = $VBoxContainer

# Handles the widget's response when one of its keywords has been invoked.
func _callback(widget_keyword: String, data) -> void:
	match widget_keyword:
		WIDGET_KEYWORDS.ADD_LABEL:
			add_label(data.name, str(data.value))
		WIDGET_KEYWORDS.REMOVE_LABEL:
			remove_label(data.name)
		_:
			push_error('DebugTextList._callback(): widget_keyword not found. (' + str(widget_keyword) + '", "' + str(name) + '", "' + str(WIDGET_KEYWORDS) + '")')


# Returns the list of widget keywords.
func get_widget_keywords() -> Array:
		return [
			WIDGET_KEYWORDS.ADD_LABEL,
			WIDGET_KEYWORDS.REMOVE_LABEL
		]


# Returns a child node named child_name, or null if no child by that name is found.
func _find_child_by_name(child_name: String) -> Node:
	for child in listNode.get_children():
		if 'name' in child and child.name == child_name:
			return child
	return null


# Adds a label to the list, or updates label text if label_name matches an existing label's name.
func add_label(label_name: String, text_content: String) -> void:
	var existingLabel = _find_child_by_name(label_name)
	if existingLabel:
		existingLabel.text = text_content
		return

	var labelNode = Label.new()
	labelNode.name = label_name
	labelNode.text = text_content
	listNode.add_child(labelNode)


func remove_label(label_name) -> void:
	var labelNode = _find_child_by_name(label_name)
	if labelNode:
		listNode.remove_child(labelNode)
