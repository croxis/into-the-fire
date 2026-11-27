extends GutTest
## Interest: which ships the server tells each client about (netcode slice N5).
## Plain objects stand in for peers' systems and for ships: the rule only needs
## to know which system each one is in, and what each client's faction knows.

var interest: Interest
var alpha := RefCounted.new()  # A system.
var beta := RefCounted.new()   # Another system.
var ship_a1 := RefCounted.new()
var ship_a2 := RefCounted.new()
var ship_b1 := RefCounted.new()


func before_each() -> void:
	interest = Interest.new()


func _ships() -> Dictionary:
	return {ship_a1: alpha, ship_a2: alpha, ship_b1: beta}


## A client whose player is in [param system], and whose faction's picture has
## every ship (so only the system decides).
func _in(system: Object) -> Dictionary:
	return Interest.view(system, null, {ship_a1: true, ship_a2: true, ship_b1: true})


func test_a_client_knows_the_ships_in_its_own_system() -> void:
	interest.update({7: _in(alpha)}, _ships())
	assert_true(interest.knows(7, ship_a1))
	assert_true(interest.knows(7, ship_a2))
	assert_false(interest.knows(7, ship_b1), "another system")


func test_a_client_knows_only_what_its_faction_knows() -> void:
	# Fog of war (N5b3): the ships in its faction's sensor picture, in its system.
	interest.update({7: Interest.view(alpha, null, {ship_a1: true, ship_b1: true})}, _ships())
	assert_true(interest.knows(7, ship_a1))
	assert_false(interest.knows(7, ship_a2), "not in the picture")
	assert_false(interest.knows(7, ship_b1), "in the picture, but another system")


func test_a_client_always_knows_the_ship_its_player_is_aboard() -> void:
	# Whoever owns it: a passenger on someone else's ship.
	interest.update({7: Interest.view(alpha, ship_a2, {})}, _ships())
	assert_true(interest.knows(7, ship_a2))
	assert_false(interest.knows(7, ship_a1))


func test_a_factions_picture_is_its_ships_and_what_they_detect() -> void:
	var own1 := RefCounted.new()
	var own2 := RefCounted.new()
	var enemy := RefCounted.new()
	var unseen := RefCounted.new()
	var picture: Dictionary = Interest.picture([own1, own2], {own1: [enemy], own2: [own1]})
	assert_eq_deep(picture, {own1: true, own2: true, enemy: true})
	assert_false(picture.has(unseen))


func test_without_a_character_a_client_knows_nothing() -> void:
	# The join menu gets its spawn points from the server (N5b2).
	interest.update({7: null}, _ships())
	assert_false(interest.knows(7, ship_a1))
	assert_false(interest.knows(7, ship_b1))


func test_an_update_says_what_each_client_gained_and_lost() -> void:
	# What spawning and despawning (N5a2) act on.
	var changes := interest.update({7: _in(alpha)}, _ships())
	assert_eq_deep(changes[7]["shown"], [ship_a1, ship_a2])
	assert_eq_deep(changes[7]["leaving"], [])
	assert_eq_deep(changes[7]["hidden"], [])
	changes = interest.update({7: _in(beta)}, _ships())  # Jumped to beta.
	assert_eq_deep(changes[7]["shown"], [ship_b1])
	assert_eq_deep(changes[7]["leaving"], [ship_a1, ship_a2])
	assert_eq_deep(changes[7]["hidden"], [])
	changes = interest.update({7: _in(beta)}, _ships())
	assert_eq(changes[7]["hidden"], [ship_a1, ship_a2], "gone one update later")
	changes = interest.update({7: _in(beta)}, _ships())
	assert_false(changes.has(7), "nothing changed")


func test_a_leaving_ship_is_held_one_update_before_it_goes() -> void:
	# Snapshots and unreliable syncs stop at once, but the ship stays on the
	# client until the next update: one sent just before could still arrive
	# after a despawn and find no ship there.
	interest.update({7: _in(alpha)}, _ships())
	interest.update({7: _in(beta)}, _ships())
	assert_false(interest.knows(7, ship_a1), "no more snapshots")
	assert_true(interest.holds(7, ship_a1), "still on the client")
	interest.update({7: _in(beta)}, _ships())
	assert_false(interest.holds(7, ship_a1), "despawned")


func test_a_ship_back_before_it_went_just_carries_on() -> void:
	interest.update({7: _in(alpha)}, _ships())
	interest.update({7: _in(beta)}, _ships())
	var changes := interest.update({7: _in(alpha)}, _ships())
	assert_true(interest.knows(7, ship_a1))
	# Shown, so its snapshots and syncs start again; Godot doesn't spawn it
	# again, since the client still has it.
	assert_true(ship_a1 in changes[7]["shown"])
	assert_false(ship_a1 in changes[7]["hidden"])
	interest.update({7: _in(alpha)}, _ships())
	assert_true(interest.holds(7, ship_a1), "not despawned later either")


func test_a_ship_that_is_gone_is_forgotten() -> void:
	interest.update({7: _in(alpha)}, _ships())
	var changes := interest.update({7: _in(alpha)}, {ship_a2: alpha})
	assert_eq(changes[7]["hidden"], [ship_a1], "freed: nothing left to hold")
	assert_false(interest.holds(7, ship_a1))


func test_a_client_that_left_is_forgotten() -> void:
	interest.update({7: _in(alpha), 8: _in(alpha)}, _ships())
	interest.update({8: _in(alpha)}, _ships())
	assert_false(interest.knows(7, ship_a1))
	assert_true(interest.knows(8, ship_a1))
	assert_eq_deep(interest.peers(), [8])


func test_a_ship_freed_while_known_is_forgotten() -> void:
	# A ship destroyed in a fight is freed, not just gone from the list.
	var doomed := Node.new()
	interest.update({7: Interest.view(alpha, null, {doomed: true})}, {doomed: alpha})
	assert_true(interest.knows(7, doomed))
	doomed.free()
	var changes := interest.update({7: _in(alpha)}, _ships())
	assert_eq(changes[7]["hidden"].size(), 1, "freed: nothing left to hold")
