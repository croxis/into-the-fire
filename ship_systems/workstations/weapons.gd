extends ConsoleCapability
class_name WeaponsCapability


func fire() -> bool:
	if not is_available(): return false
	system.fire()
	return true
