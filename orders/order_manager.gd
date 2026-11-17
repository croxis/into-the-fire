extends Node
class_name OrderManager

var _order_counter = 0
var _orders: Dictionary = {}  # order_id -> OrderData


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_create_order():
	pass


func create_order() -> OrderData:
	var order:= OrderData.new()
	
	_order_counter += 1
	return order
