extends SceneTree
## PART 0.14: the alates and the mated queens on the plot, each step made to happen (LESSONS 39: a case that is rare in a
## short run is forced here, not hoped for) - sim/alates.gd, sim/wild_queens.gd.
##   godot --headless --path . --script res://tests/alates_test.gd
## 1. the autumn batch: a colony big and old enough lays it; a smaller one or a tank none
## 2. the spring choice: as many sexual larvae as the spend buys, gynes among them, the first year mostly males
## 3. their larvae eat more, their own chambers (apart), their cocoons bigger; a pupa comes out an alate
## 4. the workers feed the alates from their crops (sugar still the crops' sum), a gyne fattens
## 5. the flight: the ready ones go, a gyne underweight waits and the males with her; some of the gynes come down on the plot
## 6. a queen on the ground walks, then stops; caught: off the plot, her weight kept
## 7. saved and loaded with alates, larvae and queens on the ground: plays on exactly as never stopped
## 8. the wind: the same for the same seed, day and hour; none in a tank

const SIM := "res://scripts/sim/simulation.gd"
var ok := true


func check(what: String, cond: bool) -> void:
	print("  %s  %s" % ["ok  " if cond else "FAIL", what])
	ok = ok and cond


func _ledger_off(s) -> float:
	var c: float = s.queen.crop + s._pending_in
	for w in s.workers:
		c += w.crop
	return absf(c - s.sugar)


func _state(s) -> String:
	var al := ""
	for a in s.alates:
		al += "%s%.6f/%.3f " % [a.x, a.w, a.age]
	var gq := ""
	for q in s.ground_queens:
		gq += "%d@%s " % [q.id, s.WildQueens.pos_of(s, q)]
	var sx := 0
	for l in s.larvae:
		sx += 1 if l.has("x") else 0
	return "tick %d w %d l %d sx %d p %d sugar %.6f rng %d | %s| %s" % [s.tick, s.workers.size(), s.larvae.size(), sx,
		s.pupae.size(), s.sugar, s.rng.state, al, gq]


## Its calendar on to early June (set up in mid-April, which the colony still counts as winter: brood does not grow).
func _to_june(s) -> void:
	s.tick += 55 * s.TPD
	s.climate.doy = s.doy_f()
	s.climate.settle(s.time_of_day(), false)


func _low_limit(s) -> void:
	s.sp = s.sp.duplicate()
	s.sp["colony_max"] = 300.0


