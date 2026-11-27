class_name Player
extends Node
## A player online in this world this session: replicated to clients. Their
## login (password hash) is in the world's PlayerRecords, never here.

@export var network_id: int
@export var player_id: int


func _to_string() -> String:
	return name + ": " + str(player_id) + " Net ID: " + str(network_id)
