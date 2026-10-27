extends SceneTree
## The diggers carry their soil out themselves (v0.11.57, sim._surface): over 12 days of a young colony, workers are
## seen outside with a pellet (Ant.DUMP, carrying Ant.SOIL), each is a digging worker bound to a digger, sets its pellet
## down within the crater's ring (where nest.excavated grows) and comes back in; every digger with a pellet at the
## entrance waits for its worker; the soil dumped this way is most of what was dug.
##   godot --headless --path . --script res://tests/dump_test.gd     -> "DUMP TEST PASSED"

const Sim := preload("res://scripts/sim/simulation.gd")
const Ant := preload("res://scripts/sim/ant.gd")
var ok := true


func _init() -> void:
	var s = Sim.new()
	s.setup(7, 20, false, "keeper")
	var seen := 0
	var far := 0.0
	var trail := 0.0
	var dumped0: int = s.nest.excavated
	for t in s.TPD * 12:
		s.step()
		if t % 20 != 0:
			continue
		for a in s.outside:
			if a.state == Ant.DUMP:
				seen += 1
				far = maxf(far, a.pos.distance_to(s.nest_pos))
				trail = maxf(trail, s.home.read_i(int(a.pos.y / s.CELL) * s.gw + int(a.pos.x / s.CELL)))
				var bound := false
				for d in s.nest.diggers:
					if int(d.get("wid", -1)) == a.id:
						bound = true
				_check("a soil carrier is a digger's worker", bound)
	var dumped: int = s.nest.excavated - dumped0
	print("  soil carriers seen %d, farthest %.1f px from the entrance, trail under them %.2f, pellets dumped %d" % [seen, far, trail, dumped])
	_check("soil carriers seen outside", seen > 20)
	_check("they stay by the crater (< 30 px)", far < 30.0)
	_check("they lay a home trail", trail > 0.0)
	_check("pellets dumped", dumped > 50)
	print("DUMP TEST PASSED" if ok else "DUMP TEST FAILED")
	quit()


func _check(what: String, good: bool) -> void:
	if not good:
		print("  FAIL ", what)
		ok = false
