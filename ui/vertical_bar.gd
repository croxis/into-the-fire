extends Control

# https://www.reddit.com/r/godot/comments/kdimah/ui_create_altimeter_right_bar_and_airspeed/

@onready var font:Font = Control.new().get_font('font')
var current_velocity:int = 0:
	set(velocity):
		current_velocity = velocity
		#trigger redraw
		queue_redraw()
var displayAbove = 300
var displayBelow = 300
var displayStepText  = 100
var displayStepSmallLines = 20
@export var display_color: Color = Color.GREEN
@export var right_justify: bool = false
#onready var font:DynamicFont = DynamicFont.new()


func _ready():
	#font.font_data = load("res://shared/fonts/DejaVuSans.ttf")
	#current_velocity = 523
	#temp test setup
	offset_bottom = 0
	offset_top = 0
	offset_left = 0
	offset_right = 0
	size = Vector2(100, 400)
	position = Vector2(0, 0)
	if right_justify:
		position = Vector2(200, 0)


func _process(delta):
	pass


func _draw():
	var localRect = Rect2( position, self.size )
	
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
		draw_string(font, Vector2(localRect.position.x + 120, self.rect_size.y/2 + lineHeight), "< " + str(current_velocity) + " m/s", HORIZONTAL_ALIGNMENT_LEFT, -1, 16.0, display_color)
	else:
		draw_string(font, Vector2(localRect.size.x - 120, self.rect_size.y/2 + lineHeight), str(current_velocity) + " m/s" + " >", HORIZONTAL_ALIGNMENT_LEFT, -1, 16.0, display_color)
	
	
	for velocity in range(current_velocity + displayAbove, current_velocity - displayBelow, -1 ):
		
		cursorPosition.y += altScale 
		
		if not right_justify:
			if velocity % displayStepText == 0:
				#altitude Number
				draw_string(font, cursorPosition, str(velocity), HORIZONTAL_ALIGNMENT_LEFT, -1, 16.0, display_color)
				
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
				draw_string(font, Vector2(localRect.end.x - 220, cursorPosition.y), str(velocity), HORIZONTAL_ALIGNMENT_LEFT, -1, 16.0, display_color)
				
				#altitude Line
				var linePositionStart = Vector2(localRect.end.x - 180, cursorPosition.y - lineHeight/2 + 2)
				var linePositionEnd = Vector2(linePositionStart.x - 15, linePositionStart.y)
				draw_line(linePositionStart, linePositionEnd, display_color, 1.0, true)
			
			elif velocity % displayStepSmallLines == 0:
			#small lines inbetween
			
				var linePositionStart = Vector2(localRect.end.x - 180, cursorPosition.y )
				var linePositionEnd = Vector2(linePositionStart.x - 5, linePositionStart.y)
				
				draw_line(linePositionStart, linePositionEnd, display_color, 1.0, true)  
