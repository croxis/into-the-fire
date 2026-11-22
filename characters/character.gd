class_name Character
extends Node

# This getter setter chain is attempting to automagically assign the player the correct resource for
# network clients
## 0 (FactionRegistry.NO_FACTION) means no faction. Change membership with
## Faction.add_member() rather than setting this directly.
@export var faction_id: int:
	set(new_id):
		if new_id == faction_id:
			return
		faction_id = new_id
		var f := faction
		Log.log(["Character ", name, " faction: ", _faction_label(f), " (", faction_id, ")"], Log.MessageType.INFO)
## The faction for faction_id, or null (no faction, or no registry reachable yet).
var faction: Faction:
	get:
		var r := factions
		return r.get_by_id(faction_id) if r else null
## Set this to use a registry directly, for example in a unit test or before the
## character is in the tree. Otherwise the Galaxy above this node is used.
var faction_registry: FactionRegistry
var factions: FactionRegistry:
	get:
		if faction_registry:
			return faction_registry
		var galaxy := Galaxy.find_for(self)
		return galaxy.factions if galaxy else null
# If this is the player, set the id to 1 or more. 0 means an NPC.
@export var _player_pilot_id: int:
	set(new_id):
		_player_pilot_id = new_id
		_update_brain_active()
@export var multiplayer_id: int
@export var pilot_id: int
var active_orders: Array[OrderData] = []
var pending_orders: Array[OrderData] = []
var personality
var current_console: Console

@onready var hsm: LimboHSM = $BrainHSM # Later make behavior tree

@onready var inputs: InputSynchronizer:
	get:
		return get_node("InputsSync")

## The ship whose Crew node holds this character, or null.
var current_ship: Ship:
	get:
		var crew_node := get_parent()
		return crew_node.get_parent() as Ship if crew_node else null

@export var doctrine_var: StringName = &"doctrine"

static var next_id := 0
static var pilot_scene: PackedScene = load("res://characters/character.tscn")

var _brain_initialized := false

static func new_pilot(new_name: String) -> Character:
	var new_pilot_instance = pilot_scene.instantiate()
	new_pilot_instance.name = new_name
	new_pilot_instance.pilot_id = next_id
	next_id += 1
	return new_pilot_instance


func _ready():
	_init_brain()


func _init_brain() -> void:
	hsm = $BrainHSM
	var idle_state: LimboState = $BrainHSM/IdleState
	var moving_to_state: LimboState = $BrainHSM/MovingToConsoleState
	var operating_state: LimboState = $BrainHSM/OperatingConsoleState
	var moving_ship_state: LimboState = $BrainHSM/MovingToShipState
	var dead_state: LimboState = $BrainHSM/DeadState
	hsm.add_transition(idle_state, operating_state, &"move_console")
	hsm.add_transition(operating_state, idle_state, &"leave_console")
	hsm.add_transition(idle_state, moving_ship_state, "leave_ship")
	hsm.add_transition(moving_ship_state, idle_state, "enter_ship")
	hsm.add_transition(hsm.ANYSTATE, dead_state, "died")
	hsm.add_transition(dead_state, idle_state, "respawn")
	hsm.initial_state = idle_state
	hsm.initialize(self)
	_brain_initialized = true
	_update_brain_active()



## For logs: the faction name, "none" for no faction, or a note that the
## registry isn't reachable yet (not in the world).
func _faction_label(f: Faction) -> String:
	if f:
		return f.resource_name
	return "none" if faction_id == FactionRegistry.NO_FACTION else "not in world yet"


func is_player() -> bool:
	return _player_pilot_id > 0


## The brain only thinks for NPCs, and only where the simulation is authoritative.
## Players drive their character with inputs instead.
func _update_brain_active() -> void:
	# restore() can set _player_pilot_id before the node enters the tree.
	if not _brain_initialized:
		return
	hsm.set_active(multiplayer.is_server() and not is_player())


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
		var helm := current_console.get_capability(HelmCapability) as HelmCapability
		if helm:
			if inputs.autobreak_toggle:
				helm.toggle_autobreak()
			if inputs.autospin_toggle:
				helm.toggle_autospin()
			helm.input_rotation_throttle = inputs.rotation_throttle
			helm.throttle = inputs.throttle
			if inputs.debug_all_stop:
				helm._debug_all_stop()
		# TODO: Weapons capability is found but firing is not wired to inputs yet.
		if Input.is_action_just_released("camera_change") and _player_pilot_id == LocalGameManager.player_id:
			current_console.change_camera()
		var command := current_console.get_capability(CommandCapability) as CommandCapability
		if command:
			# AI updates server only and non players
			if multiplayer.is_server() and _player_pilot_id < 1:
				var threats: Array[Ship] = [] # TODO: command.get_hostiles()
				$BrainHSM.blackboard.set_var(&"threat_picture", threats)
				$BrainHSM.blackboard.set_var(doctrine_var, faction.doctrine if faction else null)
				$BrainHSM.blackboard.set_var(&"fighters_deployed", command.get_subordinate_ships_in_escort_range())
				$BrainHSM.blackboard.set_var(&"current_ship", current_ship)
				$BrainHSM.blackboard.set_var(&"faction", faction)


func _to_string() -> String:
	return name


func serialize() -> Dictionary:
	var payload:= {}
	# Personality
	# payload["personality"] = personality.resource_path
	
	# Blackboard. Object references (ships, factions, doctrine) are runtime
	# context rebuilt every tick, and cannot cross the network, so skip them.
	var blackboard: Blackboard = $BrainHSM.blackboard
	for key in blackboard.list_vars():
		var value = blackboard.get_var(key)
		if value is Object:
			continue
		payload["bb_" + key] = value
	
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
			$BrainHSM.blackboard.set_var(bb_key, payload[key])
	
	name = payload["name"]
	faction_id = payload["faction_id"]
	_player_pilot_id = payload["_player_pilot_id"]
	multiplayer_id = payload["multiplayer_id"]
	pilot_id = payload["pilot_id"]
	active_orders = payload["active_orders"]
	pending_orders = payload["pending_orders"]
	
	#hsm.initialize(self)
	
