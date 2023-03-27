@tool
extends Control

# https://www.reddit.com/r/godot/comments/kdimah/ui_create_altimeter_right_bar_and_airspeed/

@onready var font:Font = Control.new().get_theme_font('font')
var current_velocity:int = 0:
	set(velocity):
		current_velocity = velocity
		#trigger redraw
		queue_redraw()
@export var displayAbove = 300
@export var displayBelow = 300
@export var displayStepText  = 100
@export var displayStepSmallLines = 20
@export var display_color: Color = Color.GREEN
@export var draw_outline: bool = true
@export var font_size := 12.0

	
func _draw():
	var localRect = Rect2(Vector2(0, 0), size)
	if draw_outline:
		draw_rect(localRect, Color.GREEN, false, 2.0)
	
	#scale display range to control size
	var totalRange = displayAbove + displayBelow
	var height = localRect.size.y
	var width = localRect.size.x
	var altScale = width/totalRange

	#outline	
	var lineHeight = font.get_height()
	var cursorPosition = Vector2(localRect.position.x, 0)
	
	# Stupid unicode arrow isn't centered oin text. Hand drawing
	#var points = PoolVector2Array()
	#points.push_back(Vector2(localRect.position.x + 59, self.rect_size.y/2 + lineHeight/2))
	#points.push_back(Vector2(localRect.position.x + 64, self.rect_size.y/2 + lineHeight))
	#points.push_back(Vector2(localRect.position.x + 64, self.rect_size.y/2 + lineHeight/4))
	#var colors = PoolColorArray([display_color])
	#draw_polygon(points, colors)
	
	var label_size = font.get_string_size(str( current_velocity) + " m/s")
	
	#draw_string(font, Vector2(localRect.position.x + 120, self.rect_size.y/2 + lineHeight), "< " + String(current_velocity) + " m/s", display_color, -1)
	draw_string(font, Vector2(self.size.x/2 - label_size.x/2, 34 + lineHeight),  str(current_velocity) + " m/s", HORIZONTAL_ALIGNMENT_LEFT, -1, 16.0, display_color)
	
	for velocity in range(  current_velocity - displayBelow, current_velocity + displayAbove, 1 ):
		
		cursorPosition.x += altScale 
		
		if velocity % displayStepText == 0:
			#altitude Number
			#
			var string_size = font.get_string_size(str(velocity))
			draw_string(font, Vector2(cursorPosition.x - string_size.x / 2, cursorPosition.y + 26), str(velocity), HORIZONTAL_ALIGNMENT_LEFT, -1, 16.0, display_color)
			
			#altitude Line
			#var linePositionStart = Vector2(cursorPosition.x-20, cursorPosition.y - lineHeight/2 + 2)
			var linePositionStart = Vector2(cursorPosition.x, cursorPosition.y)
			#var linePositionEnd  =  Vector2(linePositionStart.x + 15, linePositionStart.y)
			var linePositionEnd  =  Vector2(linePositionStart.x, linePositionStart.y + 15)
			draw_line(linePositionStart,linePositionEnd, display_color,1.0, true)
		
		elif velocity % displayStepSmallLines == 0:
		#small lines inbetween
		
			#var linePositionStart = Vector2(cursorPosition.x-20, cursorPosition.y )
			var linePositionStart = Vector2(cursorPosition.x, cursorPosition.y )
			var linePositionEnd = Vector2(linePositionStart.x, linePositionStart.y + 5)
			
			
			draw_line(linePositionStart,linePositionEnd, display_color,1.0, true)	  
