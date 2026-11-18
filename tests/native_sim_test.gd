extends SceneTree
## The foragers' walk in C++ (native/src/forager_*.cpp, PART 0.14 v0.14.1) against the GDScript it was written from:
##   1. its random generator: the engine's draws from the same states, every bit (rng_probe)
##   2. its sums: cos, sin, exp, pow, wrapf, Vector2 angle/normalized/lerp on many numbers, every bit (math_probe)
##   3. whole colonies stepped twice from the same start - the C++ walking the foragers, and the GDScript (native_off) -
##      the saved state compared every few hours of game time, keeper and wild, at substeps 1 and 4
##   godot --headless --path . --script res://tests/native_sim_test.gd [-- long]   -> "NATIVE SIM TEST PASSED"
## (no C++ part here: nothing to compare - passes, saying so)

var ok := true


func _init() -> void:
	if not ClassDB.class_exists("ForagerStep"):
		print("no ForagerStep (no dll here): the game walks the foragers in GDScript")
		print("NATIVE SIM TEST PASSED")
		quit()
		return
	var long := OS.get_cmdline_user_args().has("long")
	_rng_check()
	_math_check()
	# scenario, workers, seed, substep, days (long: more days)
	var runs := [["keeper", 300, 3, 1, 1.0], ["keeper", 300, 3, 4, 1.0], ["wild", 300, 4, 1, 1.0], ["wild", 300, 4, 4, 1.0],
		["keeper", 14, 5, 1, 2.0], ["wild", 60, 7, 1, 3.0], ["keeper", 1200, 6, 1, 0.5], ["keeper", 300, 8, 1, 2.0, "starve"],
		["keeper", 300, 9, 1, 2.0, "dry"]]
	if long:
		runs += [["wild", 600, 11, 1, 6.0], ["keeper", 600, 12, 4, 6.0], ["wild", 200, 13, 4, 10.0], ["keeper", 200, 14, 1, 10.0]]
	for r in runs:
		_sim_check(r[0], r[1], r[2], r[3], r[4], r[5] if r.size() > 5 else "")
	print("NATIVE SIM TEST PASSED" if ok else "NATIVE SIM TEST FAILED")
	quit()


func _rng_check() -> void:
	var g := RandomNumberGenerator.new()
	var pick := RandomNumberGenerator.new()
	pick.seed = 99
	var bad := 0
	var n := 0
	for t in 40:
		g.seed = 1000 + t * 7919
		var st0: int = g.state
		var kinds := PackedInt32Array()
		for i in 5000:
			kinds.append(pick.randi() % 5)
		var want := PackedFloat64Array()
		for k in kinds:
			match k:
				0: want.append(g.randf())
				1: want.append(g.randf_range(-0.16, 0.16))
				2: want.append(g.randi_range(10, 30))
				3: want.append(g.randi_range(90, 220))
				_: want.append(g.randi())
		want.append(g.state)
		var got: PackedFloat64Array = ClassDB.class_call_static("ForagerStep", "rng_probe", st0, kinds)
		n += want.size()
		if got != want:
			bad += 1
			if bad <= 3:
				for i in want.size():
					if got[i] != want[i]:
						print("  rng: state %d draw %d kind %d: C++ %s, engine %s" % [st0, i, kinds[mini(i, kinds.size() - 1)], got[i], want[i]])
						break
	print("rng: %d draws from 40 states, %d sequences differ" % [n, bad])
	ok = ok and bad == 0


func _math_check() -> void:
	var g := RandomNumberGenerator.new()
	g.seed = 7
	var inp := PackedFloat64Array()
	for i in 40000:
		var a: float
		var b: float
		match i % 5:
			4:
				a = g.randf_range(-600.0, 600.0)                 # nearly along an axis: Vector2.angle() near 0 or PI
				b = a * g.randf_range(-0.001, 0.001)            # (v0.14.1: the compiler's atan2f differed there)
			0:
				a = g.randf_range(-12.0, 12.0)                   # angles
				b = g.randf_range(0.0, 3.0)                      # speeds
			1:
				a = g.randf_range(-30.0, 0.5)                    # exp(clock - stamp)
				b = 2.0
			2:
				a = g.randf_range(0.0, 1.0)                      # pow(1 - k, substep), pow(r + 2 + spd, 2)
				b = float(g.randi_range(1, 8))
			_:
				a = g.randf_range(-1200.0, 1200.0)               # positions, differences
				b = g.randf_range(-750.0, 750.0)
		inp.append(a)
		inp.append(b)
	var got: PackedFloat64Array = ClassDB.class_call_static("ForagerStep", "math_probe", inp)
	var want := PackedFloat64Array()
	for i in range(0, inp.size(), 2):
		var a := inp[i]
		var b := inp[i + 1]
		want.append(cos(a))
		want.append(sin(a))
		want.append(exp(a))
		want.append(pow(a, b))
		want.append(wrapf(a, -PI, PI))
		want.append(Vector2(a, b).angle())
		var nz := Vector2(a, b).normalized() * 6.0
		want.append(nz.x)
		want.append(nz.y)
		var lp := Vector2(a, b).lerp(Vector2(b, a), 0.5)
		want.append(lp.x)
		want.append(lp.y)
		var st := Vector2(a, b) + Vector2(cos(a), sin(a)) * b
		want.append(st.x)
		want.append(st.y)
	var bad := 0
	var per := {}
	var names := ["cos", "sin", "exp", "pow", "wrapf", "angle", "norm.x", "norm.y", "lerp.x", "lerp.y", "step.x", "step.y"]
	for i in want.size():
		# (NaN != NaN: pow of a negative base - not a sum the walk does)
		if got[i] != want[i] and not (is_nan(got[i]) and is_nan(want[i])):
			bad += 1
			per[names[i % 12]] = per.get(names[i % 12], 0) + 1
			if bad <= 5:
				print("  math %s(%s, %s): C++ %s, GDScript %s" % [names[i % 12], inp[(i / 12) * 2], inp[(i / 12) * 2 + 1], got[i], want[i]])
	print("math: %d results, %d differ %s" % [want.size(), bad, per])
	ok = ok and bad == 0 and got.size() == want.size()


