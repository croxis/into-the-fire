class_name UtilityConsideration
extends Resource
## One consideration in a utility score (UtilityScorer): an input, normalised
## to 0..1 by whoever scores, mapped through a response curve to how good that
## is (0..1). Curves are Godot Curve resources, so they can be edited in the
## Inspector when considerations become .tres files.

## The key of the input it reads.
@export var input: StringName
## Maps the input (0..1) to a score (0..1). None: the input as it is.
@export var curve: Curve
## How much it counts: 1 fully, 0 not at all (a score of 1 either way).
@export_range(0.0, 1.0) var weight := 1.0


## This consideration's score for [param value].
func evaluate(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	var y := clampf(curve.sample(x), 0.0, 1.0) if curve else x
	return lerpf(1.0, y, weight)


## A straight curve from 1 at 0 down to [param low] at 1: the less the better.
static func falling(low: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	c.add_point(Vector2(1.0, low), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return c


## A straight curve from [param low] at 0 up to 1 at 1: the more the better.
static func rising(low: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, low), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	c.add_point(Vector2(1.0, 1.0), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return c
