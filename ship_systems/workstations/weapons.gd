extends ConsoleCapability
class_name WeaponsCapability
## A console's weapons: its occupant's trigger, each tick (Character._apply_input,
## from their tick-stamped input on the server), fires the guns it controls
## (system: a Guns node) as their cooldowns allow.


## Each tick: fires the guns at [param tick] while [param pressed].
func trigger(pressed: bool, tick: int) -> void:
	if pressed and is_available():
		system.fire_at(tick)
