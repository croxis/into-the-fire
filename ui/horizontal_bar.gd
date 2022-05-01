extends Control

# https://www.reddit.com/r/godot/comments/kdimah/ui_create_altimeter_right_bar_and_airspeed/

onready var font:Font = Control.new().get_font('font')
var current_velocity:int = 0 setget setCurrentVelocity
var displayAbove = 300
var displayBelow = 300
var displayStepText  = 100
var displayStepSmallLines = 20
export var display_color: Color = Color.green
#onready var font:DynamicFont = DynamicFont.new()

func _ready():
	#font.font_data = load("res://shared/fonts/DejaVuSans.ttf")
	#current_velocity = 523
	#temp test setup
	margin_bottom = 0
	margin_top = 0
	margin_left = 0
	margin_right = 0
	rect_size = Vector2(400, 100)
	rect_position = Vector2(0, 0)

func _process(delta):
	pass

	
func setCurrentVelocity(velocity:int):
	current_velocity = velocity
	#trigger redraw
	update()

	
func _draw():
	var localRect = Rect2(rect_position, self.rect_size )
	
	#draw outline shape
	#draw_rect(localRect,Color.white,false,2.0,true)
	
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
	
	var label_size = font.get_string_size(String( current_velocity) + " m/s")
	
	#draw_string(font, Vector2(localRect.position.x + 120, self.rect_size.y/2 + lineHeight), "< " + String(current_velocity) + " m/s", display_color, -1)
	draw_string(font, Vector2(self.rect_size.x/2 - label_size.x/2, 34 + lineHeight),  String(current_velocity) + " m/s", display_color,-1)
	
	for velocity in range(  current_velocity - displayBelow, current_velocity + displayAbove, 1 ):
		
		cursorPosition.x += altScale 
		
		if velocity % displayStepText == 0:
			#altitude Number
			#
			var string_size = font.get_string_size(String(velocity))
			draw_string(font, Vector2(cursorPosition.x - string_size.x / 2, cursorPosition.y + 26), String(velocity), display_color, -1)
			
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
