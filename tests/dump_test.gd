extends SceneTree
## The diggers carry their soil out themselves (v0.11.57, sim._surface): over 12 days of a young colony, workers are
## seen outside with a pellet (Ant.DUMP, carrying Ant.SOIL), each is a digging worker bound to a digger, sets its pellet
## down within the crater's ring (where nest.excavated grows) and comes back in; every digger with a pellet at the
## entrance waits for its worker; the soil dumped this way is most of what was dug.
## v0.12.31: a soil carrier killed outside before setting its pellet down - its digger is back digging within an hour
## (before, it waited for ever); and all along, no digger waits on a worker that is gone, no job is left for one.
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
	var dumped: int = s.nest.excavated - dumped0 + _exit_soil(s)
	print("  soil carriers seen %d, farthest %.1f px from the entrance, trail under them %.2f, pellets dumped %d" % [seen, far, trail, dumped])
	_check("soil carriers seen outside", seen > 20)
	_check("they stay by the crater (< 30 px)", far < 30.0)
	_check("they lay a home trail", trail > 0.0)
	_check("pellets dumped", dumped > 50)
	_killed_carriers(s)
	print("DUMP TEST PASSED" if ok else "DUMP TEST FAILED")
	quit()


## Kill every soil carrier outside that has not set its pellet down; each of their diggers must dig on within a game
## hour, and the colony's diggers stay whole (the invariant checked at every tick).
func _killed_carriers(s) -> void:
	var killed := {}           # worker id -> [its digger's id, the tick it was killed]
	var back := 0
	var late := 0
	for t in s.TPD * 3:
		s.step()
		if killed.size() < 3:
			for a in s.outside:
				var job = s._dumps.get(a.id)
				if a.state == Ant.DUMP and not a.dead and job != null and not job.get("dropped", false) and not killed.has(a.id):
					killed[a.id] = [int(job.dig), s.tick]
					s._kill(a, "other")
					break
		for wid in killed:
			var k: Array = killed[wid]
			if k.size() > 2:
				continue
			var waiting := false
			for d in s.nest.diggers:
				if int(d.id) == k[0] and d.get("surfacing", false) and int(d.get("wid", -1)) == wid:
					waiting = true
			if not waiting:
				k.append(s.tick - k[1])
				back += 1
			elif s.tick - k[1] > s.TPD / 24:
				k.append(-1)
				late += 1
		_invariant(s)
	_check("soil carriers killed with their pellet (3)", killed.size() == 3)
	var took := []
	for wid in killed:
		took.append(killed[wid][2] if killed[wid].size() > 2 else -1)
	print("  killed carriers %d, their diggers free again %d (ticks after: %s), stuck longest %d ticks" % [killed.size(), back, str(took), stuck_max])
	_check("every digger of a killed carrier is free within a game hour", back == killed.size() and late == 0)
	_check("no digger waits on a gone worker longer than two nest steps", stuck_max <= 2 * 4 + 1)


var _stuck_since := {}
var stuck_max := 0


## A digger out at the entrance waits only on a living worker; a job is only for a worker still there or just gone.
func _invariant(s) -> void:
	var live := {}
	for w in s.workers:
		if not w.dead:
			live[w.id] = true
	var now := {}
	for d in s.nest.diggers:
		if d.get("surfacing", false) and not live.has(int(d.get("wid", -1))):
			now[d.id] = true
	for wid in s._dumps:
		if not live.has(int(wid)):
			now["job%d" % int(wid)] = true
	for k in now:
		_stuck_since[k] = int(_stuck_since.get(k, s.tick))
		stuck_max = maxi(stuck_max, s.tick - int(_stuck_since[k]))
	for k in _stuck_since.keys():
		if not now.has(k):
			_stuck_since.erase(k)


static func _exit_soil(s) -> int:
	var n := 0
	for e in s.nest.exits:
		n += int(e.get("soil", 0))
	return n


func _check(what: String, good: bool) -> void:
	if not good:
		print("  FAIL ", what)
		ok = false
