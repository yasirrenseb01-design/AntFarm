extends SceneTree
## PART 0.13: each worker's own crop and body fat (parts/sim_crops.gd, since v0.13.1 the food itself).
##  1. the colony's sugar and fat are the sums of what the ants hold (+ the queen's crop and the honeydew at the entrance),
##     every day, and nothing is made or lost: each day the sums change by what came home less what was eaten (±1e-6)
##  2. honeydew flows from full crops to empty ones: 50 workers, one with a full crop, 3 duty rounds -> at least 10 fed;
##     loads regurgitated at the entrance go to the emptiest
##  3. no crop over the cap, none below 0
##   godot --headless --path . --script res://tests/crop_ledger_test.gd [-- long]
## (quick: ~1 minute, in tools/check.ps1 -Quick; long: the colonies of 14 and ~300 for 100 days, the full check)

const Sim := preload("res://scripts/sim/simulation.gd")
const TOL := 1e-6
var ok := true


func _sums(s) -> Array:      # [sugar, fat] (not a Vector2: 32-bit floats)
	var c: float = s.queen.crop + s._pending_in
	var f := 0.0
	var cap: float = s.crop_cap()
	for w in s.workers:
		c += w.crop
		f += w.body_fat
		if w.crop < -1e-9 or w.body_fat < -1e-9 or w.crop > cap + 1e-9:
			return [INF, INF]
	return [c, f]


func _check(what: String, good: bool) -> void:
	print(("  ok    " if good else "  FAIL  ") + what)
	ok = ok and good


func _run(start: int, scen: String, days: int) -> void:
	var s := Sim.new()
	s.setup(5, start, false, scen)
	var worst_sum := 0.0
	var worst_flow := 0.0
	var min_w := 1 << 30
	var max_w := 0
	for d in days:
		var was: float = s.sugar + s.fat
		s.food_in = 0.0
		s.food_eaten = 0.0
		for i in s.TPD:
			s.step()
		if d % 3 == 0 and scen == "keeper":
			s.auto_care(d)
		var sm := _sums(s)
		worst_sum = maxf(worst_sum, maxf(absf(sm[0] - s.sugar), absf(sm[1] - s.fat)))
		if s.workers.size() > 0:
			worst_flow = maxf(worst_flow, absf(s.sugar + s.fat - (was + s.food_in - s.food_eaten)))
		min_w = mini(min_w, s.workers.size())
		max_w = maxi(max_w, s.workers.size())
	_check("start=%d %s %d days  workers %d..%d  worst |sums - sugar,fat| %.9f  |change - (in - eaten)| %.9f  sugar %.2f fat %.2f" % [
		start, scen, days, min_w, max_w, worst_sum, worst_flow, s.sugar, s.fat], worst_sum < TOL and worst_flow < TOL and max_w > 0)


func _flow() -> void:
	var s := Sim.new()
	s.setup(7, 50, false, "keeper")
	for a in s.workers:
		a.state = 0                # (Ant.IN_NEST: every one inside)
		a.crop = 0.0
	s.outside.clear()
	s.queen.crop = 0.0
	s._pending_in = 0.0
	s._unloaded.clear()
	s.workers[17].crop = s.crop_cap()
	s.ledger_count()
	var total: float = s.sugar
	for r in 3:
		s._duties()
	var fed := 0
	for a in s.workers:
		if a.crop > 0.01:
			fed += 1
	_check("one full crop in 50, 3 duty rounds: %d have honeydew (>= 10), sugar %.6f -> %.6f" % [fed, total, _sums(s)[0]],
		fed >= 10 and absf(_sums(s)[0] - total) < TOL)
	# loads at the entrance: to the emptiest first
	for a in s.workers:
		a.crop = 1.0
	s.workers[3].crop = 0.0
	s.workers[40].crop = 0.2
	s._pending_in = 1.8
	s.ledger_count()
	total = s.sugar
	s._duties()
	_check("honeydew at the entrance to the emptiest: %.2f, %.2f; left %.3f" % [s.workers[3].crop, s.workers[40].crop, s._pending_in],
		s.workers[3].crop > 1.0 and s.workers[40].crop > 0.2 and s._pending_in < 1e-9 and absf(_sums(s)[0] - total) < TOL)


func _init() -> void:
	var long: bool = "long" in OS.get_cmdline_user_args()
	if long:
		for c in [[14, "keeper", 100], [300, "keeper", 100], [14, "wild", 100]]:
			_run(c[0], c[1], c[2])
	else:
		for c in [[14, "keeper", 40], [300, "keeper", 6], [14, "wild", 25]]:
			_run(c[0], c[1], c[2])
	_flow()
	var t := Sim.new()
	t.setup(7, 14, false, "keeper")
	t.ledger_set_sugar(3.5)
	_check("ledger_set_sugar(3.5): sums %.9f" % _sums(t)[0], absf(_sums(t)[0] - 3.5) < TOL and absf(t.sugar - 3.5) < TOL)
	print("CROP LEDGER TEST PASSED" if ok else "CROP LEDGER TEST FAILED")
	quit(0 if ok else 1)
