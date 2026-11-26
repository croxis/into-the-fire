extends GutTest
## Crew are created through the ship's CrewMultiplayerSpawner.
##
## A character added with plain add_child() exists only on the server: clients
## never receive it, and its synchronizers log "Node not found" there. Going
## through the spawner sends it to every client with the same data.

const ShipScene := preload("res://ships/Ship.tscn")


func _ship() -> Ship:
	var ship: Ship = ShipScene.instantiate()
	add_child_autofree(ship)
	return ship


func test_pilot_data_restores_a_character() -> void:
	var data := Character.pilot_data("Susan", 3, 7, 4, 2)
	var c: Character = autofree(preload("res://characters/character.tscn").instantiate())
	c.restore(data)
	assert_eq(String(c.name), "Susan")
	assert_eq(c.faction_id, 3)
	assert_eq(c.multiplayer_id, 7)
	assert_eq(c.pilot_id, 4)
	assert_eq(c._player_pilot_id, 2)


func test_spawn_crew_adds_a_crew_member() -> void:
	var ship := _ship()
	var pilot := ship.spawn_crew(Character.pilot_data("Karren", 0, 1, 1))
	assert_not_null(pilot)
	assert_eq(pilot.get_parent(), ship.get_node("Crew"))
	assert_eq(pilot.current_ship, ship)
	assert_eq(String(pilot.name), "Karren")
	assert_eq(pilot.get_node("InputsSync").get_multiplayer_authority(), 1, "inputs belong to its peer")


func test_full_ship_refuses_crew() -> void:
	var ship := _ship()  # Ship.tscn holds one crew member.
	assert_not_null(ship.spawn_crew(Character.pilot_data("First", 0, 1, 1)))
	assert_null(ship.spawn_crew(Character.pilot_data("Second", 0, 1, 2)))
	assert_eq(ship.get_crew().size(), 1)


## Docking: a ship entering a carrier's dock area boards its crew and is freed.
## Only on the server, which owns the world: a client docking its own copy freed
## a Starfury launched from the Hyperion's hangar (it starts inside the dock
## area), and the server went on sending state for a ship the client no longer
## had.

func test_the_server_docks_a_ship_that_enters_the_dock() -> void:
	var carrier := _ship()
	var fighter := _ship()
	carrier._on_area_3d_dock_body_entered(fighter)
	assert_true(fighter.is_queued_for_deletion())


func test_a_client_never_docks() -> void:
	var carrier := _ship()
	var fighter := _ship()
	var client := SceneMultiplayer.new()
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", 9)  # Never connects: a client all the same.
	client.multiplayer_peer = peer
	get_tree().set_multiplayer(client, carrier.get_path())
	assert_false(carrier.multiplayer.is_server(), "set up as a client")
	carrier._on_area_3d_dock_body_entered(fighter)
	get_tree().set_multiplayer(null, carrier.get_path())
	peer.close()
	assert_false(fighter.is_queued_for_deletion(), "left for the server to decide")
