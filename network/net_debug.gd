class_name NetDebug
extends RefCounted
## TEMPORARY: per-tick prediction logs, to find why the pilot's client and the
## server disagree while flying. Off unless the environment variable
## ITF_NETDEBUG is set to a path prefix; each process then writes
## <prefix>_server.log or <prefix>_client.log. Remove once the cause is found.

static var _file: FileAccess  # One per process (debug only; not game state).


static func on() -> bool:
	return OS.get_environment("ITF_NETDEBUG") != ""


static func line(role: String, text: String) -> void:
	if not on():
		return
	if _file == null:
		_file = FileAccess.open(OS.get_environment("ITF_NETDEBUG") + "_" + role + ".log", FileAccess.WRITE)
		if _file == null:
			return
	_file.store_line(text)
	_file.flush()


static func v(x: Vector3) -> String:
	return "%.6f,%.6f,%.6f" % [x.x, x.y, x.z]
