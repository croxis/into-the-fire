class_name UtilityScorer
extends RefCounted
## Utility AI, small and our own (the Godot addons are unmaintained; design
## doc): an option's score is the product of its considerations' scores, so
## any one near 0 rules it out. Agents score their options this way and take
## the best; behaviour trees carry the choice out.


## The score (0..1) of [param considerations] (UtilityConsideration) for
## [param inputs] (input name -> value, 0..1). A missing input counts as 0.
static func score(considerations: Array, inputs: Dictionary) -> float:
	var total := 1.0
	for c: UtilityConsideration in considerations:
		total *= c.evaluate(inputs.get(c.input, 0.0))
	return total
