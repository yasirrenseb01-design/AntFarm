extends "res://scripts/view/nest/parts/nest_lifecycle.gd"
## Nest view, layer 6 of 8 (split from parts/nest_mates.gd in v0.8.5): how a nestmate's body moves —
## easing along its voxel path, turning, the leg cycle, and bodies keeping out of one another (and the queen),
## and (moved from nest_mates.gd in v0.8.16) where an ant chooses to stop: a free patch of floor.


func _pose(from: Vector3, to: Vector3, t: float, up: Vector3, scale := 1.0) -> Transform3D:
	var p := from.lerp(to, clampf(t, 0.0, 1.0))
	var f := to - from
	if f.length_squared() < 0.0001:
		f = Vector3.RIGHT
	f = f.normalized()
	var y := (up - f * f.dot(up))
	if y.length_squared() < 0.01:
		y = Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT
	y = y.normalized()
	var z := f.cross(y)
	return Transform3D(Basis(f, y, z).scaled(Vector3.ONE * scale), p - up * 0.4)


## Turns heading a part of the way (k) toward want. Slerp needs unit vectors and fails (a bad axis) when the
## two are all but the same or opposite: then it simply takes the new heading.
func _turn_to(a: Vector3, want: Vector3, k: float) -> Vector3:
	var u := a.normalized()
	var d := u.dot(want)
	if d > 0.9995 or d < -0.99:
		return want
	return u.slerp(want, k)


## Eases the drawn ant along its voxel path: position, heading and body tilt follow the hops
## smoothly instead of snapping at each cell; distance walked drives the leg gait (radians) and
## `mv` (0..1) tells the shader how much the legs should be stepping. If `face` is set the ant
## turns to look at that point (meeting a nestmate, tending brood).
func _smooth(v: Dictionary, path_pos: Vector3, up: Vector3, delta: float, scale: float) -> Transform3D:
	if not v.has("vp") or v.vp.distance_squared_to(path_pos) > 36.0:
		v.vp = path_pos
		v.vf = Vector3.RIGHT
		v.vu = up
		v.gait = randf() * TAU
		v.mv = 0.0
	var np: Vector3 = v.vp.lerp(path_pos, 1.0 - exp(-12.0 * delta))
	var step: Vector3 = np - v.vp
	var moving := step.length() > 0.12 * delta
	if moving:
		var want := step.normalized()
		var old_f: Vector3 = v.vf
		v.vf = _turn_to(v.vf, want, minf(1.0, 9.0 * delta))
		var turned := old_f.angle_to(v.vf)            # turning takes steps as well as walking does
		v.gait = fmod(v.gait + (step.length() + turned * 0.9 * scale) / (AntModel.stride_len(v.get("stride", 1.0)) * scale) * TAU, TAU * 64.0)
	var face: Vector3 = v.get("face", Vector3.INF)
	if face != Vector3.INF and not moving:
		var to := face - np
		to -= v.vu * to.dot(v.vu)
		if to.length_squared() > 0.01:
			var want := to.normalized()
			v.vf = _turn_to(v.vf, want, minf(1.0, 5.0 * delta))
	v.mv = lerpf(v.mv, 1.0 if moving else 0.0, minf(1.0, 8.0 * delta))
	v.vu = (v.vu as Vector3).lerp(up, minf(1.0, 6.0 * delta)).normalized()
	v.vp = np
	var f: Vector3 = v.vf
	var y: Vector3 = v.vu - f * f.dot(v.vu)
	if y.length_squared() < 0.01:
		y = Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT
	y = y.normalized()
	f = (f - y * f.dot(y)).normalized()
	return Transform3D(Basis(f, y, f.cross(y)).scaled(Vector3.ONE * scale), np - v.vu * 0.4)


func _custom(v: Dictionary, act: int) -> Color:
	var clock: float = v.get("anim", 0.0)
	v.vact = AntModel.act_step(v.get("vact", Vector3(-1, 0, 0)), act, clock)    # poses ease into one another
	return Color(v.get("gait", 0.0), AntModel.act_y(v.vact, clock), fmod(clock, 600.0), AntModel.gait_w(v.get("mv", 0.0), v.get("stride", 1.0)))


const _NEAR := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(-1, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]


