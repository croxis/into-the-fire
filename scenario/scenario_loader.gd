class_name ScenarioLoader
extends RefCounted
## Checks a Scenario and turns it into a world. Server only.
##
## Three steps, so each can be tested on its own:
## 1. [method validate]: every reference resolves. Nothing is built from a
##    scenario that fails, so a typo gives a list of errors, not half a world.
## 2. [method build_factions]: the faction registry. Galaxy does this before
##    loading systems, so factions exist before anything joins them.
## 3. [method populate]: ships and crew, once the systems are in the tree.


## Everything wrong with [param scenario], or an empty array.
static func validate(scenario: Scenario, content: ContentRegistry) -> PackedStringArray:
	var errors := PackedStringArray()
	var names := {}
	for f in scenario.factions:
		if f.name.is_empty():
			errors.append("a faction has no name")
		elif names.has(f.name):
			errors.append("faction '%s' is listed twice" % f.name)
		names[f.name] = true
	for f in scenario.factions:
		if f.parent and not names.has(f.parent):
			errors.append("faction '%s' has unknown parent '%s'" % [f.name, f.parent])

	for id in scenario.systems:
		if not content.has(id):
			errors.append("unknown system '%s'" % id)

	for ship in scenario.ships:
		var label := ship.ship_name if ship.ship_name else String(ship.content_id)
		if not content.has(ship.content_id):
			errors.append("ship '%s': unknown content '%s'" % [label, ship.content_id])
		if ship.system not in scenario.systems:
			errors.append("ship '%s': system '%s' is not in the scenario's systems" % [label, ship.system])
		if ship.faction and not names.has(ship.faction):
			errors.append("ship '%s': unknown faction '%s'" % [label, ship.faction])
		for crew in ship.crew:
			if crew.faction and not names.has(crew.faction):
				errors.append("crew '%s' on '%s': unknown faction '%s'" % [crew.name, label, crew.faction])
	return errors


## Every scene the scenario needs: its systems in order, then each kind of
## ship once. Loaded in the background before the world is built (Galaxy).
## Unknown content is left out; [method validate] reports it.
static func scene_paths(scenario: Scenario, content: ContentRegistry) -> PackedStringArray:
	var paths := PackedStringArray()
	var ids: Array[StringName] = []
	ids.append_array(scenario.systems)
	for ship in scenario.ships:
		ids.append(ship.content_id)
	for id in ids:
		if not content.has(id):
			continue
		var path := content.path_of(id)
		if path not in paths:
			paths.append(path)
	return paths


## A new registry holding the scenario's factions. Assumes [method validate] passed.
static func build_factions(scenario: Scenario) -> FactionRegistry:
	var registry := FactionRegistry.new()
	# Parents first, whatever the listed order: create a faction once its
	# parent exists. Each pass creates at least one, or validate() would have
	# failed (an unknown parent), so this ends.
	var pending: Array[ScenarioFaction] = scenario.factions.duplicate()
	while not pending.is_empty():
		for f in pending.duplicate():
			var parent: Faction = null
			if f.parent:
				parent = registry.find_by_name(f.parent)
				if parent == null:
					continue
			var faction := registry.create(f.name, f.is_wing, f.accept_players,
					f.accept_children, parent)
			if f.doctrine:
				faction.doctrine = f.doctrine.duplicate()
			pending.erase(f)
	return registry


## Places the scenario's ships and crew. Returns the ships, in scenario order.
## [param systems] maps a system content ID to its node in the tree (a System,
## or anything with add_ship and add_station). [param peer_id] is the server's
## peer, which owns the NPCs' inputs.
static func populate(scenario: Scenario, content: ContentRegistry, registry: FactionRegistry,
		systems: Dictionary, ids: WorldIds, peer_id: int) -> Array[Ship]:
	var placed: Array[Ship] = []
	for entry in scenario.ships:
		var ship := content.instantiate(entry.content_id) as Ship
		if ship == null:
			continue
		if entry.ship_name:
			ship.name = entry.ship_name
		ship.ship_id = ids.next_ship()
		ship.position = entry.position
		var system: Node = systems[entry.system]
		if ship.is_station:
			system.add_station(ship)
		else:
			system.add_ship(ship)
		# Set after adding to the system: ships find the registry through Galaxy.
		var ship_faction := registry.find_by_name(entry.faction)
		ship.faction_id = ship_faction.faction_id if ship_faction else FactionRegistry.NO_FACTION
		for crew in entry.crew:
			_spawn_crew(ship, crew, ship_faction, registry, ids, peer_id)
		placed.append(ship)
	return placed


static func _spawn_crew(ship: Ship, crew: ScenarioCrew, ship_faction: Faction,
		registry: FactionRegistry, ids: WorldIds, peer_id: int) -> void:
	var faction := registry.find_by_name(crew.faction) if crew.faction else ship_faction
	var faction_id := faction.faction_id if faction else FactionRegistry.NO_FACTION
	var pilot := ship.spawn_crew(Character.pilot_data(crew.name, faction_id, peer_id, ids.next_pilot()))
	if pilot == null:
		return
	if faction:
		faction.add_member(pilot)
	if not crew.console.is_empty():
		var console := ship.get_node_or_null(crew.console) as Console
		if console == null:
			Log.log(["Scenario: no console ", crew.console, " on ", ship.name], Log.MessageType.ERROR)
		else:
			console.occupy(pilot)
