class_name Faction
extends Node

@export var relations := {} # These are $Node: +-10 scale
@export var accept_players := false
@export var accept_children := false
@export var is_wing := false
@export var faction_id: int
var member_ids: Array[int] = []
var leader_id: int
var active := true


func get_wings() -> Array[Faction]:
	var factions: Array[Faction] = []
	for child in get_children():
		if child.typeof(Faction):
			if child.is_wing:
				factions.append(child)
	return factions


func add_member(pilot: Pilot) -> void:
	#TODO: Check and remove if pilot is in another faction, remove from faction and leader
	if pilot._faction_id:
		print_debug("IMPLEMENT THIS TODO")
	pilot._faction_id = faction_id
	member_ids.append(pilot.pilot_id)
