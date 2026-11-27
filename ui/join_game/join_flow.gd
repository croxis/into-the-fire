class_name JoinFlow
extends CanvasLayer
## Client: the faction and spawn picker (JoinGame) a player sees on entering a
## world. Only machines with a UI have one (entry.gd); the world itself (Galaxy)
## holds no UI, so dedicated servers run headless. Galaxy says when the player
## may pick and carries the requests and answers over the network.

const JoinGameScene := preload("res://ui/join_game/join_game.tscn")

var galaxy: Galaxy
## The picker (join_game.gd). Hidden until the player may pick.
var menu: Control
var _wanted := false  # The player may pick, but factions may not have arrived yet.


func _init(for_galaxy: Galaxy) -> void:
	galaxy = for_galaxy
	name = "JoinFlow"
	layer = 2


func _ready() -> void:
	menu = JoinGameScene.instantiate()
	menu.visible = false
	add_child(menu)
	menu.request_faction.connect(galaxy.request_spawn_points)
	menu.request_spawn.connect(_on_request_spawn)
	galaxy.ready_to_spawn.connect(_on_ready_to_spawn)
	galaxy.factions_synced.connect(_try_show)
	galaxy.resumed.connect(_on_resumed)
	galaxy.spawn_points_received.connect(menu.show_spawn)


func _on_ready_to_spawn() -> void:
	_wanted = true
	_try_show()


## Shows the picker once it is wanted and there are factions to pick from: on a
## client the server's copy may arrive before or after the player joins.
func _try_show() -> void:
	if not _wanted or not galaxy.factions_ready():
		return
	_wanted = false
	menu.build_faction_menu(galaxy.factions)
	menu.visible = true


func _on_request_spawn(faction_name: String, system_name: String, spawner_name: String) -> void:
	galaxy.request_spawn(faction_name, system_name, spawner_name)
	menu.visible = false


func _on_resumed() -> void:
	_wanted = false
	menu.visible = false
