extends "res://scripts/view/nest/parts/nest_bodies.gd"
## Nest view, layer 8 of 15 (split from parts/nest_bodies.gd in v0.8.55): where a nestmate stops and how it
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
	# (by the push as it goes over a quarter of a second, not frame by frame: the keep-apart push wobbles to and fro a
	# little every frame, and stepping by each wobble a resting ant trod on the spot - a foot lifted ~11 times a second,
	# landing with jumps of 0.3-0.5: the keeper saw them shake, 2026-10-28. Nudged slower than STEP_ASIDE_MIN, it
	# stands on its planted feet - and steps once it has gone off them: nest_feet._feet_twisted)
	var speed := sv_avg.length()
	if speed < STEP_ASIDE_MIN:
		m.sgr = 0.0
		return
	m.sgr = speed / (AntModel.stride_len(float(m.get("stride", 1.0))) * float(m.size)) * TAU
	m.smv = clampf(speed / 0.5, 0.0, 1.0)
	if m.rest > 0 and sv_avg.length() > 0.3 and (m.get("face", Vector3.INF) as Vector3) == Vector3.INF:     # (walking, its way on turns it)
		var w := sv_avg.normalized()
		if (m.vf as Vector3).dot(w) > -0.3:
			m.vf = _turn_to(m.vf, w, minf(1.0, 2.5 * dt))


const STEP_ASIDE_MIN := 0.15    # units a second a push must shift it by before its legs step with it


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


## How an ant lies on the real surface under it, standing on cell c facing `fwd`: [lift along its up, pitch
## (nose up +), roll, gaster bend (tip up +), head bend (up +)] - its feet on the ground under them, the body
## tipped to the slope they stand on, the gaster and head bent toward the ground under them (an ant's body is
## jointed at the waist and the neck). From the ground round the cell (_ground_ring, worked out once per cell);
## an empty array if that is still to be worked out and this frame's share is used up (the caller keeps what
## it had).
func _fit_at(c: Vector3i, fwd: Vector3) -> PackedFloat32Array:
	var e = _gfit_cache.get(c)
	if e == null:
		if _gfit_budget <= 0:
			return PackedFloat32Array()
		_gfit_budget -= 1
		e = _ground_ring(c)
		_gfit_cache[c] = e
	var up: Vector3 = e[0]
	var ref: Vector3 = e[1]
	var g: PackedFloat32Array = e[2]
	var a := atan2(up.cross(ref).dot(fwd), ref.dot(fwd))
	var g0 := g[0]
	# (the ground under its feet, ahead, behind and to each side - a wall there counts as ground rising half a unit
	# at most: it tips the body up toward it, but does not stand it up against the wall)
	var gf := clampf(_ring_at(g, 1, a), g0 - 0.6, g0 + 0.5)
	var gb := clampf(_ring_at(g, 1, a + PI), g0 - 0.6, g0 + 0.5)
	var gl := clampf(_ring_at(g, 1, a - PI * 0.5), g0 - 0.6, g0 + 0.5)             # (its left: forward x up)
	var gr := clampf(_ring_at(g, 1, a + PI * 0.5), g0 - 0.6, g0 + 0.5)
	# (its middle stays on the ground under it: at the foot of a wall the ground ahead "rises" into the wall -
	# that tips it nose up, it does not lift it off the floor)
	var lift := g0 + clampf((gf + gb + gl + gr) * 0.25 - g0, -0.15, 0.2)
	# (no ground close under it - over a drop, or between two walls: it stays where its cell is, it is not lowered
	# into the gap)
	lift = maxf(lift, -0.35)
	var slope := (gf - gb) / 1.6
	var pitch := clampf(atan(slope), -0.6, 0.6)
	var roll := clampf(atan2(gl - gr, 1.6), -0.5, 0.5)
	# (ground that rises more than half a unit there is a wall, not floor to bend toward)
	var bt := clampf(atan2(minf(_ring_at(g, 9, a + PI), lift + 0.5) - (lift - slope * 1.05), 0.55), -0.2, 0.3)
	var bh := clampf(atan2(minf(_ring_at(g, 9, a), lift + 0.5) - (lift + slope * 1.05), 0.5), -0.2, 0.25)
	return PackedFloat32Array([clampf(lift, -0.6, 0.5), pitch, roll, bt, bh])     # (never far off its cell: a misread up raised ants into the ceiling)


