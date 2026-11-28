extends Resource

class_name FactionDoctrine
## How a faction's commanders behave (server only; not sent to clients).

## Fighters a commander wants out on patrol at no threat (CommanderPatrol).
@export var minimum_patrol_fighters: int = 0
## Extra fighters wanted per unit of threat (ThreatAssessment).
@export var fighters_per_threat: int = 0
## How far from their ship a commander's patrol flies, and fighters within it
## count as out, in metres.
@export var patrol_radius: float = 20000.0
@export var retreat_when_hull_percent: float = 0
@export var intercept_range: float = 5000
