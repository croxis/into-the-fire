class_name Pilot
extends Node

# This getter setter chain is attempting to automagically assign the player the correct resource for
# network clients
@export var _faction_id: int:
	set(new_id):
		if faction and faction.faction_id == new_id:
			return
		_faction_id = new_id
		# A zero value is no faction.
		if _faction_id:
			faction = Faction.factions[new_id]
@export var faction: Faction:
	set(new_faction):
		if faction:
			faction.remove_member(self)
		faction = new_faction
		_faction_id = faction.faction_id
		Log.log(["Player gets new faction:", name, faction.resource_name], Log.MessageType.INFO)
# If this is the player, set the id to 1 or more
@export var _player_pilot_id: int:
	set(new_id):
		if new_id > -1:
			$LimboHSM.set_active(false)
		else:
			$LimboHSM.set_active(true)
		_player_pilot_id = new_id
@export var multiplayer_id: int
@export var pilot_id: int
@export var is_captain: bool = false
var active_orders: Array[OrderData] = []
var pending_orders: Array[OrderData] = []
var personality

@onready var hsm: LimboHSM = $LimboHSM # Later make behavior tree
@onready var idle_state: LimboState = $LimboHSM/IdleState


static var next_id := 0
static var pilot_scene: PackedScene = load("res://characters/character.tscn")

static func new_pilot(new_name: String) -> Pilot:
	var new_pilot_instance = pilot_scene.instantiate()
	new_pilot_instance.name = new_name
	new_pilot_instance.pilot_id = next_id
	next_id += 1
	return new_pilot_instance


func _ready():
	hsm = $LimboHSM
	hsm.initialize(self)
	#hsm.set_active(true)


func set_multiplayer_id(id):
	multiplayer_id = id
	# Give authority over the player input to the appropriate peer.
	$InputsSync.set_multiplayer_authority(id)


func _to_string() -> String:
	return name


func serialize() -> Dictionary:
	var payload:= {}
	# Personality
	# payload["personality"] = personality.resource_path
	
	# Blackboard
	# for key in blackboard.get_vars():
	#	payload["bb_" + key] = blackbaord.get_var(key)
	
	# HSM
	if hsm.get_active_state():
		payload["hsm_state"] = hsm.get_active_state().name
	
	payload["name"] = name
	payload["_faction_id"] = _faction_id
	payload["_player_pilot_id"] = _player_pilot_id
	payload["multiplayer_id"] = multiplayer_id
	payload["pilot_id"] = pilot_id
	payload["is_captain"] = is_captain
	payload["active_orders"] = active_orders
	payload["pending_orders"] = pending_orders
	
	return payload


func restore(payload: Dictionary):
	## Restores state when spawning a node from a save or crew transfer
	
	if payload.has("personality"):
		personality = load(payload["personality"])
	
	for key in payload.keys():
		if key.begins_with("bb_"):
			var bb_key = key.trim_prefix("bb_")
			#blackboard.set_var(bb_key, payload[key])
	
	name = payload["name"]
	_faction_id = payload["_faction_id"]
	_player_pilot_id = payload["_player_pilot_id"]
	multiplayer_id = payload["multiplayer_id"]
	pilot_id = payload["pilot_id"]
	is_captain = payload["is_captain"]
	active_orders = payload["active_orders"]
	pending_orders = payload["pending_orders"]
	
	#hsm.initialize(self)
	
