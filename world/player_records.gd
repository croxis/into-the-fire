class_name PlayerRecords
extends RefCounted
## Server: the players a world knows, by name: their player ID (kept for good,
## so a returning player is the same player) and a salted password hash.
## World data (part of WorldState), so saves keep it. The Player nodes under
## Galaxy/Players are only this session's view of who is online, replicated
## to clients without any password.
##
## The hash is a salted SHA-256, enough to keep plain passwords out of saves
## and logs; a slow key-derivation function is still to do before servers
## hold real players' passwords.

## log_in's answer for a known name with the wrong password.
const REFUSED := 0

var _records := {}  # name -> {"player_id": int, "salt": String, "hash": String}
var _next_id := 1  # 0 is reserved for NPCs.


func size() -> int:
	return _records.size()


## [param player_name]'s player ID, registering them first if the name is new;
## REFUSED when the name is known and [param password] is wrong.
func log_in(player_name: String, password: String) -> int:
	if _records.has(player_name):
		var r: Dictionary = _records[player_name]
		return r.player_id if _hash(r.salt, password) == r.hash else REFUSED
	var salt := Crypto.new().generate_random_bytes(16).hex_encode()
	_records[player_name] = {"player_id": _next_id, "salt": salt, "hash": _hash(salt, password)}
	_next_id += 1
	return _records[player_name].player_id


## [param player_name]'s record (a copy), or an empty dictionary.
func record(player_name: String) -> Dictionary:
	return _records.get(player_name, {}).duplicate()


static func _hash(salt: String, password: String) -> String:
	return (salt + password).sha256_text()