## Bodies do not pass through one another: each ant is two discs along its body (head-thorax and
## gaster), the queen a long capsule. Overlaps push the ant sideways (in the floor plane) right out of
## the other body; the push is eased only a little so it never jitters.
func _keep_apart(m: Dictionary, p: Vector3, near: Dictionary, delta: float) -> Vector3:
	var up: Vector3 = m.up
	var s: float = m.size
	var a0: Vector3 = m.get("d0", p)
	var a1: Vector3 = m.get("d1", p)
	var r := 0.55 * s
	var push := Vector3.ZERO
	var key := Vector3i(floori(p.x / 3.0), floori(p.y / 3.0), floori(p.z / 3.0))
	for off in _NEAR:
		var bin = near.get(key + off)
		if bin == null:
			continue
		for o in bin:
			if o == m or (o.has("callow") and m.has("script")):
				continue                 # (the nurses pulling a callow out of its cocoon hold on to it)
			var oc: Vector3 = (o.xf as Transform3D).origin
			if p.distance_squared_to(oc) > 9.0 * s * s:
				continue
			var reach: float = r + 0.55 * float(o.size)
			var rr := reach * reach
			for a in [a0, a1]:
				for b in [o.d0, o.d1]:
					# overlap is judged by the true distance (one ant may be on the wall, the other on
					# the floor); the push itself stays in this ant's floor plane
					var d: Vector3 = a - b
					var l2 := d.length_squared()
					if l2 < rr and l2 > 0.000001:
						var l := sqrt(l2)
						var dir := d - up * d.dot(up)
						if dir.length_squared() < 0.0001:
							dir = (m.xf as Transform3D).basis.z if m.has("xf") else Vector3.RIGHT
						push += dir.normalized() * (reach - l) * 0.5
	if _queen_mm.instance_count > 0:
		var qa: Vector3 = _queen_xf * QUEEN_HEAD
		var qb: Vector3 = _queen_xf * QUEEN_TAIL
		if p.distance_squared_to((qa + qb) * 0.5) < 36.0:
			var attending := m.has("script")             # an attendant may touch her with its head, no more
			for a in [a0, a1]:
				var t := clampf((a - qa).dot(qb - qa) / maxf((qb - qa).length_squared(), 0.001), 0.0, 1.0)
				var d: Vector3 = a - qa.lerp(qb, t)
				d -= up * d.dot(up)
				var l := d.length()
				var reach := QUEEN_R + r
				if attending and a == a0:
					reach = QUEEN_R * 0.8
				if l < reach and l > 0.001:
					push += d / l * (reach - l)
	# brood on the floor is in the way too: ants step round the egg packet, the larvae and the cocoons
	# instead of walking over them; a nurse (or an ant carrying brood) may put its head in among them to
	# lick, feed or pick one up, but not its body
	if not _brood_occ.is_empty() and not _on_brood(m):
		var tends := _tends_brood(m)
		var ar := 0.45 * s                       # an ant's half width (legs bend in round brood)
		for o in _brood_near(p):
			for a in [a0, (a0 + a1) * 0.5, a1]:     # head-thorax, waist and gaster
				var d := _brood_offset(a, o)
				var dv := d.dot(up)
				if absf(dv) > 1.2:
					continue                     # on the wall or ceiling above it
				d -= up * dv
				var reach: float = ar + float(o[3] if o.size() > 3 else o[1])
				if tends and a == a0:
					reach = float(o[3] if o.size() > 3 else o[1]) + 0.12    # head just touching it
				var l := d.length()
				if l < reach and l > 0.001:
					push += d / l * (reach - l) * 0.5     # (as hard as ant on ant: harder only squeezed them into each other)
	# The discs above already include last frame's shift, so `push` is what still overlaps: add it on, and
	# let the shift relax slowly (half-life ~1 s) so an ant drifts back to its path once there is room.
	var was: Vector3 = m.get("sep", Vector3.ZERO)
	var sep: Vector3 = (was + push * minf(1.0, 12.0 * delta)) * pow(0.5, delta)
	sep = sep.limit_length(2.5)
	# never into the soil: in a cramped chamber ants press together (as real ones do) rather than
	# through the walls
	if not _open_at(p + sep, up):
		sep *= 0.5
		if not _open_at(p + sep, up):
			sep = Vector3.ZERO
	# the shift itself changes no faster than a slow step (~4.5 mm/s): two ants pressed together, or one
	# squeezed against the wall, used to flick back and forth a millimetre or more every frame
	sep = was.move_toward(sep, 3.0 * delta)
	m.sep = sep
	return sep


## Whether this nestmate is walking across the brood pile (its way on led over it: no way round). Real
## ants climb over the brood in a crowded chamber (user's choice, 2026-10-13); it is not pushed off sideways.
func _on_brood(m: Dictionary) -> bool:
	return m.has("cell") and _brood_cells.has(m.cell) and not m.has("script")    # (diggers have no cell: never); stays up if it stops there


