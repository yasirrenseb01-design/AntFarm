extends "res://scripts/view/nest/parts/nest_rest.gd"
## Nest view, layer 9 of 14 (split from parts/nest_rest.gd in v0.11.44): the one drawn nestmate per real worker
## inside - bound to it by id (`wid`), its role from the worker's, walked in from the entrance when it has just come
## in and up to the entrance when it goes out (from near the way out: _leave_from_near).


## The nestmates drawn in the nest are the real workers inside, one each, so each keeps its own size, age and
## job: nurses (and the queen's attendants) by the brood and the queen, the reserve resting about, a forager
## just back walking in from the entrance, one going out walking up to it first. Diggers are drawn at the dig
## face (_dig_vis), and workers still climbing out of their cocoons by their eclosion.
var io := {}                     # dev (--io): ants in and out of the nest as the nest view drew them, counted
var _io_was := {}                 # (dev --io: worker id -> in the nest at the last bind)

func _bind_workers() -> void:
	var all := {}
	var inside := []
	for w in sim.workers:
		all[w.id] = w
		if w.state == Ant.IN_NEST and w.task != Ant.TASK_DIG:
			inside.append(w)
	inside.sort_custom(func(a, b): return a.age < b.age or (a.age == b.age and a.id < b.id))
	if not _io_was.is_empty():
		for w in sim.workers:
			var now_in: bool = w.state == Ant.IN_NEST
			if _io_was.has(w.id) and _io_was[w.id] != now_in:
				var k := "sim_in" if now_in else "sim_out"
				io[k] = int(io.get(k, 0)) + 1
	_io_was.clear()
	for w in sim.workers:
		_io_was[w.id] = w.state == Ant.IN_NEST
	var by_id := {}
	for i in range(_pending("eclose"), inside.size()):      # the youngest are still being born
		if by_id.size() >= 250:
			break
		by_id[inside[i].id] = inside[i]
	# the queen's retinue: the nurses most drawn to her
	var attend := {}
	if sim.queen.alive:
		var nurses: Array = by_id.values().filter(func(w): return w.task == Ant.TASK_NURSE)
		nurses.sort_custom(func(a, b): return a.threshold(Ant.TH_ATTEND) < b.threshold(Ant.TH_ATTEND))
		for i in mini(mini(3, by_id.size() / 6), nurses.size()):
			attend[nurses[i].id] = true
	_leave_from_near(all, by_id)
	var keep := []
	var free := []
	var bound := {}
	for m in _mates:
		var wid: int = m.get("wid", -1)
		if m.get("gone", false):
			io.out_reached = int(io.get("out_reached", 0)) + 1
			continue                                   # walked out through the entrance
		if wid >= 0 and by_id.has(wid) and not m.get("leaving", false):
			bound[wid] = m
			keep.append(m)
		elif wid >= 0 and not m.has("script") and not m.has("deliver"):
			var w = all.get(wid)
			if w != null and w.state != Ant.IN_NEST and not m.get("leaving", false):
				# it has gone out: walk it up to the entrance first
				m.leaving = true
				m.left_at = _t
				m.role = "traffic"
				m.goal = -1
				m.rest = 0
				m.wander = 0
				m.settle = []
				m.carry = false
				io.out_started = int(io.get("out_started", 0)) + 1
			if m.get("leaving", false) and _still_leaving(m):
				keep.append(m)
			elif m.get("leaving", false):
				io.out_dropped = int(io.get("out_dropped", 0)) + 1      # (never got to the entrance: gone mid-tunnel)
				io.out_dropped_d = float(io.get("out_dropped_d", 0.0)) + (m.to as Vector3).distance_to(Vector3(nest.entrance))
		elif wid < 0:
			free.append(m)                             # a newborn from an eclosion: takes the youngest worker
		else:
			keep.append(m)                             # busy in a life-cycle moment: let it finish
	for w in by_id.values():
		if bound.has(w.id):
			continue
		var m: Dictionary
		if not free.is_empty():
			m = free.pop_front()
		else:
			var walking_in: bool = sim.tick - int(w.came_in) < int(sim.TPD * 0.05)
			var c := _entrance_cell() if walking_in else _any_spot()
			if c.x < 0:
				continue
			_add_mate(c, "traffic" if walking_in else "idle", -1000000000, w.size)
			var k := "in_entrance" if walking_in else ("in_anywhere_recent" if sim.tick - int(w.came_in) < int(sim.TPD * 0.5) else "placed")
			io[k] = int(io.get(k, 0)) + 1
			m = _mates.pop_back()
			m.fed = walking_in and w.brought == Ant.SUGAR       # back from the aphids: its crop is full
			if not walking_in:
				_settle(m)
		m.wid = w.id
		bound[w.id] = m
		keep.append(m)
	_mates = keep
	# each one's job follows its worker's (unless it is in the middle of carrying or a life-cycle moment)
	for wid in bound:
		var m: Dictionary = bound[wid]
		var w = by_id[wid]
		m.size = w.size
		m.born = sim.tick - int(w.age * sim.TPD)
		if m.carry or m.has("script") or m.has("deliver") or m.role == "carry":
			continue
		var want := _role_for(m, w, attend.has(wid))
		if want != m.role:
			m.role = want
			m.goal = _queen_room() if want == "attend" else (_brood_room(_larva_group) if want == "nurse" else _random_room())
			m.wander = 0
			m.rest = mini(m.rest, 5)
			if want == "wander":
				m.wander = 0                            # (walking about the nest: chamber to chamber along the tunnels)


