## Liblast Logger
extends Node

enum MessageType {NONE, INFO, WARNING, QUESTION, ERROR, SUCCESS, PANIC, MAX}


## Multiplayer API override; GameState should set this
var _multiplayer : MultiplayerAPI

## Generate a unique color from a network peer id
func _get_color_from_pid(pid : int) -> Color:
	var color : Color
	var hue = roundf(fmod(float(pid) / 10000.0, 1) * 16) / 16.0;
	color = Color.from_ok_hsl(hue, 1, 0.85)
	return color

## Set multiplayer API override
func set_multiplayer(new_multiplayer: MultiplayerAPI):
	_multiplayer = new_multiplayer


func get_message_type_symbol(message_type : MessageType) -> String:
	match message_type:
		MessageType.NONE:
			return "·" #nbsp;
		MessageType.INFO:
			return "ℹ"
		MessageType.WARNING:
			return "❕"
		MessageType.QUESTION:
			return "❔"
		MessageType.ERROR:
			return "❌"
		MessageType.SUCCESS:
			return "✅"
		MessageType.PANIC:
			return "🔥"
		_:
			return " "

		# Other possibly useful symbols: ❎❌❌🕱✅☑🗹🛈ℹ❗❕◉◎⌁⚡


func log(what : Variant, message_type := MessageType.NONE) -> void:
	var pid : int

	if is_instance_valid(_multiplayer):
		pid = _multiplayer.get_unique_id()
	elif is_instance_valid(multiplayer):
		pid = multiplayer.get_unique_id()
	else:
		pid = -1

	var log_color : Color
	var log_prefix : String

	match pid:
		-1: # OFFLINE
			log_color = Color.WHITE_SMOKE
			log_prefix = ""
		1: # SERVER
			log_color = Color.MEDIUM_VIOLET_RED
			log_prefix = "SERVER"
		_: # CLIENT
			log_color = _get_color_from_pid(pid)
			log_prefix = str(pid).left(6)

	# Convert the log message to a string, trying to do a clean job
	var args : Array = []
	args.append(log_color.to_html(false)) # color
	args.append(get_message_type_symbol(message_type))
	args.append(log_prefix)
	var msg : String = ''
	if what is Array:
		for i in what:
			msg += str(str(i).strip_edges()) + ' '
	else:
		msg = str(what)
	msg.strip_edges()

	args.append(msg)

	print_rich("[color=%s]%c [b]%s[/b] [i]%s" % args)
