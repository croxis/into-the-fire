extends GutTest
## Faction tree queries.
##
## Each test gets its own FactionRegistry, so there is no shared state to reset.

var registry: FactionRegistry


func before_each() -> void:
	registry = FactionRegistry.new()


func _make(faction_name: String, is_wing: bool, parent: Faction = null) -> Faction:
	return registry.create(faction_name, is_wing, is_wing, false, parent)


func test_get_wings_returns_only_direct_wing_children() -> void:
	var b5 := _make("Babylon 5", false)
	var alpha := _make("Alpha Wing", true, b5)
	var ops := _make("Ops", false, b5)
	_make("Sub Wing", true, ops)  # A wing, but a grandchild of b5.

	var wings := b5.get_wings()

	assert_eq(wings.size(), 1, "only direct children that are wings")
	assert_has(wings, alpha)


func test_get_wings_empty_when_no_children() -> void:
	var lonely := _make("Lonely", false)
	assert_eq(lonely.get_wings().size(), 0)


func test_is_a_parent_walks_up_the_tree() -> void:
	var ea := _make("Earth Alliance", false)
	var b5 := _make("Babylon 5", false, ea)
	var zeta := _make("Zeta Wing", true, b5)

	assert_true(zeta.is_a_parent(b5), "direct parent")
	assert_true(zeta.is_a_parent(ea), "grandparent")
	assert_false(ea.is_a_parent(zeta), "a child is not a parent")
	assert_false(ea.is_a_parent(b5), "top faction has no parents")


func test_get_faction_by_name() -> void:
	var b5 := _make("Babylon 5", false)
	assert_eq(registry.find_by_name("Babylon 5"), b5)


func test_add_member_moves_character_between_factions() -> void:
	var alpha := _make("Alpha Wing", true)
	var zeta := _make("Zeta Wing", true)
	var pilot: Character = autofree(preload("res://characters/character.tscn").instantiate())
	pilot.pilot_id = 4
	pilot.faction_registry = registry

	alpha.add_member(pilot)
	zeta.add_member(pilot)

	assert_eq(pilot.faction, zeta)
	assert_does_not_have(alpha.member_ids, 4, "left the old faction")
	assert_eq(zeta.member_ids, [4] as Array[int])


func test_remove_member_leaves_no_faction() -> void:
	var alpha := _make("Alpha Wing", true)
	var pilot: Character = autofree(preload("res://characters/character.tscn").instantiate())
	pilot.faction_registry = registry
	alpha.add_member(pilot)

	alpha.remove_member(pilot)

	assert_eq(pilot.faction_id, FactionRegistry.NO_FACTION)
	assert_null(pilot.faction, "0 is no faction, not the first faction")
