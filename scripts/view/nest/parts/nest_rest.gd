extends "res://scripts/view/nest/parts/nest_bodies.gd"
## Nest view, layer 7 of 9 (split from parts/nest_bodies.gd in v0.8.55): where a nestmate stops and how it
## lies there - a free patch of floor with room for its body (not in a nestmate, the queen's legs or a narrow
## tunnel), clear of the soil where a chamber floor curves (lifted) or a wall is close (turned away), stepping
## aside when pushed; and the one drawn nestmate per real worker inside.


## Pushed aside (by a nestmate, the queen or the brood), an ant steps aside on its legs instead of gliding over
## the floor: the shift drives its gait as walking does (`sgr`, radians a second, and `smv`, how much it
## steps, applied every frame), and a steady shift turns it to walk that way (not when it is pushed
## backwards: it backs off a step, as ants do). Called with each new shift, `dt` the time since the last.
func _step_aside(m: Dictionary, dt: float) -> void:
	var sv: Vector3 = m.get("sep", Vector3.ZERO)
	var was: Vector3 = m.get("sep_was", Vector3.ZERO)
	if sv == was:
		if float(m.get("sgr", 0.0)) != 0.0:     # (most ants, standing where they settled: nothing to do)
			m.sgr = 0.0
			m.sepv = Vector3.ZERO
		return
	var ds: Vector3 = sv - was
	m.sep_was = sv
	if dt <= 0.0 or not m.has("vf"):
		return
	var up: Vector3 = m.get("vu", m.up)
	ds -= up * ds.dot(up)
	var sv_avg: Vector3 = (m.get("sepv", Vector3.ZERO) as Vector3).lerp(ds / dt, 1.0 - exp(-4.0 * dt))
	m.sepv = sv_avg
	var speed := ds.length() / dt
	if speed < 0.02:
		m.sgr = 0.0
		return
	m.sgr = speed / (AntModel.stride_len(float(m.get("stride", 1.0))) * float(m.size)) * TAU
	m.smv = clampf(speed / 0.5, 0.0, 1.0)
	if m.rest > 0 and sv_avg.length() > 0.3 and (m.get("face", Vector3.INF) as Vector3) == Vector3.INF:     # (walking, its way on turns it)
		var w := sv_avg.normalized()
		if (m.vf as Vector3).dot(w) > -0.3:
			m.vf = _turn_to(m.vf, w, minf(1.0, 2.5 * dt))


## A resting ant pushed well off its spot (its neighbours or the queen are in the way) gets up after a moment
## and walks to a free spot nearby (as it does when it first stops), rather than being held squeezed aside.
func _make_room(m: Dictionary, md: float) -> void:
	var pt := float(m.get("pushed_t", 0.0))
	if m.rest > 0 and not m.has("script") and not m.carry and (m.get("settle", []) as Array).is_empty() \
			and (m.get("sep", Vector3.ZERO) as Vector3).length() > 0.8:
		pt += md
		if pt > 1.5:
			pt = -3.0                            # (not again for a while)
			if _settle(m) and not (m.settle as Array).is_empty():
				m.act_left = 0.0                 # (stops grooming to go)
	else:
		pt = minf(pt + md, 0.0)
	m.pushed_t = pt


## How far an ant standing on floor cell c must be raised for its body to clear the floor around it (a curving
## chamber floor can rise above the cell's own height within a body length): cached per cell until the soil
## changes. Only soil that rising clears counts: a wall beside the cell is no reason to float above it.
func _cell_lift(c: Vector3i) -> float:
	var v = _lift_cache.get(c)
	if v == null:
		# along the cell's own up (floor, wall or ceiling): sample a body's span round the cell at belly height
		var up := _up_at(c)
		var a := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		var b := up.cross(a).normalized()
		var need := 0.0
		for o in [Vector3.ZERO, a * 0.8, -a * 0.8, b * 0.8, -b * 0.8]:
			need = maxf(need, _rise_to_clear(Vector3(c) + o + up * 0.25, up))
		v = need
		_lift_cache[c] = v
	return v


