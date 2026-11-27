class_name WorldReplicator
extends Node
## What a client is told about the world besides the ships and crews its
## spawners bring (those go by interest management, network/). On join the
## server sends a snapshot (snapshot_of), which replaces the client's copy as a
## whole; it is never patched from client data. A child of Galaxy on server and
## clients alike, since an RPC needs the same node path on both.
##
## Events after the snapshot: none yet. The only world data clients hold are
## factions, and nothing they read from them changes after the world is built
## (members and leaders change, but only the server reads them). A change
## clients must see goes here as an event, so this stays the one place that
## decides what each peer is told about the world.

## Bumped whenever the snapshot's layout changes: a client refuses another one.
const SNAPSHOT_VERSION := 1

## Client: a snapshot arrived and replaced the local world copy.
signal snapshot_received()

var _galaxy: Galaxy
var _synced := false  # Client: a snapshot has arrived.


func _init(galaxy: Galaxy) -> void:
	_galaxy = galaxy
	name = "WorldReplicator"


## The snapshot a joining client gets: plain dictionaries, not objects (those
## can't be sent). [param factions]: the server's registry.
static func snapshot_of(factions: FactionRegistry) -> Dictionary:
	return {"version": SNAPSHOT_VERSION, "factions": factions.to_data()}


## True once this machine has the world to show: the server's own, or on a
## client the snapshot the server sent.
func world_ready() -> bool:
	return multiplayer.is_server() or _synced


## Server: sends [param peer] the world as it is now. Before anything that
## spawns ships there: a ship finds its faction in this copy.
func send_snapshot(peer: int) -> void:
	_receive_snapshot.rpc_id(peer, snapshot_of(_galaxy.factions))


## "authority": only the server may send it, so a client can't push a world
## to other peers.
@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(data: Dictionary) -> void:
	apply_snapshot(data)


## Client: replaces the local world copy with [param data] (snapshot_of).
func apply_snapshot(data: Dictionary) -> void:
	var version: int = data.get("version", 0)
	if version != SNAPSHOT_VERSION:
		Log.log(["World snapshot version ", version, " refused: this game reads ", SNAPSHOT_VERSION],
				Log.MessageType.ERROR)
		return
	_galaxy.factions = FactionRegistry.from_data(data.get("factions", {}))
	_synced = true
	Log.log(["Received ", _galaxy.factions.size(), " factions from server"], Log.MessageType.INFO)
	snapshot_received.emit()
