extends GutTest
## JoinFlow: the client-side faction and spawn picker, kept out of Galaxy so a
## world holds no UI (dedicated servers are headless). Galaxy only says when the
## player may pick (ready_to_spawn, factions_synced) and passes answers on
## (spawn_points_received, resumed). Offline, this machine is the server: a
## host, whose factions are always ready.

var galaxy: Galaxy
var flow: JoinFlow


func before_each() -> void:
	galaxy = preload("res://Galaxy.tscn").instantiate()
	galaxy.factions = FactionRegistry.new()
	galaxy.factions.create("Earth Alliance", false, true)
	add_child_autofree(galaxy)
	flow = JoinFlow.new(galaxy)
	add_child_autofree(flow)


func test_the_galaxy_holds_no_join_ui() -> void:
	assert_null(galaxy.get_node_or_null("CanvasLayer"))
	assert_eq(galaxy.find_children("*", "Control", true, false).size(), 0)


func test_the_menu_waits_until_the_player_may_pick() -> void:
	assert_false(flow.menu.visible, "hidden before the world is ready")
	galaxy.ready_to_spawn.emit()
	assert_true(flow.menu.visible, "a host has its factions at once")


func test_a_resumed_player_gets_no_menu() -> void:
	galaxy.ready_to_spawn.emit()
	galaxy.resumed.emit()
	assert_false(flow.menu.visible)


func test_a_host_gets_its_spawn_points_without_the_network() -> void:
	watch_signals(galaxy)
	galaxy.request_spawn_points("Earth Alliance")
	assert_signal_emitted_with_parameters(galaxy, "spawn_points_received", ["Earth Alliance", {}])


func test_unknown_factions_get_no_spawn_points() -> void:
	watch_signals(galaxy)
	galaxy.request_spawn_points("Psi Corps")
	assert_signal_not_emitted(galaxy, "spawn_points_received")