## The ground round cell c, along the cell's up from where a body standing there is drawn (feet level): under
## its middle, then 8 places round it 0.8 away (under its feet) and 8 places 1.05 away (under its head and
## gaster tip): [up, a fixed heading round it, the 17 heights]. A drop (nothing within reach) counts as the
## ground under its middle.
func _ground_ring(c: Vector3i) -> Array:
	var up := _up_at(c)
	var ref := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var o := Vector3(c) - up * 0.4
	var g := PackedFloat32Array()
	g.resize(17)
	g[0] = _ground_off(o, up)
	for k in 8:
		var d := ref.rotated(up, k * TAU / 8.0)
		for j in 2:
			var v := _ground_off(o + d * (0.8 if j == 0 else 1.05), up)
			g[1 + j * 8 + k] = g[0] if v <= -0.99 else v
	return [up, ref, g]


## The ground height round a cell at angle a (radians round its up from its fixed heading), between the two
## nearest of the 8 (ring from index i0 of _ground_ring's heights).
static func _ring_at(g: PackedFloat32Array, i0: int, a: float) -> float:
	var x := fposmod(a / TAU * 8.0, 8.0)
	var k := floori(x)
	return lerpf(g[i0 + k % 8], g[i0 + (k + 1) % 8], x - k)


## Where the ground is along `up` from a point p at a body's feet level: + above it (the floor rises there), -
## below; -1 if there is none within reach (a drop).
func _ground_off(p: Vector3, up: Vector3) -> float:
	var s := 0.35
	if _density_at(p + up * s) < 0.5:
		while s > -0.95:
			s -= 0.2
			if _density_at(p + up * s) >= 0.5:
				return s + 0.1
		return -1.0
	while s < 1.15:
		s += 0.2
		if _density_at(p + up * s) < 0.5:
			return s - 0.1
	return 1.2


## The ground fit (see _fit_at) for an ant drawn at `tr`, from the cell it is over now, eased toward it. How it
## is tipped and bent is looked up again only when `fresh` (a third of the ants each frame); how high it stands
## follows the ground under the very point it is at, every frame - from that cell's ring of ground heights, so
## it does not jump as it passes from one cell to the next (a walking ant bobbed up and down at every cell).
## The easing stops once it is there (most ants stand still).
const _FIT0 := [0.0, 0.0, 0.0, 0.0, 0.0]
func _fit_for(m: Dictionary, tr: Transform3D, md: float, fresh: bool) -> PackedFloat32Array:
	var cur: PackedFloat32Array = m.get("gfit", PackedFloat32Array())
	var p := tr.origin + tr.basis.y.normalized() * 0.4
	if fresh or cur.size() != 5:
		var c := Vector3i(roundi(p.x), roundi(p.y), roundi(p.z))
		var was: Vector3i = m.get("gfit_c", Vector3i(-1, -1, -1))
		if was.x >= 0 and Vector3(was).distance_to(p) < 0.85 and nest.is_open(was):
			c = was                    # (kept until it is well over the next cell: no flicking between two)
		elif not nest.is_open(c):
			c = m.cell
		var w := _fit_at(c, tr.basis.x)
		if w.size() == 5:
			m.gfit_want = w
			m.gfit_c = c
	var want: PackedFloat32Array = (m.get("gfit_want", PackedFloat32Array(_FIT0)) as PackedFloat32Array).duplicate()
	var e = _gfit_cache.get(m.get("gfit_c", Vector3i(-1, -1, -1)))
	if e != null:
		var cu: Vector3 = e[0]
		var g: PackedFloat32Array = e[2]
		var off: Vector3 = p - Vector3(m.gfit_c)
		var along := off.dot(cu)
		var o := off - cu * along
		var r := o.length()
		var ga := g[0]
		if r > 0.05:
			var ref: Vector3 = e[1]
			# (a wall beside it is not ground to stand higher on: only the floor's own rise, at most ~half a unit)
			ga += (clampf(_ring_at(g, 1, atan2(cu.cross(ref).dot(o), ref.dot(o))), g[0] - 0.5, g[0] + 0.4) - g[0]) * minf(r / 0.8, 1.25)
		want[0] = clampf(want[0] + ga - g[0] - along, -0.7, 0.6)
	if cur.size() != 5:
		cur = want
		m.gfit_still = false
	else:
		var moved := absf(want[0] - cur[0]) > 0.004
		for i in range(1, 5):
			moved = moved or absf(want[i] - cur[i]) > 0.004
		if moved or not m.get("gfit_still", false):
			cur[0] = lerpf(cur[0], want[0], 1.0 - exp(-9.0 * md))
			var k := 1.0 - exp(-7.0 * md)
			for i in range(1, 5):
				cur[i] = lerpf(cur[i], want[i], k)
			m.gfit_still = not moved
	m.gfit = cur
	return cur