## How high the brood under p reaches above the floor (0 if none): an ant crossing the pile walks on top of
## it - eggs, larvae and cocoons are firm enough to step on.
func _brood_top(p: Vector3) -> float:
	var top := 0.0
	var f := _floor_cached(p)
	for o in _brood_near(p):
		var d := _brood_offset(p, o)
		var half: float = float(o[3] if o.size() > 3 else o[1])
		if Vector2(d.x, d.z).length() < half + 0.15:
			top = maxf(top, float(o[0].y) + half - f)
	return top


## Whether this nestmate works at the brood itself (its head may go in among the eggs, larvae and cocoons).
func _tends_brood(m: Dictionary) -> bool:
	return m.get("role", "") in ["nurse", "carry", "attend"] or m.has("script") or m.has("deliver")


## How many body parts of nestmates still stand on eggs, larvae or cocoons: dev check (--trace).
var _overlap_who := []


func brood_overlaps() -> int:
	_overlap_who.clear()
	var n := 0
	for m in _mates:
		if not m.has("xf"):
			continue
		var x: Transform3D = m.xf
		var f: Vector3 = x.basis.x.normalized() * (0.7 * float(m.size))
		# (a nurse's head may be in among the brood; its body may not)
		for a in ([x.origin, x.origin - f] if _tends_brood(m) else [x.origin + f, x.origin, x.origin - f]):
			for o in _brood_near(a):
				var d := _brood_offset(a, o)
				var dy := d.y
				d.y = 0.0
				var half: float = o[3] if o.size() > 3 else o[1]
				if absf(dy) < 1.2 and d.length() < (0.45 * float(m.size) + half) * 0.75:
					n += 1
					_overlap_who.append("%s/a%d/r%d/s%d" % [m.get("role", "dig"), m.get("act", 0), m.get("rest", 0), (m.get("settle", []) as Array).size()])
	return n


## How many pairs of nestmates still overlap by more than a third of a body width: dev check (--trace).
func mate_overlaps() -> int:
	var n := 0
	for i in _mates.size():
		var m: Dictionary = _mates[i]
		if not m.has("d0"):
			continue
		for j in range(i + 1, _mates.size()):
			var o: Dictionary = _mates[j]
			if not o.has("d0") or (m.d0 as Vector3).distance_squared_to(o.d0) > 16.0:
				continue
			var lim: float = (0.55 * float(m.size) + 0.55 * float(o.size)) * 0.66
			var hit := false
			for a in [m.d0, m.d1]:
				for b in [o.d0, o.d1]:
					hit = hit or (a as Vector3).distance_to(b) < lim
			if hit:
				n += 1
				_overlap_who.append("M:%s/a%d+%s/a%d@%d" % [m.role, m.act, o.role, o.act, int((m.xf as Transform3D).origin.y)])
	return n


## Whether a body standing at p (on a surface whose up is `up`) is in open space, not in the soil.
func _open_at(p: Vector3, up: Vector3) -> bool:
	var c := p + up * 0.6
	return nest.is_open(Vector3i(roundi(c.x), roundi(c.y), roundi(c.z)))


## Whether a nestmate could stand at cell c without being on top of another ant, the brood or the queen.
func _cell_free(m: Dictionary, c: Vector3i) -> bool:
	if not nest.walkable(c) or _queen_cells.has(c):
		return false
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var o = _mate_cells.get(c + Vector3i(dx, dy, dz))
				if o != null and not is_same(o, m):
					return false
	if not _brood_occ.is_empty():
		var p := Vector3(c) - _up_at(c) * 0.4
		for o in _brood_near(p):
			var d := _brood_offset(p, o)
			if absf(d.y) < 1.2 and Vector2(d.x, d.z).length() < float(o[3] if o.size() > 3 else o[1]) + 1.1:   # half an ant
				return false
	return true


## Ants choose where to stop: a free patch of floor near where they were going (a nurse beside the larvae,
## an attendant beside the queen) rather than on top of a nestmate or the brood. Sets m.settle, the cells
## to walk there (empty: stay put).
func _settle(m: Dictionary) -> bool:
	m.settle = []
	var start: Vector3i = m.cell
	var near_to := Vector3.INF
	match m.role:
		"nurse": near_to = _nearest_spot(Vector3(start), _spots.larvae) if not _spots.larvae.is_empty() else Vector3.INF
		"attend": near_to = _spots.queen if _spots.queen != Vector3.ZERO else Vector3.INF
	var score := func(c: Vector3i, depth: int) -> float:
		return depth * 0.6 + (Vector3(c).distance_to(near_to) if near_to != Vector3.INF else 0.0)
	var best := start if _cell_free(m, start) else Vector3i(-9999, 0, 0)
	var best_s: float = score.call(start, 0) if best == start else INF
	var parent := {start: start}
	var frontier: Array[Vector3i] = [start]
	for depth in range(1, 8):             # (a crowded chamber: look a little further for room)
		var next: Array[Vector3i] = []
		for c in frontier:
			for d in DIRS:
				var n: Vector3i = c + d
				if parent.has(n) or not nest.walkable(n) or _queen_cells.has(n):
					continue
				parent[n] = c
				next.append(n)
				if _cell_free(m, n):
					var s: float = score.call(n, depth)
					if s < best_s - 0.3:          # (stay put unless somewhere is clearly better)
						best_s = s
						best = n
		frontier = next
	if best.x == -9999:
		return false                             # no room anywhere near
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
		if m.rest > 0 and not m.has("script") and not m.carry and _brood_cells.has(m.cell):
			if not _settle(m):
				m.goal = _random_room()
				m.rest = 0


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


