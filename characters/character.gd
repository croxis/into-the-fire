class_name Character
extends Node

# This getter setter chain is attempting to automagically assign the player the correct resource for
# network clients
@export var faction_id: int:
	set(new_id):
		if faction and faction.faction_id == new_id:
			return
		faction_id = new_id
		# A zero value is no faction.
		Log.log(["Player gets new faction ID:", name, faction.resource_name, faction.faction_id, faction_id], Log.MessageType.INFO)
@export var faction: Faction:
	set(new_faction):
		assert(false, "BOO! DO NOT SET FACTIONS DIRECTLY")
	get:
		return Faction.factions[faction_id]
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
var active_orders: Array[OrderData] = []
var pending_orders: Array[OrderData] = []
var personality
var current_console: Console

@onready var hsm: LimboHSM = $LimboHSM # Later make behavior tree
@onready var idle_state: LimboState = $LimboHSM/IdleState

@onready var inputs: InputSynchronizer:
	get:
		return get_node("InputsSync")

static var next_id := 0
static var pilot_scene: PackedScene = load("res://characters/character.tscn")

static func new_pilot(new_name: String) -> Character:
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


func _physics_process(_dt: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.get_unique_id() == multiplayer_id:
		# The client which this player represent will update the controls state, and notify it to everyone.
		inputs.update()
	if current_console:
		var rotation_throttle = inputs.rotation_throttle  # May be needed for turrets
		var throttle = inputs.throttle  # May be needed for turrent zoom or engineering
		if current_console.has_capability("Helm"):
			var helm: HelmCapability = current_console.get_node("Helm") as HelmCapability
			if inputs.autobreak_toggle:
				helm.toggle_autobreak()
			if inputs.autospin_toggle:
				helm.toggle_autospin()
			helm.input_rotation_throttle = inputs.rotation_throttle
			helm.throttle = inputs.throttle
			if inputs.debug_all_stop:
				helm._debug_all_stop()
		if current_console.has_capability("Weapons"):
			var weapons: WeaponsCapability = current_console.get_node("Helm") as WeaponsCapability
		if Input.is_action_just_released("camera_change") and _player_pilot_id == LocalGameManager.player_id:
			print_debug(current_console.name, " by ", name)
			current_console.change_camera()


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
	payload["faction_id"] = faction_id
	payload["_player_pilot_id"] = _player_pilot_id
	payload["multiplayer_id"] = multiplayer_id
	payload["pilot_id"] = pilot_id
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
	faction_id = payload["faction_id"]
	_player_pilot_id = payload["_player_pilot_id"]
	multiplayer_id = payload["multiplayer_id"]
	pilot_id = payload["pilot_id"]
	active_orders = payload["active_orders"]
	pending_orders = payload["pending_orders"]
	
	#hsm.initialize(self)
	
