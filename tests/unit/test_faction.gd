extends GutTest
## Faction tree queries.
##
## Faction keeps its registry in static variables, so every test starts from a
## clean registry. (Moving factions into a per-world registry is planned.)


func before_each() -> void:
	Faction.factions.clear()
	Faction._next_id = 0


func after_all() -> void:
	Faction.factions.clear()
	Faction._next_id = 0


func _make(faction_name: String, is_wing: bool, parent: Faction = null) -> Faction:
	var f := Faction.new_faction(faction_name, is_wing, is_wing, false)
	f.parent_faction = parent
	return f


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
	assert_eq(Faction.get_faction("Babylon 5"), b5)
