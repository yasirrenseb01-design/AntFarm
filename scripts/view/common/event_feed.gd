extends RefCounted
## One view's reader of the simulation's recent moments (sim.events: {"n", "k", "s"}). Each view that
## acts moments out keeps its own feed, so the nest, the outworld and later the fights do not miss or
## replay each other's events. The simulation keeps only the last few, so a view that falls far
## behind simply skips the older ones.

var sim
var _seen := 0


func _init(s) -> void:
	sim = s
	_seen = s.event_seq


## Forget what happened while the view was not watching.
func skip() -> void:
	_seen = sim.event_seq


## Events since the last call, oldest first.
func take() -> Array:
	var out := []
	for e in sim.events:
		if e.n > _seen:
			out.append(e)
	_seen = sim.event_seq
	return out
