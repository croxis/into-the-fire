class_name ContactBrackets
extends Control
## Client: a bracket on the HUD for every other ship in the zone the player is
## viewing, with its name and distance, visible however far away it is (a
## Starfury 10 km out is smaller than a pixel). A ship off screen gets an arrow
## at the edge pointing to it. Green for the player's side (the same top-level
## faction), amber for anyone else; hostility comes with threat assessment.
##
## Only ships this client knows are drawn, so fog of war (network/) already
## decides what shows. Part of HudLayer; drawn only where something renders.

enum Side { OWN, OTHER }

## How far in from the screen's edge arrows sit, in pixels.
const EDGE_MARGIN := 28.0
## Half a bracket's width, in pixels.
const BRACKET := 14.0
const CORNER := 6.0
const COLORS := {Side.OWN: Color(0.35, 1.0, 0.45, 0.9), Side.OTHER: Color(1.0, 0.75, 0.2, 0.9)}

var _galaxy: Galaxy


func _init() -> void:
	name = "ContactBrackets"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_galaxy = Galaxy.find_for(self)
	set_process(DisplayServer.get_name() != "headless")


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _galaxy == null or _galaxy.zone_view.zone == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var size := get_viewport_rect().size
	var own := _own_ship()
	var font := get_theme_default_font()
	for ship in contacts_in(_galaxy.zone_view.zone, own):
		var color: Color = COLORS[side_of(ship, own.faction if own else null)]
		var mark := place(camera, ship.global_position, size)
		if mark.on_screen:
			_draw_bracket(mark.position, color)
			var text := "%s  %s" % [label_of(ship), distance_text(camera.global_position.distance_to(ship.global_position))]
			draw_string(font, mark.position + Vector2(BRACKET + 4.0, 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
		else:
			_draw_arrow(mark.position, mark.angle, color)


func _draw_bracket(at: Vector2, color: Color) -> void:
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var tip: Vector2 = at + corner * BRACKET
		draw_line(tip, tip - Vector2(corner.x * CORNER, 0), color, 2.0)
		draw_line(tip, tip - Vector2(0, corner.y * CORNER), color, 2.0)


func _draw_arrow(at: Vector2, angle: float, color: Color) -> void:
	var forward := Vector2.from_angle(angle)
	var side := forward.orthogonal()
	draw_colored_polygon(PackedVector2Array([at + forward * 12.0, at - forward * 6.0 + side * 8.0,
			at - forward * 6.0 - side * 8.0]), color)


## The ship the local player is aboard, or null.
func _own_ship() -> Ship:
	var character := _galaxy.zones.player_character(LocalGameManager.player_id)
	return character.current_ship if character else null


## Where [param point] (world space) goes on a screen of [param size] seen by
## [param camera]: {on_screen, position, angle}. Off screen (or behind the
## camera), the position is on the screen's edge, EDGE_MARGIN in, and angle
## points from the middle toward the point.
static func place(camera: Camera3D, point: Vector3, size: Vector2) -> Dictionary:
	var local := camera.global_transform.affine_inverse() * point
	# In front of the camera and inside the screen, however far: not the
	# frustum, whose far plane (4 km by default) is what hides distant ships.
	if local.z < 0.0:
		var at := camera.unproject_position(point)
		if Rect2(Vector2.ZERO, size).has_point(at):
			return {"on_screen": true, "position": at, "angle": 0.0}
	# Its direction across the screen; straight behind the camera: below.
	var direction := Vector2(local.x, -local.y)
	if direction.length() < 0.001:
		direction = Vector2.DOWN
	var center := size / 2.0
	var half := center - Vector2.ONE * EDGE_MARGIN
	var scale := minf(half.x / maxf(absf(direction.x), 0.0001), half.y / maxf(absf(direction.y), 0.0001))
	return {"on_screen": false, "position": center + direction * scale, "angle": direction.angle()}


## The other ships in [param zone] (a System) besides [param own].
static func contacts_in(zone: Node, own: Ship) -> Array[Ship]:
	var out: Array[Ship] = []
	var system := zone as System
	if system == null:
		return out
	for ship in system.get_ships():
		if ship != own and not ship.is_queued_for_deletion():
			out.append(ship)
	return out


## Whether [param ship] is on the side of [param mine] (a faction; null: none).
static func side_of(ship: Ship, mine: Faction) -> int:
	var theirs := ship.faction
	if mine == null or theirs == null:
		return Side.OTHER
	return Side.OWN if theirs.top_faction == mine.top_faction else Side.OTHER


## A crewed fighter by its pilot's name; anything else by the ship's.
static func label_of(ship: Ship) -> String:
	if not ship.is_station and not ship.is_capital:
		for c in ship.get_crew():
			if not c.is_queued_for_deletion():
				return String(c.name)
	return String(ship.name)


static func distance_text(metres: float) -> String:
	if metres < 1000.0:
		return "%d m" % roundi(metres)
	if metres < 100000.0:
		return "%.1f km" % (metres / 1000.0)
	return "%d km" % roundi(metres / 1000.0)
