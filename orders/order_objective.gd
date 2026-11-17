extends Resource
class_name OrderObjective

enum ObjectiveType {
	CAPTURE,
	COLLECT,
	CUSTOM,
	DEFEND,
	DESTROY,
	DISABLE,
	DOCK,
	EXPLORE,
	FORMATION_CHANGE,
	LAUNCH,
	PATROL,
	REACH_LOCATION,
	REPAIR,
	RETREAT,
	TRADE,
}

@export var id: int = 0
@export var description: String = ""
@export var type: ObjectiveType = ObjectiveType.CUSTOM
@export var target_id: int = -1  # Item id, npc id, player id, system_id
@export var target_system: String = ""
@export var target_location: Vector3 = Vector3()
@export var target_radius: float = 0.0  # Size of target, if to fly to specific location
@export var target_count: int = 0  # How many
@export var is_optional: bool = false
@export var prereq_objective: Array[OrderObjective] = []
@export var is_completed: bool = false