## How far point p must rise along `up` to be out of the soil: 0 if it is already, -1 if rising
## MAX_RISE does not clear it (it is in a wall beside or ahead, not under a curving floor).
const MAX_RISE := 0.8
func _rise_to_clear(p: Vector3, up: Vector3) -> float:
	var l := 0.0
	while _density_at(p + up * l) >= 0.5:
		l += 0.2
		if l > MAX_RISE + 0.01:
			return -1.0
	return l


## Points of an ant's body (model units) that must be out of the soil: head, thorax, gaster at belly height
## (a little lower than the belly and a little wider than the body: a margin, so it stays clear as it shifts a
## fraction before it is checked again).
const BODY_PTS := [Vector3(0.9, 0.2, 0), Vector3(0, 0.2, 0), Vector3(-1.0, 0.2, 0), Vector3(0, 0.2, 0.3), Vector3(0, 0.2, -0.3)]


## For an ant drawn at `tr`: how far it must rise along its up for its body to clear a curving floor (x), and
## how many of its points are in soil that rising does not clear (y: its head or gaster in a wall - lifting
## would only float it; a resting ant turns away from the wall instead, see _free_heading).
func _soil_clearance(tr: Transform3D, s: float) -> Vector2:
	var up := tr.basis.y.normalized()
	var need := 0.0
	var stuck := 0
	for q in BODY_PTS:
		var r := _rise_to_clear(tr * q, up)
		if r < 0.0:
			stuck += 1
		else:
			need = maxf(need, r)
	return Vector2(need, stuck)


## Whether an ant can stand at cell c with its whole body clear of the soil in some heading (not in a narrow
## tunnel or a tight corner, where its head or gaster would be in the wall whichever way it faced): where
## nestmates choose to stop and rest. Cached per cell until the soil changes.
func _cell_fits(c: Vector3i) -> bool:
	var v = _fit_cache.get(c)
	if v == null:
		var up := _up_at(c)
		var f := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		var o := Vector3(c) - up * 0.4 + up * _cell_lift(c)
		v = false
		for k in 8:
			var h := f.rotated(up, k * TAU / 8.0)
			if _soil_clearance(Transform3D(Basis(h, up, h.cross(up)), o), 1.0).y == 0:
				v = true
				break
		_fit_cache[c] = v
	return v


## The heading (in its floor's plane) in which an ant drawn at `tr` lies clear of the walls - and not with its
## head or gaster in a nestmate beside it - nearest its own: Vector3.ZERO if no heading is clearer than the
## one it has.
func _free_heading(m: Dictionary, tr: Transform3D, lift: float) -> Vector3:
	var up := tr.basis.y.normalized()
	var f := tr.basis.x.normalized()
	var sc := tr.basis.x.length()
	var o := tr.origin + up * lift
	var best := Vector3.ZERO
	var best_s := INF
	for k in 8:
		var a := (k + 1) / 2 * (1 if k % 2 == 1 else -1) * TAU / 8.0     # 0, +45, -45, +90, -90 ... degrees
		var h := f.rotated(up, a)
		var t := Transform3D(Basis(h, up, h.cross(up)).scaled(Vector3.ONE * sc), o)
		var c := _soil_clearance(t, sc)
		var score := c.y * 10.0 + c.x + absf(a) * 0.05
		for e in [o + h * (1.2 * sc), o - h * (1.2 * sc)]:     # its two ends: a nestmate there?
			var ec := Vector3i(roundi(e.x), roundi(e.y), roundi(e.z))
			for d in _NEAR:
				var n = _mate_cells.get(ec + d)
				if n != null and not is_same(n, m):
					score += 4.0
					break
		if k == 0:
			if c.y == 0:
				return Vector3.ZERO
			best_s = score
			continue
		if score < best_s:
			best_s = score
			best = h
	return best


var _near_bins := {}              # the nestmates binned by where they are drawn this frame (_update_ants)
## Whether a nestmate could stand at cell c without being on top of another ant, the brood or the queen (her
## body, and her legs reaching out beside it: an ant resting in them was pushed off into its neighbours).
func _cell_free(m: Dictionary, c: Vector3i) -> bool:
	return _cell_ok(c) and not _brood_wide.has(c) and _cell_room(m, c) >= ROOM_FREE


