extends MultiplayerSpawner

const CREW_SCENE = preload("res://characters/character.tscn")

func _init() -> void:
	spawn_function = _spawn_crew


func _spawn_crew(data: Dictionary) -> Character:
	var crew: Character = CREW_SCENE.instantiate()
	crew.restore(data)
	crew.get_node("InputsSync").set_multiplayer_authority(data["multiplayer_id"])
	return crew
