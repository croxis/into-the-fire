extends GutTest
## WorldState: a world's data as a record, apart from its scene nodes: what
## saves and the journal will serialize. Built here without any nodes. Galaxy
## holds one (Galaxy.state); its factions, ids and game_name are this record's.


func test_a_world_state_needs_no_nodes() -> void:
	var state := WorldState.new()
	state.game_name = "Babylon 4"
	state.factions.create("Earth Alliance")
	assert_eq(state.ids.next_ship(), 1)
	assert_eq(state.factions.size(), 1)
	assert_eq(state.players.size(), 0)


func test_a_new_player_is_registered_with_the_next_id() -> void:
	var players := PlayerRecords.new()
	assert_eq(players.log_in("Ivanova", "secret"), 1)
	assert_eq(players.log_in("Garibaldi", "jack"), 2)
	assert_eq(players.size(), 2)


func test_a_returning_player_keeps_their_id() -> void:
	var players := PlayerRecords.new()
	var id := players.log_in("Ivanova", "secret")
	assert_eq(players.log_in("Ivanova", "secret"), id)
	assert_eq(players.size(), 1)


func test_a_wrong_password_is_refused() -> void:
	var players := PlayerRecords.new()
	players.log_in("Ivanova", "secret")
	assert_eq(players.log_in("Ivanova", "guess"), PlayerRecords.REFUSED)


func test_records_hold_no_plain_passwords() -> void:
	var players := PlayerRecords.new()
	players.log_in("Ivanova", "secret")
	assert_false(var_to_str(players.record("Ivanova")).contains("secret"))


func test_the_galaxy_world_data_is_its_state() -> void:
	var galaxy: Galaxy = autofree(preload("res://Galaxy.tscn").instantiate())
	var registry := FactionRegistry.new()
	galaxy.factions = registry
	assert_eq(galaxy.state.factions, registry, "one place holds the factions")
	galaxy.game_name = "Test"
	assert_eq(galaxy.state.game_name, "Test")
	galaxy.ids.next_ship()
	assert_eq(galaxy.state.ids.next_ship(), 2, "the same counter")


func test_logins_go_through_the_worlds_player_records() -> void:
	var galaxy: Galaxy = preload("res://Galaxy.tscn").instantiate()
	add_child_autofree(galaxy)
	var players: Players = galaxy.get_node("Players")
	assert_true(players.check_player("Ivanova", "secret", 5))
	assert_eq(galaxy.state.players.size(), 1)
	assert_eq(players.find_player_by_netid(5).player_id, galaxy.state.players.record("Ivanova").player_id)
	assert_false(players.check_player("Ivanova", "guess", 6))
