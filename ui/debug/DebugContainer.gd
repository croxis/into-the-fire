class_name DebugContainer
extends MarginContainer


# The list of widget keywords associated with the DebugContainer.
var _widget_keywords = {}


# Called when the node enters the scene tree for the first time.
func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	_register_debug_widgets(self)
	Debug.register_debug_container(self)


# Adds a widget keyword to the registry.
func _add_widget_keyword(widget_keyword: String, widget_node: Node) -> void:
	var widget_node_name = widget_node.name if 'name' in widget_node else str(widget_node)

	if not _widget_keywords.has(widget_node_name):
		_widget_keywords[widget_node_name] = {}

	if not _widget_keywords[widget_node_name].has(widget_keyword):
		_widget_keywords[widget_node_name][widget_keyword] = widget_node
	else:
		var widget = _widget_keywords[widget_node_name][widget_keyword]
		var widget_name = widget.name if 'name' in widget else str(widget)
		push_error('DebugContainer._add_widget_keyword(): Widget keyword "' + widget_node_name + '.' + widget_keyword + '" already exists (' + widget_name + ')')
		return


# Go through all children of provided node and register any DebugWidgets found.
func _register_debug_widgets(node) -> void:
	for child in node.get_children():
		if child is DebugWidget:
			register_debug_widget(child)
		elif child.get_child_count() > 0:
			_register_debug_widgets(child)


# Register a single DebugWidget to the DebugContainer.
func register_debug_widget(widgetNode) -> void:
	for widget_keyword in widgetNode.get_widget_keywords():
		_add_widget_keyword(widget_keyword, widgetNode)


# Sends data to the widget with widget_name, triggering the callback for widget_keyword.
func update_widget(widget_path: String, data) -> void:
	var split_widget_path = widget_path.split('.')
	if split_widget_path.size() == 1 or split_widget_path.size() > 2:
		push_error('DebugContainer.update_widget(): widget_path formatted incorrectly. ("' + widget_path + '")')

	var widget_name = split_widget_path[0]
	var widget_keyword = split_widget_path[1]

	if _widget_keywords.has(widget_name) and _widget_keywords[widget_name].has(widget_keyword):
		_widget_keywords[widget_name][widget_keyword].handle_callback(widget_keyword, data)
	else:
		push_error('DebugContainer.update_widget(): Widget name and keyword "' + widget_name + '.' + widget_keyword  + '" not found (' + str(_widget_keywords) + ')')
