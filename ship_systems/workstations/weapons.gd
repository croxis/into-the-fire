extends ConsoleCapability
class_name WeaponsCapability
## A console's weapons: its occupant's trigger, each tick (Character._apply_input,
## from their tick-stamped input on the server), fires the guns it controls
## (system: a Guns node) as their cooldowns allow.


## Each tick: fires the guns at [param tick] while [param pressed]. Their shots
## are checked against targets [param rewind] ticks back (ShotField.rewind_for);
## [param client_tick] is the remote pilot's input tick (Shot.client_tick).
func trigger(pressed: bool, tick: int, rewind := 0, client_tick := -1) -> void:
	if pressed and is_available():
		system.fire_at(tick, rewind, client_tick)
