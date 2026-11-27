class_name ShipLaunch
extends RefCounted
## Server: launching a player from a carrier (a capital ship or station) in a
## new fighter. Functions only, no state: the carrier's request_launch RPC (it
## stays on Ship: Godot routes RPCs by node path) calls request.


## [param sender] asked [param carrier] to launch them. The peer comes from the
## connection, never from arguments, so nobody can launch someone else (or an
## NPC) by sending their ID.
static func request(carrier: Ship, sender: int) -> void:
	var galaxy := carrier.galaxy
	var player: Player = galaxy.get_node("Players").find_player_by_netid(sender)
	if player == null:
		Log.log(["Launch refused for peer ", sender, ": not logged in"], Log.MessageType.WARNING)
		return
	var refusal := launch_player(carrier, player.player_id, galaxy.ids)
	if refusal:
		Log.log(["Launch refused for ", player.name, " from ", carrier.name, ": ", refusal],
				Log.MessageType.WARNING)


## Launches player [param player_id]'s character from [param carrier] in a new
## fighter. Returns why not ("" when launched). Everything is checked before
## anything is built.
static func launch_player(carrier: Ship, player_id: int, ids: WorldIds) -> String:
	var passenger: Character = null
	for c in carrier.get_crew():
		if c._player_pilot_id == player_id:
			passenger = c
	if passenger == null:
		return "not aboard"
	if not carrier.get_node("Spawner").has_method("find_free_spawner"):
		return "no launch bays"
	var spawn := carrier.find_free_spawner()
	if spawn.is_empty():
		return "no free launch bay"
	var new_ship := Content.instantiate(carrier.launch_ship_id) as Ship
	if new_ship == null:
		Log.log(["Cannot launch ", carrier.launch_ship_id, " from ", carrier.name], Log.MessageType.ERROR)
		return "no craft to launch"

	Log.log(["Launching ", passenger.name, " from ", carrier.name], Log.MessageType.QUESTION)
	new_ship.is_spawning = true
	#TODO: Pull ship from existing invetory using the id
	new_ship.ship_id = ids.next_ship()
	carrier.get_current_system().add_ship(new_ship)
	new_ship.global_transform.origin = spawn[1]
	spawn[0].spawn_ship(new_ship)
	new_ship.faction_id = passenger.faction_id  # Before it is shown: the pilot knows it through their side.
	# Show it to clients now (N5a2): not as it entered the world, since its spawn
	# goes with its place at that moment, and not after the pilot leaves the
	# carrier, since a player between ships has no character and knows nothing.
	# The cockpit's RPCs below need the pilot's client to have it.
	if carrier.galaxy:
		carrier.galaxy.fog.refresh()
	var old_pilot: Character = carrier.get_node("Crew").remove_passenger_by_id(player_id)
	var pilot: Character = new_ship.get_node("CrewMultiplayerSpawner").spawn(old_pilot.serialize())
	#TODO: Genealize this to a multicrew craft
	var cockpit: Console = new_ship.get_node("Consoles/Cockpit") as Console
	cockpit.occupy(pilot)
	old_pilot.queue_free()
	carrier.disable_capital_ui.rpc_id(pilot.multiplayer_id)
	_finish(carrier.get_tree(), new_ship, pilot)
	return ""


## The launched craft is clear of the bay after a moment.
static func _finish(tree: SceneTree, new_ship: Ship, pilot: Character) -> void:
	await tree.create_timer(2.0).timeout
	if not is_instance_valid(new_ship):
		return
	new_ship.is_spawning = false
	for c in new_ship.get_node("Consoles").get_children():
		if c is Console:
			var helm := (c as Console).get_capability(HelmCapability) as HelmCapability
			if helm:
				helm.launch_completed()
	Log.log(["Spawn complete for ", pilot], Log.MessageType.SUCCESS)