## A walkable cell just inside the entrance (where foragers come in), or (-1, 0, 0).
func _entrance_cell() -> Vector3i:
	var c := Vector3i(nest.entrance)
	for k in 10:
		if nest.walkable(c):
			return c
		c.y -= 1
	return _any_spot()


## A walkable floor spot somewhere in the chambers, or (-1, 0, 0).
func _any_spot() -> Vector3i:
	if _spots.all.is_empty():
		return Vector3i(-1, 0, 0)
	for k in 6:
		var sp: Vector3 = _spots.all[randi() % _spots.all.size()]
		var c := Vector3i(roundi(sp.x), roundi(sp.y + 0.45), roundi(sp.z))
		if nest.walkable(c):
			return c
	return Vector3i(-1, 0, 0)


## The ant under the mouse (a screen position) for the hover box (ui/ant_tip.gd): a nestmate (with its real
## worker), a digger, or the queen; {} if none is close.
func pick_ant(sp: Vector2) -> Dictionary:
	var best := {}
	var best_d := 26.0
	var all := {}
	for w in sim.workers:
		all[w.id] = w
	for m in _mates:
		if m.has("xf") and m.get("wid", -1) >= 0:
			var d := _screen_gap((m.xf as Transform3D).origin, sp)
			if d < best_d:
				best_d = d
				best = {"kind": "worker", "w": all.get(m.wid), "role": m.role, "act": m.act}
	# diggers: the colony's diggers are the workers set to dig, lowest id first, one per digger drawn
	var dig_ws: Array = sim.workers.filter(func(w): return w.task == Ant.TASK_DIG)
	dig_ws.sort_custom(func(a, b): return a.id < b.id)
	var ds: Array = nest.diggers.duplicate()
	ds.sort_custom(func(a, b): return a.id < b.id)
	for i in ds.size():
		var v: Dictionary = _dig_vis.get(ds[i].id, {})
		if v.has("xf"):
			var d := _screen_gap((v.xf as Transform3D).origin, sp)
			if d < best_d:
				best_d = d
				best = {"kind": "digger", "w": dig_ws[i] if i < dig_ws.size() else null, "act": ACT_CARRY if ds[i].carry else ACT_DIG,
					"dig": ds[i].id}
	if _queen_mm.instance_count > 0 and _screen_gap(_queen_xf.origin, sp) < 46.0:
		best = {"kind": "queen", "act": _queen_act if _queen_act >= 0 else _queen_mode}
	return best


## The selected ant as it is now (ui/ant_tip.gd): the same fields as pick_ant(), or {} if it is not in the nest.
func info_for(kind: String, id: int) -> Dictionary:
	if kind == "queen":
		return {"kind": "queen", "act": _queen_act if _queen_act >= 0 else _queen_mode} if _queen_mm.instance_count > 0 else {}
	if kind == "digger":
		var dig_ws: Array = sim.workers.filter(func(w): return w.task == Ant.TASK_DIG)
		dig_ws.sort_custom(func(a, b): return a.id < b.id)
		var ds: Array = nest.diggers.duplicate()
		ds.sort_custom(func(a, b): return a.id < b.id)
		for i in ds.size():
			if ds[i].id == id:
				return {"kind": "digger", "w": dig_ws[i] if i < dig_ws.size() else null, "act": ACT_CARRY if ds[i].carry else ACT_DIG, "dig": id}
		return {}
	for m in _mates:
		if int(m.get("wid", -1)) == id:
			for w in sim.workers:
				if w.id == id:
					return {"kind": "worker", "w": w, "role": m.role, "act": m.act}
	return {}


## Whether a click may select an ant here (the nest view has no tools).
func can_select() -> bool:
	return true


func _screen_gap(p: Vector3, sp: Vector2) -> float:
	if not _visible(p) or _cam.is_position_behind(p):
		return INF
	return _cam.unproject_position(p).distance_to(sp)
