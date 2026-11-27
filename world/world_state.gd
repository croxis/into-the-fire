class_name WorldState
extends RefCounted
## A world's data as a record, apart from its scene nodes: the part saves and
## the journal will serialize, and that tests can build with no nodes at all.
## Galaxy holds one (Galaxy.state). What lives in nodes (systems, ships, crew)
## and per-machine or per-session state (views, clocks, interest) stay out.
##
## Not serialized yet: the save format is still to be built.

## The world's name (a server's game name).
var game_name := "default"
## Every faction in this world. Clients hold a copy from the server's snapshot
## (WorldReplicator); it is replaced as a whole, never patched from client data.
var factions := FactionRegistry.new()
## Ship and pilot IDs: never reused, so they come from the world.
var ids := WorldIds.new()
## Server: the players this world knows (logins). Empty on clients.
var players := PlayerRecords.new()
