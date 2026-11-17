extends Resource
class_name OrderData

enum OrderState {
	INACTIVE,
	IN_PROGRESS,
	COMPLETED,
	FAILED,
	CANCELLED
}

enum OrderTypes {
	ANY,
	CONSTRUCTION,
	ECONOMIC,
	MILITARY,
}

@export var id: int = -1
@export var type: OrderTypes = OrderTypes.ANY # -1 means no specific type
#@export var fail_conditions: Need to think of a type for failed missions
@export var objectives: Array[OrderObjective] = []
#@expport var prereq_conditions: Need to think of types for being able to get the quest
@export var time_limit: int = 0 # 0 is no limit
@export var time_duration: int = 0
@export var faction_id: int = -1  # What faction can "see" the order
@export var recursive: bool = true  # Can 
