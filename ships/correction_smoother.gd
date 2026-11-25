class_name CorrectionSmoother
extends RefCounted
## Eases server corrections of the pilot's own ship (netcode slice N4a). No
## nodes: Ship calls apply() each time it reconciles.
##
## When the server's state shows our prediction was off (a hold or skip on a
## bad link, a collision), the ship could jump to the corrected place at once.
## At speed that is a visible hitch. Instead the ship is put only part of the
## way there, and the rest of the gap (the offset) shrinks with every state
## after: KEEP of it is left each time, so a correction has mostly eased out
## within about 100 ms.
##
## Only the ship's position lags. Its velocity and rotation are the truth at
## once, and prediction always replays from the server's state, so the offset
## never builds up. Rotation can't lag: thrust follows the way the ship points,
## so a ship turned even slightly off the truth would thrust off the truth's
## line and need a new correction every tick. Position doesn't change thrust.
## The cost: for those few ticks the body (and its collisions) is slightly off
## the truth. The server decides collisions, so that's harmless.
##
## The ship's model and camera sit directly under its physics body, so the body
## itself is what eases. A separate visual node would need every ship scene
## restructured.

## Share of the offset left after each state from the server (about one a tick):
## 0.7^6 is about 12%, so 100 ms.
const KEEP := 0.7
## Offsets beyond this snap at once (the launch, a teleport): easing a jump that
## big would only drag the ship visibly across space.
const SNAP_DISTANCE := 100.0  # m

## How far the truth moved from where we expected it, at the last apply(), in
## metres. The offset easing out doesn't count: it's an old correction.
var last_correction := 0.0

var _offset := Vector3.ZERO  # Shown minus truth, world space.


## Where to put the ship, given where it is [param shown] and where the server
## says it is [param truth] (both now).
func apply(shown: Transform3D, truth: Transform3D) -> Transform3D:
	var gap := shown.origin - truth.origin
	last_correction = (gap - _offset).length()
	if gap.length() > SNAP_DISTANCE:
		reset()
		return truth
	_offset = gap * KEEP
	return Transform3D(truth.basis, truth.origin + _offset)


## Forget any offset (say the ship was placed by the server outright).
func reset() -> void:
	_offset = Vector3.ZERO