func _init() -> void:
	var Sim = load(SIM)
	var A = load("res://scripts/sim/alates.gd")
	var Q = load("res://scripts/sim/wild_queens.gd")
	# (a smaller colony and a lower limit on its own copy of the species: the thresholds - half the limit - at 150 workers;
	# a colony of 1,100 took minutes here)
	var s = Sim.new()
	s.setup(7, 300, false, "wild")
	_low_limit(s)
	_to_june(s)
	for i in 60:
		s.step()

	print("1. the autumn batch")
	s.stats["winters"] = 1
	s.stats["food_mark"] = 0.0
	s.stats.sugar_in = 20000
	var e0: int = s.eggs.size()
	A._autumn_batch(s)
	check("a colony of %d workers before its 2nd winter lays a batch: %d eggs" % [s.workers.size(), s.eggs.size() - e0], s.eggs.size() - e0 > 50)
	var small = Sim.new()
	small.setup(8, 100, false, "wild")
	_low_limit(small)
	small.stats["winters"] = 3
	var e1: int = small.eggs.size()
	A._autumn_batch(small)
	check("100 workers (under half the limit): no batch", small.eggs.size() == e1)
	var tank = Sim.new()
	tank.setup(9, 300, false, "keeper")
	_low_limit(tank)
	tank.stats["winters"] = 3
	for d in 365:
		tank.tick = d * tank.TPD
		A.new_day(tank)
	check("a tank: no batch, no alates all year", tank.eggs.size() == int(9 * 300 / 14.0) and tank.larvae.all(func(l): return not l.has("x")))

	print("2. the spring choice")
	s.stats["winters"] = 2
	s.stats["food_mark"] = 0.0
	s.stats.sugar_in = 30000
	s.stats.protein_in = 0
	A._choose(s)
	var g := 0
	var m := 0
	for l in s.larvae:
		if l.has("x"):
			if l.x == "g": g += 1
			else: m += 1
	check("the first year: %d gynes, %d males (mostly males)" % [g, m], g > 0 and m > g * 5)
	check("no more than %d%% of the larvae" % int(A.LARVAE_MOST * 100), g + m <= int(s.larvae.size() * A.LARVAE_MOST) + 1)
	check("the year counted once", int(s.stats.alate_years) == 1)

	print("3. their larvae")
	var lg: Dictionary = s.larvae.filter(func(l): return l.has("x") and l.x == "g")[0]
	check("a gyne larva eats 3.25x, takes 1.6x as long", A.eat_k(lg) == 3.25 and is_equal_approx(A.larva_k(lg), 1.0 / 1.6))
	for i in 200:
		s.step()
	check("gynes' and males' larvae in chambers of their own: %s" % s.brood_at, s.brood_at.has("g") and s.brood_at.has("m")
		and (s.nest.chambers.size() < 2 or s.brood_at.g != s.brood_at.m))
	var pg := {"p": 0.9995, "s": A.SIZE.g, "c": 0, "x": "g", "q": 1.0}
	s.pupae.append(pg)
	var pm := {"p": 0.9995, "s": A.SIZE.m, "c": 0, "x": "m", "q": 1.0}
	s.pupae.append(pm)
	var a0: int = s.alates.size()
	for i in 400:
		s.step()
	check("two cocoons out: %d alates" % (s.alates.size() - a0), s.alates.size() - a0 == 2)

	print("4. fed in the nest")
	var gy: Dictionary = s.alates.filter(func(a): return a.x == "g")[0]
	var w0: float = gy.w
	for i in s.TPD:
		s.step()
	check("a gyne fattens: %.1f -> %.1f" % [w0, gy.w], gy.w > w0 + 0.5)
	check("sugar is still the crops' sum (off %.9f)" % _ledger_off(s), _ledger_off(s) < 1e-6)

	print("5. the flight")
	for a in s.alates:
		a.age = 20.0
	gy.w = A.GYNE_COST * 0.5
	for i in 6:
		s.alates.append({"x": "g", "w": A.GYNE_COST, "age": 20.0, "h": 0.0, "id": 90000 + i})
	A._fly(s)
	check("the underweight gyne waits, and the male with her; the ready gynes fly: %d left" % s.alates.size(),
		s.alates.size() == 2 and s.alates.any(func(a): return a.x == "m"))
	check("the flight told: %s" % s.stats.get("flight", {}), int(s.stats.flight.g) == 6 and int(s.stats.flight.m) == 0)
	gy.w = A.GYNE_COST
	A._fly(s)
	check("once she is fat enough, both go", s.alates.is_empty() and int(s.stats.flight.g) == 1 and int(s.stats.flight.m) == 1)

	print("6. queens on the ground")
	var gen: RandomNumberGenerator = Q._gen(s, 1)
	var cid: int = s._next_cid
	Q._land(s, gen, 1.1, "area")
	var q: Dictionary = s.ground_queens[-1]
	Q._land(s, gen, 1.0, "area")
	check("her id is her own: the creatures' ids stay (%d -> %d), two queens %d, %d" % [cid, s._next_cid, q.id, s.ground_queens[-1].id],
		s._next_cid == cid and int(s.ground_queens[-1].id) != int(q.id))
	s.ground_queens.pop_back()
	var p0: Vector2 = Q.pos_of(s, q)
	for i in int(s.TPD / 24.0):
		s.step()
	var p1: Vector2 = Q.pos_of(s, q)
	check("she walks: %.1f px in an hour" % p0.distance_to(p1), p0.distance_to(p1) > 1.0 and Q.walking(s, q))
	s.tick += int(s.TPD / 24.0 * 4.5)
	check("then stops to dig", not Q.walking(s, q) and Q.pos_of(s, q) == Q.pos_of(s, q))
	var got: Dictionary = Q.catch(s, int(q.id))
	check("caught: off the plot, her weight %s" % got.get("w"), not s.ground_queens.has(q) and is_equal_approx(float(got.w), 1.1))
	Q._land(s, gen, 0.9, "area")
	s.tick += int(s.TPD / 24.0 * Q.GONE_H) + 30
	Q.step(s)
	check("not caught: gone into the soil after %.0f h" % Q.GONE_H, s.ground_queens.is_empty())

	print("7. saved and loaded")
	Q._land(s, gen, 1.0, "own")
	s.alates.append({"x": "m", "w": A.MALE_COST, "age": 2.0, "h": 0.0, "id": 91000})
	var copy = Sim.new()
	copy.from_dict(bytes_to_var(var_to_bytes(s.to_dict())))
	for i in s.TPD / 2:
		s.step()
		copy.step()
	check("plays on identically", _state(s) == _state(copy))
	if _state(s) != _state(copy):
		print("    ", _state(s), "\n    ", _state(copy))

	print("8. the wind")
	var c = s.climate
	check("the same for the same seed, day and hour", c.wind_at(5, 100, 0.6) == c.wind_at(5, 100, 0.6) and c.wind_at(5, 100, 0.6) != c.wind_at(6, 100, 0.6))
	check("none in a tank", tank.climate.wind_at(5, 100, 0.6) == 0.0)
	print("ALATES TEST PASSED" if ok else "ALATES TEST FAILED")
	quit(0 if ok else 1)