## What a drawn nestmate does, from its worker: queen's retinue, nurse at the brood, walking in, or resting. (The nest
## view's duties layer, nest_duties.gd, gives it the duty the simulation set instead - this is what is left without one.)
func _role_for(m: Dictionary, w, attends: bool) -> String:
	if attends:
		return "attend"
	if (w.task == Ant.TASK_NURSE or w.task == Ant.TASK_CALLOW) and w.threshold(Ant.TH_ATTEND) < 1.15:
		return "nurse"                             # (the rest of the nurses rest nearby, off the brood pile)
	if _walking_in(m, w):
		return "traffic"                           # still walking in from the entrance
	return "idle"


func _walking_in(m: Dictionary, w) -> bool:
	return m.role == "traffic" and m.goal != -1 and sim.tick - int(w.came_in) < int(sim.TPD * 0.05)


## A worker the simulation has just sent out leaves from near the entrance: the inside nestmate drawn nearest the way
## out (much nearer than its own body, of much the same size and age) takes it over, and its own body takes that
## nestmate's worker. Each worker's body used to walk out from wherever it was - from the deepest chamber of a big
## nest that took longer than the 25 s allowed, and half of them vanished in the tunnels (the keeper's colony, 1 min:
## 22 out, 8 reached the entrance, 9 gone mid-tunnel ~36 cells from it). An ant the keeper has selected, follows or
## named keeps its own body.
const LEAVE_NEAR := 6             # cells from the entrance: near enough to walk out as it is
const SWAP_SIZE := 0.04           # the most two bodies that change workers may differ in size

func _leave_from_near(all: Dictionary, by_id: Dictionary) -> void:
	var ef: Dictionary = _fields.get(-1, {})
	if ef.is_empty():
		return
	for m in _mates:
		var wid: int = m.get("wid", -1)
		if wid < 0 or not _free_body(m):
			continue
		var w = all.get(wid)
		if w == null or w.state == Ant.IN_NEST or _own_body(w):
			continue
		var dm: int = ef.get(m.cell, 1 << 20)
		if dm <= LEAVE_NEAR:
			continue
		var best = null
		var bd: int = dm - LEAVE_NEAR
		for c in _mates:
			var cw: int = c.get("wid", -1)
			if cw < 0 or not by_id.has(cw) or not _free_body(c) or _own_body(by_id[cw]):
				continue
			var o = by_id[cw]
			if absf(float(o.size) - float(w.size)) > SWAP_SIZE or (minf(o.age, w.age) < float(sim.sp["callow_days"]) and absf(o.age - w.age) > 1.0):
				continue                     # (a callow's pale body is not a dark one's)
			var d: int = ef.get(c.cell, 1 << 20)
			if d < bd:
				best = c
				bd = d
		if best != null:
			io.swapped = int(io.get("swapped", 0)) + 1
			m.wid = best.wid
			best.wid = wid


func _free_body(m: Dictionary) -> bool:
	return not (m.get("leaving", false) or m.get("gone", false) or m.has("script") or m.has("deliver") or m.carry
		or m.role == "carry")


func _own_body(w) -> bool:
	return (sel_kind == "worker" and sel_id == w.id) or follow_wid == w.id or String(w.name) != ""


## A body walking out keeps going while it still gets nearer the entrance (or the clock is stopped); one that has not
## for 8 s is held up for good, and goes (it was 25 s in all, however far it had to walk).
func _still_leaving(m: Dictionary) -> bool:
	if speed <= 0.0:
		return true
	var d: int = _fields.get(-1, {}).get(m.cell, 1 << 20)
	if d < int(m.get("out_best", 1 << 20)):
		m.out_best = d
		m.out_best_t = _t
	return _t - float(m.get("out_best_t", m.get("left_at", _t))) < 8.0
