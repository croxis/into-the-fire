extends GutTest
## Interest: which ships the server tells each client about (netcode slice N5).
## Plain objects stand in for peers' systems and for ships: the rule only needs
## to know which system each one is in.

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


func test_a_client_knows_the_ships_in_its_own_system() -> void:
	interest.update({7: alpha}, _ships(), [])
	assert_true(interest.knows(7, ship_a1))
	assert_true(interest.knows(7, ship_a2))
	assert_false(interest.knows(7, ship_b1), "another system")


func test_without_a_character_a_client_knows_the_ships_where_it_could_spawn() -> void:
	# The join menu lists spawn points from the ships the client has.
	interest.update({7: null}, _ships(), [beta])
	assert_false(interest.knows(7, ship_a1))
	assert_true(interest.knows(7, ship_b1))


func test_an_update_says_what_each_client_gained_and_lost() -> void:
	# What the spawn and despawn step (N5a2) will act on.
	var changes := interest.update({7: alpha}, _ships(), [])
	assert_eq_deep(changes[7]["shown"], [ship_a1, ship_a2])
	assert_eq_deep(changes[7]["hidden"], [])
	changes = interest.update({7: beta}, _ships(), [])  # Jumped to beta.
	assert_eq_deep(changes[7]["shown"], [ship_b1])
	assert_eq_deep(changes[7]["hidden"], [ship_a1, ship_a2])
	changes = interest.update({7: beta}, _ships(), [])
	assert_false(changes.has(7), "nothing changed")


func test_a_ship_that_is_gone_is_forgotten() -> void:
	interest.update({7: alpha}, _ships(), [])
	var changes := interest.update({7: alpha}, {ship_a2: alpha}, [])
	assert_eq_deep(changes[7]["hidden"], [ship_a1])
	assert_false(interest.knows(7, ship_a1))


func test_a_client_that_left_is_forgotten() -> void:
	interest.update({7: alpha, 8: alpha}, _ships(), [])
	interest.update({8: alpha}, _ships(), [])
	assert_false(interest.knows(7, ship_a1))
	assert_true(interest.knows(8, ship_a1))
	assert_eq_deep(interest.peers(), [8])
