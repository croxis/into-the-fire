class_name Player
extends Node

var network_id: int
var player_id: int
var password: String:
	set(pswrd):
		password = pswrd.sha256_text()
var faction := Faction


func password_match(check: String) -> bool:
	return check.sha256_text() == password