## `tr` set on the ground as `g` (_fit_at) says: tipped nose up/down and rolled, raised or lowered along its up.
static func _apply_fit(tr: Transform3D, g: PackedFloat32Array) -> Transform3D:
	var up := tr.basis.y.normalized()
	if absf(g[1]) + absf(g[2]) < 0.005:
		return Transform3D(tr.basis, tr.origin + up * g[0])       # (on a flat floor: only raised or lowered)
	var b := tr.basis.rotated(tr.basis.z.normalized(), g[1])
	b = b.rotated(b.x.normalized(), -g[2])
	return Transform3D(b, tr.origin + up * g[0])


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
const NECK := Vector2(0.46, 0.39)            # the head's and the gaster's joints (model units: ant_core K x design)
const WAIST := Vector2(-0.31, 0.36)
const GASTER_CURL := 0.1                    # the gaster's resting curl (tip down) in shaders/ants/ant_core.gdshaderinc
const BODY_PTS := [Vector3(0.9, 0.2, 0), Vector3(0, 0.2, 0), Vector3(-1.0, 0.2, 0), Vector3(0, 0.2, 0.3), Vector3(0, 0.2, -0.3)]


## For an ant drawn at `tr`: how far it must rise along its up for its body to clear a curving floor (x), and
## how many of its points are in soil that rising does not clear (y: its head or gaster in a wall - lifting
## would only float it; a resting ant turns away from the wall instead, see _free_heading).
func _soil_clearance(tr: Transform3D, s: float, bend := Vector2.ZERO, head_free := false) -> Vector2:
	var up := tr.basis.y.normalized()
	var need := 0.0
	var stuck := 0
	for i in BODY_PTS.size():
		if i == 0 and head_free:
			continue                       # (a digger's head is at the face it bites)
		var q: Vector3 = BODY_PTS[i]
		# (the head and gaster as bent at the neck and the waist: see ant_core.gdshaderinc)
		if i == 0 and bend.y != 0.0:
			var hq := (Vector2(q.x, q.y) - NECK).rotated(bend.y) + NECK
			q = Vector3(hq.x, hq.y, q.z)
		elif i == 2:
			# (the shader curls the gaster tip down 0.1 and lifts it by the bend: rot_z(0.1 - bend.x) about the waist -
			# this turned it the other way, by +bend.x, so a gaster bent down into a dip was checked as raised)
			var gq := (Vector2(q.x, q.y) - WAIST).rotated(GASTER_CURL - bend.x) + WAIST
			q = Vector3(gq.x, gq.y, q.z)
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


