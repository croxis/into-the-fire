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
@export var right_justify: bool = false
@export var draw_outline: bool = true
@export var font_size := 12


func _draw():
	var localRect = Rect2(Vector2(0, 0), size)
	if draw_outline:
		draw_rect(localRect, Color.GREEN, false, 2.0)
	
	#scale display range to control size
	var totalRange = displayAbove + displayBelow
	var height = localRect.size.y
	var altScale = height/totalRange 

	var lineHeight = font.get_height(font_size)
	var cursorPosition = Vector2(localRect.position.x, 0)
	if right_justify:
		cursorPosition.x = localRect.end.x
	
	if not right_justify:
		draw_string(font, Vector2(localRect.position.x + 50, size.y/2 + lineHeight/4), "< " + str(current_velocity) + " m/s", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, display_color)
	else:
		draw_string(font, Vector2(localRect.end.x - 95, size.y/2 + lineHeight/4), str(current_velocity) + " m/s" + " >", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, display_color)
	
	
	for velocity in range(current_velocity + displayAbove, current_velocity - displayBelow, -1 ):
		
		cursorPosition.y += altScale 
		
		if not right_justify:
			if velocity % displayStepText == 0:
				#altitude Number
				draw_string(font, Vector2(cursorPosition.x + 20, cursorPosition.y + lineHeight/4), str(velocity), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, display_color)
				
				#altitude Line
				var linePositionStart = Vector2(cursorPosition.x, cursorPosition.y)
				var linePositionEnd = Vector2(linePositionStart.x + 15, linePositionStart.y)
				draw_line(linePositionStart, linePositionEnd, display_color,1.0, true)
			
			elif velocity % displayStepSmallLines == 0:
			#small lines inbetween
				var linePositionStart = Vector2(cursorPosition.x, cursorPosition.y)
				var linePositionEnd = Vector2(linePositionStart.x + 5, linePositionStart.y)
				
				draw_line(linePositionStart, linePositionEnd, display_color, 1.0, true)  
		else:
			if velocity % displayStepText == 0:
				#altitude Number
				draw_string(font, Vector2(cursorPosition.x - 45, cursorPosition.y + lineHeight/4), str(velocity), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, display_color)
				
				#altitude Line
				var linePositionStart = Vector2(localRect.end.x, cursorPosition.y)
				var linePositionEnd = Vector2(linePositionStart.x - 15, linePositionStart.y)
				draw_line(linePositionStart, linePositionEnd, display_color, 1.0, true)
			
			elif velocity % displayStepSmallLines == 0:
			#small lines inbetween
			
				var linePositionStart = Vector2(localRect.end.x, cursorPosition.y )
				var linePositionEnd = Vector2(linePositionStart.x - 5, linePositionStart.y)
				
				draw_line(linePositionStart, linePositionEnd, display_color, 1.0, true)  
