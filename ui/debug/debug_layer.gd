extends CanvasLayer

signal debug_container_registered

# Boolean that governs whether the debug interface should be visible.
var show_debug_interface = false

# The debug containers registered to the DebugLayer.
var _debug_containers = {}

# The currently active debug container.
var _debugContainer: Node

@onready var _ui_container = $DebugUIContainer

# Nodes implementing the debug container tab switching interface.
@onready var debugTabs: TabBar = $DebugUIContainer/VBoxContainer/DebugTabBar
@onready var debugContentContainer = $DebugUIContainer/VBoxContainer/DebugContentContainer


func _ready() -> void:
	_set_ui_container_visibility(show_debug_interface)
	debugTabs.connect('tab_changed', Callable(self, '_on_Tab_changed'))


func _set_ui_container_visibility(boolean) -> void:
	_ui_container.visible = boolean


func _input(_event) -> void:
	if Input.is_action_just_pressed('ui_debug'):
		show_debug_interface = !show_debug_interface
		print("Toggle Debug Interface: ", str(show_debug_interface))
		_set_ui_container_visibility(show_debug_interface)
		_debugContainer.show()


func register_debug_container(containerNode) -> void:
	var container_name = containerNode.name
	if _debug_containers.has(container_name):
		push_error('DebugLayer.register_debug_container: Debug already has registered DebugContainer with name "' + container_name + '".')
		return

	# Reparent the container node to the DebugLayer.
	containerNode.get_parent().call_deferred('remove_child', containerNode)
	debugContentContainer.call_deferred('add_child', containerNode)
	
	_debug_containers[container_name] = containerNode
	if _debug_containers.size() == 1:
		_debugContainer = containerNode
	
	debugTabs.add_tab(container_name)

	# Hide this container node so we don't show debug info by default.
	containerNode.hide()
	emit_signal('debug_container_registered', containerNode)


# Sends data to the debug container specified in widget_path.
# API: container_name:widget_name.widget_keyword
func update_widget(widget_path: String, data = null) -> void:
	var split_keyword = widget_path.split(':')
	if split_keyword.size() == 1:
		push_error('DebugLayer.update_widget(): No container name was specified. (' + widget_path + ', ' + str(data) + ')')
		return

	var container_name = split_keyword[0]
	if not _debug_containers.has(container_name):
		push_error('DebugLayer.update_widget(): Container with name "' + container_name + '" is not registered.')
		return

	var containerNode = _debug_containers[container_name]
	widget_path = split_keyword[1]
	containerNode.update_widget(widget_path, data)


func _on_Tab_changed(tab_index) -> void:
	var tab_name = debugTabs.get_tab_title(tab_index)
	print(tab_index, " ", tab_name, " ", _debug_containers)
	var containerNode = _debug_containers[tab_name]
	_debugContainer.hide()
	_debugContainer = containerNode
	_debugContainer.show()
