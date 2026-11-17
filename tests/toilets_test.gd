extends SceneTree
## PART 0.13 step 7: the nest's toilets (scripts/sim/toilets.gd)
##  1. a 14-worker nest, 60 days: at least one toilet, in a chamber corner (a floor cell with soil on >= CORNER of the 8
##     cells round it and open space over it), in a chamber the queen and the brood are not kept in (the nest has more)
##  2. what the toilets hold is the waste counted, no more (the first days' waste comes before the first toilet)
##  3. the waste is only what the workers ate inside: never more than the colony ate
##  4. the same every run, and a saved and loaded colony goes on with the same toilets
##  5. a changed save (wrong kinds, too many rows) loads as no toilets or as many as are good, never an error
##   godot --headless --path . --script res://tests/toilets_test.gd

const Sim := preload("res://scripts/sim/simulation.gd")
var ok := true


func _check(what: String, good: bool) -> void:
	print(("  ok    " if good else "  FAIL  ") + what)
	ok = ok and good


func _run(days: int) -> Sim:
	var s := Sim.new()
	s.setup(3, 14, false, "keeper")
	for i in days * s.TPD:
		s.step()
	return s


func _rows(s) -> String:
	return str(s.toilets.to_save())


func _init() -> void:
	var s := _run(60)
	var t = s.toilets
	_check("toilets made: %d (%s)" % [t.patches.size(), _rows(s)], t.patches.size() >= 1)
	var busy := [s.queen_at, int(s.brood_at.larvae), int(s.brood_at.pupae)]
	for p in t.patches:
		if p.old:
			continue
		var sc: int = t._score(s.nest, p.c)
		_check("toilet %s in a corner: %d of 8 round it soil" % [p.c, sc], sc >= t.CORNER)
		_check("toilet in chamber %d, not where the queen or brood is (%s)" % [p.ch, busy], s.nest.chambers.size() == 1 or not int(p.ch) in busy)
	var held := 0.0
	for p in t.patches:
		held += float(p.amt)
	_check("held %.2f <= counted %.2f (and most of it: %.0f%%)" % [held, t.total, 100.0 * held / maxf(t.total, 0.001)],
		held <= t.total + 1e-6 and held > 0.5 * t.total)
	_check("waste %.2f <= what the colony ate %.2f" % [t.total, s.food_eaten], t.total <= s.food_eaten + 1e-6)

	var s2 := _run(60)
	_check("the same every run", _rows(s2) == _rows(s))
	var loaded := Sim.new()
	loaded.from_dict(bytes_to_var(var_to_bytes(s.to_dict())))     # (through bytes, as a save: else they share lists)
	_check("saved and loaded: the same toilets", _rows(loaded) == _rows(s))
	for i in 10 * s.TPD:
		s.step()
		loaded.step()
	_check("ten days on: the same after loading", _rows(loaded) == _rows(s))

	var junk := Sim.new()
	junk.setup(1, 14, false, "keeper")
	var d := junk.to_dict()
	for bad in [42, {"patches": "x"}, {"patches": [[1, 2, 3]], "due": "a"}, {"patches": [[1, 2, 3, 4.0, 0, 0], ["a", 2, 3, 4, 0, 0]]},
			{"patches": range(30).map(func(k): return [k, 1, 1, 1.0, 0, 0])}]:
		d["toilets"] = bad
		junk.from_dict(d)
		_check("changed save %s... -> %d toilets" % [str(bad).left(30), junk.toilets.patches.size()], junk.toilets.patches.size() <= junk.toilets.MAX_KEPT)
	print("TOILETS TEST PASSED" if ok else "TOILETS TEST FAILED")
	quit()
