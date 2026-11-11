extends SceneTree
## PART 0.13 step 1: each worker's share of the colony's sugar and fat (Ant.crop, Ant.body_fat, queen.crop) is a ledger kept
## equal to the colony's sums, every day, in colonies of 14 and ~300 workers over 100 days (parts/sim_crops.gd).
##   godot --headless --path . --script res://tests/crop_ledger_test.gd

const Sim := preload("res://scripts/sim/simulation.gd")
const TOL := 1e-6


func _off(s) -> Vector2:
	var c: float = s.queen.crop
	var f := 0.0
	for w in s.workers:
		c += w.crop
		f += w.body_fat
		if w.crop < -1e-9 or w.body_fat < -1e-9:
			return Vector2(INF, INF)
	return Vector2(absf(c - s.sugar), absf(f - s.fat))


func _init() -> void:
	var ok := true
	for case in [[14, "keeper"], [300, "keeper"], [14, "wild"]]:
		var s := Sim.new()
		s.setup(5, case[0], false, case[1])
		var worst := _off(s)
		var days := 100
		var min_w := 1 << 30
		var max_w := 0
		for d in days:
			for i in s.TPD:
				s.step()
			if d % 3 == 0 and case[1] == "keeper":
				s.auto_care(d)
			var o := _off(s)
			worst = Vector2(maxf(worst.x, o.x), maxf(worst.y, o.y))
			min_w = mini(min_w, s.workers.size())
			max_w = maxi(max_w, s.workers.size())
		var pass_case: bool = worst.x < TOL and worst.y < TOL and max_w > 0
		print("start=%d %s  %d days  workers %d..%d  worst |crops - sugar| %.9f  |body_fat - fat| %.9f  sugar %.2f fat %.2f  %s" % [
			case[0], case[1], days, min_w, max_w, worst.x, worst.y, s.sugar, s.fat, "ok" if pass_case else "OFF"])
		ok = ok and pass_case
	# the dev setter spreads over the colony
	var t := Sim.new()
	t.setup(7, 14, false, "keeper")
	t.ledger_set_sugar(3.5)
	var o2 := _off(t)
	print("after ledger_set_sugar(3.5): off %.9f" % o2.x)
	ok = ok and o2.x < TOL
	print("CROP LEDGER TEST PASSED" if ok else "CROP LEDGER TEST FAILED")
	quit(0 if ok else 1)