## Whether an ant could stand at cell c at all, nestmates aside: on a surface, off the queen and out of her
## legs, and with room for its body (not a narrow tunnel or a tight corner).
func _cell_ok(c: Vector3i) -> bool:
	if not nest.walkable(c) or _queen_cells.has(c):
		return false
	if _queen_mm.instance_count > 0 and _queen_gap(Vector3(c)) < 1.35:
		return false
	return _cell_fits(c)


## How much room there is for a nestmate at cell c: the distance to the nearest other ant - the cell it stands
## on (or is going to rest on), and its body (head-thorax and gaster discs, as drawn this frame: pushed off its
## own cell, or lying across the next one); at most ROOM_FREE.
const ROOM_FREE := 1.7               # (a body's half length + a disc: no overlap whichever way it faces)
func _cell_room(m: Dictionary, c: Vector3i) -> float:
	var room := ROOM_FREE * ROOM_FREE
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var o = _mate_cells.get(c + Vector3i(dx, dy, dz))
				if o != null and not is_same(o, m):
					room = minf(room, float(dx * dx + dy * dy + dz * dz))
	if room == 0.0:
		return 0.0
	var p := Vector3(c) + Vector3(0, -0.4, 0)
	for bx in range(floori((p.x - 2.0) / 3.0), floori((p.x + 2.0) / 3.0) + 1):
		for by in range(floori((p.y - 2.0) / 3.0), floori((p.y + 2.0) / 3.0) + 1):
			for bz in range(floori((p.z - 2.0) / 3.0), floori((p.z + 2.0) / 3.0) + 1):
				var bin = _near_bins.get(Vector3i(bx, by, bz))
				if bin == null:
					continue
				for o in bin:
					if not is_same(o, m) and o.has("d0"):
						room = minf(room, minf((o.d0 as Vector3).distance_squared_to(p), (o.d1 as Vector3).distance_squared_to(p)))
	return sqrt(room)


## Ants choose where to stop: a free patch of floor near where they were going (a nurse beside the larvae,
## an attendant beside the queen) rather than on top of a nestmate or the brood. Sets m.settle, the cells
## to walk there (empty: stay put).
func _settle(m: Dictionary) -> bool:
	var t0 := Time.get_ticks_usec()
	var r := _settle_on(m)
	fprof["ants: settle"] = fprof.get("ants: settle", 0) + Time.get_ticks_usec() - t0
	return r


func _settle_on(m: Dictionary) -> bool:
	m.settle = []
	var start: Vector3i = m.cell
	var near_to := Vector3.INF
	match m.role:
		"nurse": near_to = _nearest_spot(Vector3(start), _spots.larvae) if not _spots.larvae.is_empty() else Vector3.INF
		"attend": near_to = _spots.queen if _spots.queen != Vector3.ZERO else Vector3.INF
	# a resting ant settles on the floor: walls and the ceiling only if nothing else is free nearby (ants do
	# walk on them, but a chamber full of ants resting upside down looked chaotic)
	var score := func(c: Vector3i, depth: int) -> float:
		var u: Vector3 = _up_at(c)
		var where := 0.0 if u.y > 0.7 else (2.5 if u.y > -0.3 else 5.0)
		return depth * 0.6 + where + (Vector3(c).distance_to(near_to) if near_to != Vector3.INF else 0.0)
	# the cells within reach along the walls (cheap), then those looked at for room best first (the room
	# around a cell - the nestmates near it - is the costly part: worked out only until a free one turns up)
	var parent := {start: start}
	var cands := [[score.call(start, 0) - 0.3, start]] if _cell_ok(start) and not _brood_wide.has(start) else []
	var frontier: Array[Vector3i] = [start]
	var floor_seen := false
	for depth in range(1, 13):            # (a crowded chamber: look a little further for room)
		# (by 7 steps it has looked round its own part of the chamber; further only if all it found is up on
		# the ceiling or a wall - ants coming in at the top of a chamber used to rest on its ceiling, the floor
		# being just out of reach)
		if depth > 7 and floor_seen:
			break
		var next: Array[Vector3i] = []
		for c in frontier:
			for d in DIRS:
				var n: Vector3i = c + d
				if parent.has(n) or not nest.walkable(n) or _queen_cells.has(n):
					continue
				parent[n] = c
				next.append(n)
				if _cell_ok(n) and not _brood_wide.has(n):
					var sc: float = score.call(n, depth)
					cands.append([sc, n])
					floor_seen = floor_seen or sc - depth * 0.6 < 2.0
		frontier = next
	cands.sort_custom(func(x, y): return x[0] < y[0])     # (start's own score is 0.3 better: it stays put unless somewhere is clearly better)
	var best := Vector3i(-9999, 0, 0)
	# (no free spot near: the roomiest one - packed in as real ants are in a crowded chamber, but not inside
	# a nestmate; where it stands now counts too)
	var roomy := start
	var roomy_r := -1.0
	for k in mini(cands.size(), 60):
		var c: Vector3i = cands[k][1]
		var room := _cell_room(m, c)
		if room >= ROOM_FREE:
			best = c
			break
		if room - k * 0.01 > roomy_r + (0.3 if c != start else 0.0):
			roomy_r = room - k * 0.01
			roomy = c
	if best.x == -9999:
		if roomy_r < 0.5:
			return false                         # no room anywhere near
		best = roomy
	if best == start:
		return true
	var path := []
	var c := best
	while c != start:
		path.push_front(c)
		c = parent[c]
	m.settle = path
	_mate_cells[best] = m                    # spoken for: the next ant looks elsewhere
	return true


