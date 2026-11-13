extends SceneTree
## PART 0.13 step 3: the workers go out by their own crops (parts/sim_colony.gd _colony, R4-R7 of docs/roadmap/PLAN_CROP.md)
##  1. a forager home with honeydew: the nestmates take all of it (but its own ration) while the colony's crops are
##     half empty or more, little when they are nearly full - then it keeps the rest in its own crop
##  2. R7: an empty forager brings home ~35% more a trip than a full one
##  3. the share of workers out follows how full the crops are: held at 20% full -> >= 35% out, at 90% -> <= 15%
##     (the numbers are the plan's check that the rule works, chosen; prey kept plentiful so only the crops count)
##   godot --headless --path . --script res://tests/forage_hunger_test.gd

const Sim := preload("res://scripts/sim/simulation.gd")
var ok := true


func _check(what: String, good: bool) -> void:
	print(("  ok    " if good else "  FAIL  ") + what)
	ok = ok and good


func _fill_all(s, f: float) -> void:
	for a in s.workers:
		a.crop = s.crop_cap() * f
	s.queen.crop = 0.0
	s._pending_in = 0.0
	s.ledger_count()


func _arrive_at(f: float) -> Array:      # [given to the entrance, kept by the forager] of one load
	var s := Sim.new()
	s.setup(7, 100, false, "keeper")
	_fill_all(s, f)
	var a = s.workers[3]
	a.crop = 0.0
	s.ledger_count()
	var before: float = s._pending_in
	var c0: float = a.crop
	s.ledger_arrive(a, s.sugar + 1.0)
	return [s._pending_in - before, a.crop - c0]


func _out_share(f: float) -> float:
	var s := Sim.new()
	s.setup(11, 200, false, "keeper")
	s.protein = s.protein_cap()
	var sum := 0.0
	var n := 0
	for i in 6000:
		if i % 20 == 0:
			_fill_all(s, f)
			s.protein = s.protein_cap()
		s.step()
		if i > 2000 and i % 20 == 0 and s.activity > 0.8:
			sum += float(s.out_count) / s.workers.size()
			n += 1
	return sum / maxf(1.0, n)


func _init() -> void:
	var lo := _arrive_at(0.2)
	var hi := _arrive_at(0.95)
	_check("a load home, crops 20%% full: %.2f given, %.2f kept (all but its own ration given)" % lo,
		absf(lo[0] - 0.25) < 1e-6 and absf(lo[1] - 0.75) < 1e-6)
	_check("a load home, crops 95%% full: %.2f given, %.2f kept (most kept)" % hi, hi[0] < 0.1 and hi[1] > 0.9)
	var s := Sim.new()
	s.setup(7, 20, false, "keeper")
	var w = s.workers[0]
	w.crop = 0.0
	var empty_load: float = s.sugar_load(w)
	w.crop = s.crop_cap()
	_check("R7 load: empty crop %.2f, full crop %.2f" % [empty_load, s.sugar_load(w)],
		absf(empty_load - 1.35) < 1e-6 and absf(s.sugar_load(w) - 1.0) < 1e-6)
	var o_lo := _out_share(0.2)
	var o_hi := _out_share(0.9)
	_check("workers out in the active hours: crops 20%% full %.0f%% (>= 35), 90%% full %.0f%% (<= 15)" % [o_lo * 100.0, o_hi * 100.0],
		o_lo >= 0.35 and o_hi <= 0.15)
	print("FORAGE HUNGER TEST PASSED" if ok else "FORAGE HUNGER TEST FAILED")
	quit()