## neglect: "starve" (crops and fat emptied, no food given: deaths of hunger), "dry" (the nest dried out, no water:
## deaths of thirst) - LESSONS 39: the rare ends made to happen, not hoped for
func _sim_check(scen: String, workers: int, seed: int, sub: int, days: float, neglect := "") -> void:
	var Sim = load("res://scripts/sim/simulation.gd")
	var sims := []
	for native in [true, false]:
		var s = Sim.new()
		s.native_off = not native
		s.setup(seed, workers, false, scen)
		s.sp = s.sp.duplicate(true)
		s.sp["colony_max"] = maxf(float(s.sp["colony_max"]), workers * 1.5)
		s.ant_substep = sub
		# (low energy to start, spread by id: else hunger or thirst takes ~6-7 game days to kill one)
		if neglect != "":
			for w in s.workers:
				w.energy = 0.02 + 0.3 * float(w.id % 17) / 17.0
		if neglect == "starve":
			for w in s.workers:
				w.crop = 0.0
				w.body_fat = 0.0
			s.foods.clear()
			s._food_dirty = true
			s.ledger_count()
		elif neglect == "dry":
			s.water = 0.0
		sims.append(s)
	var every := 600
	var ticks := int(days * Sim.TPD)
	var t := 0
	var first_bad := -1
	var t_nat := 0
	var t_gd := 0
	while t < ticks:
		for k in every:
			if neglect == "dry":
				for s in sims:
					s.humidity = 0.05                # (kept dry: the same in both)
			var t0 := Time.get_ticks_usec()
			sims[0].step()
			var t1 := Time.get_ticks_usec()
			sims[1].step()
			t_nat += t1 - t0
			t_gd += Time.get_ticks_usec() - t1
			if sims[0].tick % Sim.TPD == 0 and neglect == "":
				for s in sims:
					s.auto_care(s.tick / Sim.TPD)
		t += every
		if var_to_bytes(sims[0].to_dict()) != var_to_bytes(sims[1].to_dict()):
			first_bad = sims[0].tick
			break
	var walked: int = sims[0].prof.get("native", 0)
	var died: Dictionary = sims[0].stats.dead_by
	var all_steps: int = sims[0].prof.get("steps", 0)
	var same := first_bad < 0
	print("%s %d workers seed %d substep %d, %.1f days%s: %s  (C++ walked %d of %d forager steps; step %.3f ms C++, %.3f GDScript; died %s)" % [
		scen, workers, seed, sub, days, " " + neglect if neglect != "" else "", "identical" if same else "DIFFER from tick %d" % first_bad,
		walked, all_steps, t_nat / 1000.0 / maxi(1, t), t_gd / 1000.0 / maxi(1, t), died])
	if not same:
		_where(sims[0].to_dict(), sims[1].to_dict(), "")
	ok = ok and same and walked > all_steps / 2
	# the forced ends must have happened (else the run proves nothing about them)
	if neglect == "starve" and int(died.get("starve", 0)) == 0 or neglect == "dry" and int(died.get("thirst", 0)) == 0:
		print("  (no %s deaths: the case did not happen)" % neglect)
		ok = false


## The first keys at which two saved states differ (to say where to look).
func _where(a, b, path: String, shown := [0]) -> void:
	if shown[0] >= 6:
		return
	if a is Dictionary and b is Dictionary:
		for k in a:
			if not b.has(k) or var_to_bytes(a[k]) != var_to_bytes(b[k]):
				_where(a[k], b.get(k), path + "/" + str(k), shown)
	elif a is Array and b is Array and a.size() == b.size():
		for i in a.size():
			if var_to_bytes(a[i]) != var_to_bytes(b[i]):
				_where(a[i], b[i], path + "[%d]" % i, shown)
				if shown[0] >= 6:
					return
	else:
		shown[0] += 1
		print("    %s: C++ %s / GDScript %s" % [path, str(a).left(120), str(b).left(120)])
