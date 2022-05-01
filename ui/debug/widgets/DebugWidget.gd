# Base class for nodes that are meant to be used with the DebugLayer system.
class_name DebugWidget
extends MarginContainer

# Controls if the widget should allow invocation without data.
@export var allow_null_data: bool = false


# Abstract method which must be overridden by the inheriting debug widget.
# Returns the list of widget keywords. Responses to multiple keywords should be provided in _callback.
func get_widget_keywords() -> Array:
	push_error("DebugWidget.get_widget_keywords(): No widget keywords have been defined. Did you override the base DebugWidget.get_widget_keywords() method?")
	return []



# Abstract method which must be overridden by the inheriting debug widget.
# Handles the widget's response when one of its keywords has been invoked.
func _callback(widget_keyword, data) -> void:
	push_error('DebugWidget._callback(): No callback has been defined. (' + widget_keyword + ', ' + data + ')')


# Called by DebugContainer when one of its widget keywords has been invoked.
func handle_callback(widget_keyword: String, data = null) -> void:
	if data == null and not allow_null_data:
		push_error('DebugWidget.handle_callback(): data is null. (' + widget_keyword + ')')
		return
  
	_callback(widget_keyword, data)
