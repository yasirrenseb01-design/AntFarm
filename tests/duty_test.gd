extends SceneTree
## Duties in the nest (PART EA3a, parts/sim_duties.gd): the same colony gives every ant the same duties run after run;
## the counters move (larvae fed, nestmates fed, hours resting and digging...); the game's catch-up for the time it was
## closed (substep 4, as main_base._run_catchup) runs them too; top_ants() and duty_of() keep the shape the star ants
## panel (ui/parts/hud_stars.gd) reads; the queen can be named and her death is told like a named worker's.
##   godot --headless --path . --script res://tests/duty_test.gd     -> "DUTY TEST PASSED"
const KEYS := ["big", "small", "old", "hurt", "feed_larvae", "carry_brood", "feed_mates", "rest", "dig", "sugar_trips",
	"prey", "corpses", "fights"]


func _run(seed_v: int, days: int, substep: int):
	var Sim = load("res://scripts/sim/simulation.gd")
	var s = Sim.new()
	s.setup(seed_v, 40, false, "wild")
	s.ant_substep = substep
	for i in s.TPD * days:
		s.step()
	return s


func _sig(s) -> String:
	var parts := PackedStringArray()
	for w in s.workers:
		parts.append("%d:%d/%d/%d/%.1f/%.1f/%d" % [w.id, w.duty, w.n_larvae, w.n_mates, w.rest_h, w.dig_h, w.n_brood])
	return ",".join(parts)


func _init():
	var ok := true
	var a = _run(5, 4, 1)
	var b = _run(5, 4, 1)
	var same: bool = _sig(a) == _sig(b) and a.rng.state == b.rng.state
	print("same colony, same duties: %s" % same)
	ok = ok and same
	var sums := {"n_larvae": 0, "n_mates": 0, "rest_h": 0.0, "dig_h": 0.0, "n_brood": 0, "n_sugar": 0}
	var duties := {}
	for w in a.workers:
		for k in sums:
			sums[k] += w.get(k)
		duties[a.DUTY_NAMES[w.duty]] = true
	print("4 days, 40 workers: %s; duties now %s" % [str(sums), str(duties.keys())])
	ok = ok and sums.n_larvae > 0 and sums.rest_h > 0.0 and sums.dig_h > 0.0
	# the catch-up while the game was closed (fast stride) runs the duties too
	var c = _run(5, 4, 4)
	var fed := 0
	for w in c.workers:
		fed += w.n_larvae
	print("catch-up stride: larvae fed %d" % fed)
	ok = ok and fed > 0
	# the larvae are fed one by one: each carries how much of its feeding it got
	var with_f: int = a.larvae.filter(func(l): return l.has("f")).size()
	print("larvae with a feeding share: %d of %d" % [with_f, a.larvae.size()])
	ok = ok and (a.larvae.is_empty() or with_f == a.larvae.size())
	# the shapes the views read
	var tops: Array = a.top_ants()
	var shape_ok := not tops.is_empty()
	for r in tops:
		shape_ok = shape_ok and r.key in KEYS and r.title is String and r.text is String and a.duty_of(r.id).has("duty")
	print("top_ants: %d lines (%s), shape ok %s" % [tops.size(), ", ".join(tops.map(func(r): return r.key)), shape_ok])
	ok = ok and shape_ok and a.duty_of(-99).is_empty()
	# the queen: a name, and her death told like a named worker's
	a.name_queen("  Big Mama  ")
	ok = ok and a.queen.name == "Big Mama"
	a.queen.starve = 999.0
	a._queen(0.01)
	var told: bool = a.log_entries[0].kind == "named" and a.L.entry_text(a.log_entries[0]).contains("Big Mama")
	print("named queen's death told: %s (%s)" % [told, a.L.entry_text(a.log_entries[0])])
	ok = ok and told and not a.queen.alive
	print("DUTY TEST PASSED" if ok else "DUTY TEST FAILED")
	quit()