## After the brood is laid out again, ants resting where it now lies get up and find room beside it (or go to
## rest in another chamber).
func _clear_brood_of_ants() -> void:
	for m in _mates:
		if m.rest > 0 and not m.has("script") and not m.carry and _body_on_brood(m):
			if not _settle(m):
				m.goal = _random_room()
				m.rest = 0


## Whether any part of a resting ant's body (head end, middle, gaster; a nurse's head may be among the brood)
## lies over the brood.
func _body_on_brood(m: Dictionary) -> bool:
	if not m.has("xf"):
		return _brood_cells.has(m.cell)
	var x: Transform3D = m.xf
	var f: Vector3 = x.basis.x.normalized() * (0.7 * float(m.size))
	var pts: Array = [x.origin, x.origin - f] if _tends_brood(m) else [x.origin + f, x.origin, x.origin - f]
	for q in pts:
		if _brood_cells.has(Vector3i(roundi(q.x), roundi(q.y - 0.45), roundi(q.z))):
			return true
	return false


# ---------------------------------------------------------------- one drawn nestmate per real worker

## The nestmates drawn in the nest are the real workers inside, one each, so each keeps its own size, age and
## job: nurses (and the queen's attendants) by the brood and the queen, the reserve resting about, a forager
## just back walking in from the entrance, one going out walking up to it first. Diggers are drawn at the dig
## face (_dig_vis), and workers still climbing out of their cocoons by their eclosion.
func _bind_workers() -> void:
	var all := {}
	var inside := []
	for w in sim.workers:
		all[w.id] = w
		if w.state == Ant.IN_NEST and w.task != Ant.TASK_DIG:
			inside.append(w)
	inside.sort_custom(func(a, b): return a.age < b.age or (a.age == b.age and a.id < b.id))
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
	var keep := []
	var free := []
	var bound := {}
	for m in _mates:
		var wid: int = m.get("wid", -1)
		if m.get("gone", false):
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
			if m.get("leaving", false) and _t - float(m.get("left_at", _t)) < 25.0:
				keep.append(m)
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
		var want := "idle"
		if attend.has(wid):
			want = "attend"
		elif (w.task == Ant.TASK_NURSE or w.task == Ant.TASK_CALLOW) and w.threshold(Ant.TH_ATTEND) < 1.15:
			want = "nurse"                             # (the rest of the nurses rest nearby, off the brood pile)
		elif m.role == "traffic" and m.goal != -1 and sim.tick - int(w.came_in) < int(sim.TPD * 0.05):
			want = "traffic"                           # still walking in from the entrance
		if want != m.role:
			m.role = want
			m.goal = _queen_room() if want == "attend" else (_brood_room(_larva_group) if want == "nurse" else _random_room())
			m.wander = 0
			m.rest = mini(m.rest, 5)
