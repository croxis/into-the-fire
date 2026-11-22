extends GutTest
## FactionRegistry: IDs, lookups, the faction tree and the network copy.

var registry: FactionRegistry


func before_each() -> void:
	registry = FactionRegistry.new()


func _playtest_tree() -> Dictionary:
	var ea := registry.create("Earth Alliance")
	var b5 := registry.create("Babylon 5", false, false, false, ea)
	var zeta := registry.create("Zeta Wing", true, true, false, b5)
	return {"ea": ea, "b5": b5, "zeta": zeta}


func test_ids_start_at_one() -> void:
	var first := registry.create("First")
	var second := registry.create("Second")
	assert_eq(first.faction_id, 1, "0 is reserved for no faction")
	assert_eq(second.faction_id, 2)


func test_no_faction_id_finds_nothing() -> void:
	registry.create("First")
	assert_null(registry.get_by_id(FactionRegistry.NO_FACTION))
	assert_null(registry.get_by_id(99), "unknown ids are null, not an error")


func test_find_by_name() -> void:
	var t := _playtest_tree()
	assert_eq(registry.find_by_name("Zeta Wing"), t.zeta)
	assert_null(registry.find_by_name("Psi Corps"))


func test_tree_queries() -> void:
	var t := _playtest_tree()
	var beta := registry.create("Beta Wing", true, true, false, t.b5)
	assert_eq(registry.top_level(), [t.ea] as Array[Faction])
	assert_eq(registry.children_of(t.b5), [t.zeta, beta] as Array[Faction])
	assert_eq(t.b5.get_wings(), [t.zeta, beta] as Array[Faction], "Faction asks its registry")


func test_registries_are_independent() -> void:
	registry.create("Earth Alliance")
	var other := FactionRegistry.new()
	assert_eq(other.size(), 0, "no shared static state")
	assert_eq(other.create("Minbari Federation").faction_id, 1)


func test_faction_outside_a_registry_has_no_children() -> void:
	var loose := Faction.new()
	assert_eq(loose.get_children().size(), 0)


func test_data_round_trip_keeps_ids_and_tree() -> void:
	var t := _playtest_tree()
	t.zeta.member_ids.assign([3, 5])
	t.zeta.leader_id = 3

	var copy := FactionRegistry.from_data(registry.to_data())

	assert_eq(copy.size(), 3)
	var zeta := copy.get_by_id(t.zeta.faction_id)
	assert_eq(zeta.resource_name, "Zeta Wing")
	assert_true(zeta.is_wing)
	assert_true(zeta.accept_players)
	assert_eq(zeta.parent_faction, copy.get_by_id(t.b5.faction_id), "parents point into the copy")
	assert_true(zeta.is_a_parent(copy.find_by_name("Earth Alliance")))
	assert_eq(zeta.member_ids, [3, 5] as Array[int])
	assert_eq(zeta.leader_id, 3)


func test_copy_continues_numbering() -> void:
	_playtest_tree()
	var copy := FactionRegistry.from_data(registry.to_data())
	assert_eq(copy.create("Psi Corps").faction_id, 4)


func test_copy_never_reuses_an_id() -> void:
	_playtest_tree()
	var data := registry.to_data()
	data["next_id"] = 1  # Damaged or old data.
	var copy := FactionRegistry.from_data(data)
	assert_eq(copy.create("Psi Corps").faction_id, 4)


func test_parent_listed_after_child_still_links() -> void:
	var data := {"factions": [
		{"id": 2, "name": "Zeta Wing", "parent_id": 1, "is_wing": true},
		{"id": 1, "name": "Babylon 5"},
	]}
	var copy := FactionRegistry.from_data(data)
	assert_eq(copy.get_by_id(2).parent_faction, copy.get_by_id(1))


func test_data_has_no_objects() -> void:
	# Sent over the network: Object references can't cross it.
	_playtest_tree()
	var data := registry.to_data()
	for entry: Dictionary in data["factions"]:
		for key in entry:
			assert_false(entry[key] is Object, "%s is plain data" % key)


## Character and Ship look factions up through a registry.

func test_character_faction_comes_from_its_registry() -> void:
	var t := _playtest_tree()
	var pilot: Character = autofree(preload("res://characters/character.tscn").instantiate())
	pilot.faction_registry = registry
	t.zeta.add_member(pilot)
	assert_eq(pilot.faction, t.zeta)


func test_character_without_registry_has_no_faction() -> void:
	var pilot: Character = autofree(preload("res://characters/character.tscn").instantiate())
	pilot.faction_id = 2
	assert_null(pilot.faction, "no Galaxy above it and no registry given")


func test_ship_joins_owned_ships_of_its_faction() -> void:
	var t := _playtest_tree()
	var ship: Ship = preload("res://ships/Ship.tscn").instantiate()
	ship.faction_registry = registry
	add_child_autofree(ship)

	ship.faction_id = t.b5.faction_id
	assert_has(t.b5.owned_ships, ship)

	ship.faction_id = FactionRegistry.NO_FACTION
	assert_does_not_have(t.b5.owned_ships, ship)


## Galaxy.check_spawn_request: spawn requests come from clients and are not trusted.

func _systems() -> Node:
	var systems: Node = add_child_autofree(Node.new())
	var system := Node.new()
	system.name = "test_system"
	systems.add_child(system)
	return systems


func test_spawn_request_accepted() -> void:
	var t := _playtest_tree()
	assert_eq(Galaxy.check_spawn_request(registry, _systems(), t.zeta.faction_id, "test_system"), "")


func test_spawn_request_unknown_faction_refused() -> void:
	_playtest_tree()
	assert_ne(Galaxy.check_spawn_request(registry, _systems(), 42, "test_system"), "")


func test_spawn_request_closed_faction_refused() -> void:
	var t := _playtest_tree()
	assert_ne(Galaxy.check_spawn_request(registry, _systems(), t.b5.faction_id, "test_system"), "",
			"Babylon 5 itself doesn't accept players, only its wings")


func test_spawn_request_unknown_system_refused() -> void:
	var t := _playtest_tree()
	var systems := _systems()
	assert_ne(Galaxy.check_spawn_request(registry, systems, t.zeta.faction_id, "Narn"), "")
	assert_ne(Galaxy.check_spawn_request(registry, systems, t.zeta.faction_id, ".."), "",
			"a path out of Systems is not a system")
