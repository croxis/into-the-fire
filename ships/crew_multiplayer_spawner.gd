extends MultiplayerSpawner

const CREW_SCENE = preload("res://ship_systems/pilots/Pilot.tscn")

func _init() -> void:
	spawn_function = _spawn_crew


func _spawn_crew(data: Dictionary) -> Pilot:
	var crew: Pilot = CREW_SCENE.instantiate()
	crew.multiplayer_id = data["multiplayer_id"]
	crew.name = data["name"]
	crew.get_node("InputsSync").set_multiplayer_authority(data["multiplayer_id"])
	return crew
