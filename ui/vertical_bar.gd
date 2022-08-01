extends Control

# https://www.reddit.com/r/godot/comments/kdimah/ui_create_altimeter_right_bar_and_airspeed/

@onready var font:Font = Control.new().get_font('font')
var current_velocity:int = 0 setget set_current_velocity
var displayAbove = 300
var displayBelow = 300
var displayStepText  = 100
var displayStepSmallLines = 20
@export var display_color: Color = Color.green
@export var right_justify: bool = false
#onready var font:DynamicFont = DynamicFont.new()

func _ready():
	#font.font_data = load("res://shared/fonts/DejaVuSans.ttf")
	#current_velocity = 523
	#temp test setup
	margin_bottom = 0
	margin_top = 0
	margin_left = 0
	margin_right = 0
	rect_size = Vector2(100, 400)
	rect_position = Vector2(0, 0)
	if right_justify:
		rect_position = Vector2(200, 0)


func _process(delta):
	pass

	
func set_current_velocity(velocity:int):
	current_velocity = velocity
	#trigger redraw
	update()


func _draw():
	var localRect = Rect2( rect_position, self.rect_size )
	
	#draw outline shape
	#draw_rect(localRect, Color.white, false, 2.0, true)
	
	#scale display range to control size
	var totalRange = displayAbove + displayBelow
	var height = localRect.size.y
	var altScale = height/totalRange

	#outline	
	var lineHeight = font.get_height()
	var cursorPosition = Vector2(localRect.end.x - 20, lineHeight)
	
	# Stupid unicode arrow isn't centered oin text. Hand drawing
	#var points = PoolVector2Array()
	#points.push_back(Vector2(localRect.position.x + 59, self.rect_size.y/2 + lineHeight/2))
	#points.push_back(Vector2(localRect.position.x + 64, self.rect_size.y/2 + lineHeight))
	#points.push_back(Vector2(localRect.position.x + 64, self.rect_size.y/2 + lineHeight/4))
	#var colors = PoolColorArray([display_color])
	#draw_polygon(points, colors)
	
	#draw_string(font, Vector2(localRect.position.x + 65, self.rect_size.y/2 + lineHeight), "< " + String(current_velocity) + " m/s", display_color,-1)
	if not right_justify:
		draw_string(font, Vector2(localRect.position.x + 120, self.rect_size.y/2 + lineHeight), "< " + String(current_velocity) + " m/s", display_color, -1)
	else:
		draw_string(font, Vector2(localRect.size.x - 120, self.rect_size.y/2 + lineHeight), String(current_velocity) + " m/s" + " >", display_color, -1)
	
	
	for velocity in range(current_velocity + displayAbove, current_velocity - displayBelow, -1 ):
		
		cursorPosition.y += altScale 
		
		if not right_justify:
			if velocity % displayStepText == 0:
				#altitude Number
				draw_string(font, cursorPosition, String(velocity), display_color,-1)
				
				#altitude Line
				var linePositionStart = Vector2(cursorPosition.x-20, cursorPosition.y - lineHeight/2 + 2)
				var linePositionEnd  =  Vector2(linePositionStart.x + 15, linePositionStart.y)
				draw_line(linePositionStart, linePositionEnd, display_color,1.0, true)
			
			elif velocity % displayStepSmallLines == 0:
			#small lines inbetween
				var linePositionStart = Vector2(cursorPosition.x-20, cursorPosition.y )
				var linePositionEnd = Vector2(linePositionStart.x + 5, linePositionStart.y)
				
				draw_line(linePositionStart, linePositionEnd, display_color, 1.0, true)  
		else:
			if velocity % displayStepText == 0:
				#altitude Number
				draw_string(font, Vector2(localRect.end.x - 220, cursorPosition.y), String(velocity), display_color,-1)
				
				#altitude Line
				var linePositionStart = Vector2(localRect.end.x - 180, cursorPosition.y - lineHeight/2 + 2)
				var linePositionEnd = Vector2(linePositionStart.x - 15, linePositionStart.y)
				draw_line(linePositionStart, linePositionEnd, display_color, 1.0, true)
			
			elif velocity % displayStepSmallLines == 0:
			#small lines inbetween
			
				var linePositionStart = Vector2(localRect.end.x - 180, cursorPosition.y )
				var linePositionEnd = Vector2(linePositionStart.x - 5, linePositionStart.y)
				
				draw_line(linePositionStart, linePositionEnd, display_color, 1.0, true)  