## Where a digger at cell c bites: the soil next to it the way it was going (dir), else the nearest soil beside or
## below it, else ahead of it.
func _dig_face(c: Vector3i, dir: Vector3i) -> Vector3:
	var order: Array = [dir, Vector3i(0, -1, 0)] + DIRS
	for d in order:
		var n: Vector3i = c + d
		if d != Vector3i.ZERO and nest.inside(n) and not nest.is_open(n):
			return Vector3(n)
	return Vector3(c + dir)


## Whether cell c is in a narrow tunnel (no room for two ants side by side): little open space round it.
## Cached per cell until the soil changes (in _fit_cache, under a key of its own).
func _cell_narrow(c: Vector3i) -> bool:
	var key := Vector3i(c.x, c.y - 100000, c.z)
	var v = _fit_cache.get(key)
	if v == null:
		var n := 0
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					if nest.is_open(c + Vector3i(dx, dy, dz)):
						n += 1
		v = n < 13
		_fit_cache[key] = v
	return v


var _near_bins := {}              # the nestmates binned by where they are drawn this frame (_update_ants)
## Whether a nestmate could stand at cell c without being on top of another ant, the brood or the queen (her
## body, and her legs reaching out beside it: an ant resting in them was pushed off into its neighbours).
func _cell_free(m: Dictionary, c: Vector3i) -> bool:
	return _cell_ok(c) and not _brood_wide.has(c) and _cell_room(m, c) >= ROOM_FREE


## Whether an ant could stand at cell c at all, nestmates aside: on a surface, off the queen and out of her
## legs, and with room for its body (not a narrow tunnel or a tight corner).
func _cell_ok(c: Vector3i) -> bool:
	if not _walkable(c) or _queen_cells.has(c):
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
		"giver", "groomer": near_to = m.get("near_to", Vector3.INF)       # (its partner: nest_duties)
	# a resting ant settles on the floor: walls and the ceiling only if nothing else is free nearby (ants do
	# walk on them, but a chamber full of ants resting upside down looked chaotic)
	var score := func(c: Vector3i, depth: int) -> float:
		var u: Vector3 = _up_at(c)
		var where := 0.0 if u.y > 0.85 else (2.5 if u.y > -0.3 else 5.0)     # (the crease where floor meets wall counts as wall: resting there it was neither on the one nor the other)
		return depth * 0.6 + where + (Vector3(c).distance_to(near_to) if near_to != Vector3.INF else 0.0)
	# the cells within reach along the walls (cheap), then those looked at for room best first (the room
	# around a cell - the nestmates near it - is the costly part: worked out only until a free one turns up)
	var parent := {start: start}
	var cands := [[score.call(start, 0) - 0.3, start]] if _cell_ok(start) and not _brood_wide.has(start) else []
	var frontier: Array[Vector3i] = [start]
	var floor_seen := false
	for depth in range(1, 11):            # (a crowded chamber: look a little further for room)
		# (by 7 steps it has looked round its own part of the chamber; further only if all it found is up on
		# the ceiling or a wall - ants coming in at the top of a chamber used to rest on its ceiling, the floor
		# being just out of reach)
		if depth > 7 and floor_seen:
			break
		var next: Array[Vector3i] = []
		for c in frontier:
			for d in DIRS:
				var n: Vector3i = c + d
				if parent.has(n) or not _walkable(n) or _queen_cells.has(n):
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
	if _on_brood(m) or float(m.get("over", 0.0)) > 0.05 and not m.has("over_on"):
		return true                    # (up on the pile: its drawn body is raised above the cells it is over)
	var x: Transform3D = m.xf
	var f: Vector3 = x.basis.x.normalized() * (0.7 * float(m.size))
	var pts: Array = [x.origin, x.origin - f] if _tends_brood(m) else [x.origin + f, x.origin, x.origin - f]
	for q in pts:
		if _brood_cells.has(Vector3i(roundi(q.x), roundi(q.y - 0.45), roundi(q.z))):
			return true
	return false
