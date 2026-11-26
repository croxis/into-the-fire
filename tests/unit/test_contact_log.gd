extends GutTest
## ContactLog: a client's record of ships its side has lost contact with, and
## where to draw their ghosts (netcode slice N5c, fog of war).

const DT := 1.0 / 60.0

var contacts: ContactLog


func before_each() -> void:
	contacts = ContactLog.new(DT)


func _lost(ship_id: int, at: Vector3, velocity := Vector3.ZERO, tick := 600, immobile := false) -> void:
	contacts.lost(ship_id, {
		"name": "Narn Cruiser", "faction_id": 7, "system": "test_system",
		"transform": Transform3D(Basis(), at), "velocity": velocity,
		"immobile": immobile, "tick": tick,
	})


func test_a_ghost_starts_where_the_ship_was_last_seen() -> void:
	_lost(3, Vector3(100, 0, 0), Vector3(60, 0, 0))
	assert_eq(contacts.ghosts(600.0), [3] as Array[int])
	assert_almost_eq(contacts.ghost_position(3, 600.0), Vector3(100, 0, 0), Vector3.ONE * 1e-9)
	assert_almost_eq(contacts.ghost_alpha(3, 600.0), 1.0, 1e-9)


func test_a_ghost_drifts_on_the_last_known_course() -> void:
	# Dead reckoning: 60 m/s for 2 s.
	_lost(3, Vector3(100, 0, 0), Vector3(60, 0, 0))
	assert_almost_eq(contacts.ghost_position(3, 720.0), Vector3(220, 0, 0), Vector3.ONE * 1e-9)


func test_a_ghost_fades_out_over_the_fade_time() -> void:
	_lost(3, Vector3.ZERO)
	var half := 600.0 + contacts.fade_seconds / 2.0 / DT
	assert_almost_eq(contacts.ghost_alpha(3, half), 0.5, 1e-6)
	var gone := 600.0 + contacts.fade_seconds / DT
	assert_eq(contacts.ghost_alpha(3, gone), 0.0)
	assert_eq(contacts.ghosts(gone), [] as Array[int])


func test_the_fade_time_can_be_changed() -> void:
	# A client (and later fleet management) setting; 30 s by default.
	assert_eq(contacts.fade_seconds, 30.0)
	contacts.fade_seconds = 10.0
	_lost(3, Vector3.ZERO)
	assert_eq(contacts.ghosts(600.0 + 11.0 / DT), [] as Array[int])


func test_a_stations_ghost_stays_put_for_good() -> void:
	# Stations and other immobile objects: permanent, and they don't drift.
	_lost(1, Vector3(5, 0, 0), Vector3(60, 0, 0), 600, true)
	var much_later := 600.0 + 3600.0 / DT
	assert_eq(contacts.ghosts(much_later), [1] as Array[int])
	assert_eq(contacts.ghost_alpha(1, much_later), 1.0)
	assert_almost_eq(contacts.ghost_position(1, much_later), Vector3(5, 0, 0), Vector3.ONE * 1e-9)


func test_a_faded_contact_is_still_on_record_with_when_it_was_last_seen() -> void:
	# For future UI: when and where each object was last seen.
	_lost(3, Vector3(100, 0, 0), Vector3.ZERO, 600)
	var gone := 600.0 + contacts.fade_seconds / DT + 1
	assert_eq(contacts.ghosts(gone), [] as Array[int])
	var c: Dictionary = contacts.get_contact(3)
	assert_eq(c["last_seen_tick"], 600)
	assert_eq(c["name"], "Narn Cruiser")
	assert_false(c["in_contact"])


func test_contact_regained_ends_the_ghost() -> void:
	_lost(3, Vector3.ZERO)
	contacts.regained(3)
	assert_eq(contacts.ghosts(601.0), [] as Array[int])
	assert_true(contacts.get_contact(3)["in_contact"])
	_lost(3, Vector3(9, 0, 0), Vector3.ZERO, 900)  # Lost again: a new ghost from there.
	assert_almost_eq(contacts.ghost_position(3, 900.0), Vector3(9, 0, 0), Vector3.ONE * 1e-9)


func test_unknown_contacts_have_no_ghost() -> void:
	assert_eq(contacts.ghosts(0.0), [] as Array[int])
	assert_true(contacts.get_contact(42).is_empty())
	contacts.regained(42)  # Nothing to do, no error.
