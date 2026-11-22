class_name WorldIds
extends RefCounted
## Hands out the IDs of things in one world. Galaxy owns one ([member Galaxy.ids]).
##
## IDs start at 1 so that 0 can mean "none", as with factions. They are never
## reused, and they end up in saves, so they must come from the world and not
## from static variables (which would keep counting across games and tests).

var _next_ship := 1
var _next_pilot := 1


func next_ship() -> int:
	_next_ship += 1
	return _next_ship - 1


func next_pilot() -> int:
	_next_pilot += 1
	return _next_pilot - 1
