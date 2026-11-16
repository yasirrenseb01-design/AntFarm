extends SceneTree
## PART 0.13 step 4: the queen fed mouth to mouth by her attendants, and laying as far as she is fed
## (parts/sim_duties.gd _tend_queen/_feed_queen, parts/sim_brood.gd _queen; R8-R10 of docs/roadmap/PLAN_CROP.md)
##  1. crops held below QUEEN_FROM (the attendants have nothing spare): what the queen is given (queen.fed) halves within
##     7 days, and she lays at most half what the same colony held well fed lays, within 10 days
##  2. fed again: queen.fed and her laying come back within 10 days
##  3. nobody can feed her (every crop and every fat body held empty): she lives off her own body, alive after 12 days
##  4. a nurse with an empty crop: its larvae get prey alone (half a feeding), with honeydew a whole one
## (the numbers are the plan's checks that the mechanism works, chosen)
##   godot --headless --path . --script res://tests/queen_feed_test.gd

const Sim := preload("res://scripts/sim/simulation.gd")
var ok := true


func _check(what: String, good: bool) -> void:
	print(("  ok    " if good else "  FAIL  ") + what)
	ok = ok and good


## Every worker's crop held at `f` of full (fat too when `fat` is given), the prey plentiful.
func _hold(s, f: float, fat := -1.0) -> void:
	for a in s.workers:
		a.crop = s.crop_cap() * f
		if fat >= 0.0:
			a.body_fat = fat
	s._pending_in = 0.0
	s.ledger_count()
	s.protein = s.protein_cap()


## `days` days with the crops held at `f`: [eggs laid, queen.fed at the end].
func _run(s, days: int, f: float, seen: Array) -> Array:
	var laid := 0
	for i in days * s.TPD:
		if i % 20 == 0:
			_hold(s, f)
		s.step()
		for e in s.events:
			if e.n > seen[0]:
				seen[0] = e.n
				if e.k == "egg":
					laid += 1
	return [laid, float(s.queen.fed)]


func _colony():
	var s := Sim.new()
	s.setup(7, 60, false, "keeper")
	return s


func _init() -> void:
	var fed = _colony()
	var cut = _colony()
	var sf := [0]
	var sc := [0]
	_run(fed, 5, 0.7, sf)
	var before := _run(cut, 5, 0.7, sc)
	# 1. cut: crops at 20% (under QUEEN_FROM 30%), against the same colony still fed
	var c7 := _run(cut, 7, 0.2, sc)
	var f7 := _run(fed, 7, 0.7, sf)
	var c3 := _run(cut, 3, 0.2, sc)
	var f3 := _run(fed, 3, 0.7, sf)
	_check("crops cut to 20%%: queen given %.2f -> %.2f a day in 7 days (<= half)" % [before[1], c7[1]], c7[1] <= before[1] * 0.5)
	_check("...laying on days 8-10: %d eggs against %d well fed (<= half)" % [c3[0], f3[0]], f3[0] > 0 and c3[0] <= f3[0] * 0.5)
	# 2. fed again
	var r7 := _run(cut, 7, 0.7, sc)
	var g7 := _run(fed, 7, 0.7, sf)
	var r3 := _run(cut, 3, 0.7, sc)
	var g3 := _run(fed, 3, 0.7, sf)
	_check("fed again: queen given %.2f a day after 7 days (>= 80%% of %.2f well fed)" % [r7[1], g7[1]], r7[1] >= g7[1] * 0.8)
	_check("...laying on days 8-10: %d eggs against %d well fed (>= half)" % [r3[0], g3[0]], r3[0] >= g3[0] * 0.5)
	# 3. nobody can feed her
	var s = _colony()
	s.queen.reserve = 20.0
	s.queen.crop = 0.0
	for i in 12 * s.TPD:
		if i % 20 == 0:
			_hold(s, 0.0, 0.0)
		s.step()
	_check("no food anywhere for 12 days: the queen alive on her body (reserve 20 -> %.1f)" % s.queen.reserve,
		s.queen.alive and s.queen.reserve < 20.0)
	# 4. a nurse's crop and its larvae
	var n = _colony()
	for i in 3 * n.TPD:
		n.step()
	var got := []
	for f in [0.0, 0.8]:
		_hold(n, f)
		n._duties()                          # (60 workers: the queen feeds no larvae herself)
		var fs := []
		for l in n.larvae:
			if float(l.get("f", 0.0)) > 0.0:
				fs.append(float(l.f))
		got.append(fs)
	_check("larvae fed by empty crops: %d, all at 0.5; by full crops: %d, all at 1" % [got[0].size(), got[1].size()],
		not got[0].is_empty() and got[0].all(func(x): return absf(x - 0.5) < 1e-6)
		and not got[1].is_empty() and got[1].all(func(x): return absf(x - 1.0) < 1e-6))
	print("QUEEN FEED TEST PASSED" if ok else "QUEEN FEED TEST FAILED")
	quit()
