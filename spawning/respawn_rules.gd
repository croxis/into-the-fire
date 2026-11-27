class_name RespawnRules
extends Resource
## What happens to a crew when their ship is destroyed: a server's death rules
## (SpawnService.rules). Today's only rule respawns them at once aboard the
## nearest capital ship or station on their side in the same system. Escape
## pods, spacesuits or a choice per server are open questions (design doc).

enum Mode {
	NEAREST_CARRIER,  ## Aboard the nearest own-side carrier in that system, at once.
	NONE,  ## Nobody respawns: the crew die with the ship.
}

@export var mode := Mode.NEAREST_CARRIER
## NPC crews respawn too (today's behaviour), not only players.
@export var respawn_npcs := true


## Whether [param character] respawns under these rules.
func respawns(character: Character) -> bool:
	if mode == Mode.NONE:
		return false
	return respawn_npcs or character.is_player()
