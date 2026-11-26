class_name GhostMarker
extends Node3D
## Client: where a lost contact probably is (netcode slice N5c, fog of war): a
## label with its name and a small diamond, drifting on its last known course
## and fading, both from ContactLog. Placeholder look until the pilot HUD; it
## sits in the contact's system, so it is drawn with that zone.

const COLOR := Color(1.0, 0.72, 0.25)  # Amber: not a live contact.

var _contacts: ContactLog
var _ship_id: int
var _now: Callable  # -> float: the server tick now (SnapshotClock).
var _label := Label3D.new()
var _diamond := Sprite3D.new()


## Follows [param ship_id] in [param contacts]; [param now] gives the server tick.
func setup(contacts: ContactLog, ship_id: int, now: Callable) -> void:
	_contacts = contacts
	_ship_id = ship_id
	_now = now
	name = "Ghost%d" % ship_id
	var c := contacts.get_contact(ship_id)
	_label.text = "%s\nlost contact" % c.get("name", "?")
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.no_depth_test = true
	_label.pixel_size = 0.0008
	_label.offset = Vector2(0, -28)
	_label.modulate = COLOR
	_diamond.texture = _diamond_texture()
	_diamond.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_diamond.fixed_size = true
	_diamond.no_depth_test = true
	_diamond.pixel_size = 0.0008
	_diamond.modulate = COLOR
	add_child(_label)
	add_child(_diamond)


func _process(_delta: float) -> void:
	var now: float = _now.call()
	var a := _contacts.ghost_alpha(_ship_id, now)
	if a <= 0.0:
		queue_free()  # Faded (or in contact again); the contact stays on record.
		return
	position = _contacts.ghost_position(_ship_id, now)
	_label.modulate.a = a
	_diamond.modulate.a = a


func label_text() -> String:
	return _label.text


func alpha() -> float:
	return _label.modulate.a


## A 16 px diamond outline, drawn here so there is no asset to ship.
static func _diamond_texture() -> Texture2D:
	var size := 16
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var mid := (size - 1) / 2.0
	for y in size:
		for x in size:
			var d := absf(x - mid) + absf(y - mid)
			if d <= mid and d >= mid - 1.5:
				image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)
