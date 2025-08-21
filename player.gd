class_name Player
extends Node

@export var network_id: int
@export var player_id: int
var password: String:
	set(pswrd):
		password = pswrd.sha256_text()
var faction := Faction


func password_match(check: String) -> bool:
	return check.sha256_text() == password

func _to_string() -> String:
	return name + ": " + str(player_id) + " Net ID: " + str(network_id)
