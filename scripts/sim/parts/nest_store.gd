extends "res://scripts/sim/parts/nest_ground.gd"
## Underground nest, layer 3 of 6: taking in more soil below as the ants dig deep (extend_down), the nest's size, the
## steps to the work face (_work_paths, work_d), saving and loading. Split from nest_voxels.gd in v0.12.2 (it had grown past ~500 lines).


## Takes in the soil down to layer y (whole chunks of EXTEND_BY, never below y_floor): the ants dig near the bottom
## of what is held. Every per-voxel array is laid out again with the new layers (solid, never dug) under the old.
## Returns whether anything was added.
func extend_down(y: int) -> bool:
	var to := maxi(y_floor, y_lo - EXTEND_BY * maxi(1, ceili(float(y_lo - y) / EXTEND_BY)))
	if to >= y_lo:
		return false
	var add := y_lo - to
	var h0 := hy()
	var h1 := h0 + add
	var grow := func(a, fill_v):
		var b = a.duplicate()
		var w := wx()
		b.resize(w * h1 * wz())
		b.fill(fill_v)
		if a.size() == w * h0 * wz():
			for z in wz():
				for yy in h0:
					var s0: int = (z * h0 + yy) * w
					var d0: int = (z * h1 + yy + add) * w
					for x in w:
						b[d0 + x] = a[s0 + x]
		return b
	rho = grow.call(rho, 255)
	dug_at = grow.call(dug_at, -1000000)
	dist = grow.call(dist, -1)
	finish_work_paths()                  # (the search goes on in the soil it began with: finished first)
	if not work_dist.is_empty():
		work_dist = grow.call(work_dist, -1)
	y_lo = to
	_recount()
	_stamp_hard()
	for cz in range(floori(z_lo / float(CHUNK)), ceili(nz / float(CHUNK)) + 1):
		for cy in range(floori(to / float(CHUNK)) - 1, floori((to + add) / float(CHUNK)) + 1):
			for cx in range(floori(x_lo / float(CHUNK)), ceili(nx / float(CHUNK)) + 1):
				dirty[Vector3i(cx, cy, cz)] = true
	resized += 1
	return true


## Takes in the tank's soil sideways (PART 0.12 step 5c) so the box held covers lo .. hi (x, z) with SIDE_ROOM to spare,
## in whole chunks, never past the tank's sides (tank: 0 = the box cannot grow). The ants plan a chamber out there: the
## soil is taken in first, as extend_down does below. Every per-voxel array is laid out again round the old (the new
## soil solid, never dug). Returns whether anything was added. (No stones or roots in it yet: BACKLOG.)
const SIDE_ROOM := 12
var tank := Vector2i.ZERO               # the tank's soil, columns and slices (Simulation._nest_in_tank; not saved)

func extend_xz(lo: Vector2, hi: Vector2) -> bool:
	if tank == Vector2i.ZERO or slab:
		return false
	var c := CHUNK
	var x0 := clampi(mini(x_lo, floori((lo.x - SIDE_ROOM) / c) * c), 0, x_lo)
	var x1 := clampi(maxi(nx, ceili((hi.x + SIDE_ROOM) / c) * c), nx, tank.x)
	var z0 := clampi(mini(z_lo, floori((lo.y - SIDE_ROOM) / c) * c), 0, z_lo)
	var z1 := clampi(maxi(nz, ceili((hi.y + SIDE_ROOM) / c) * c), nz, tank.y)
	if x0 == x_lo and x1 == nx and z0 == z_lo and z1 == nz:
		return false
	finish_work_paths()                  # (the search goes on in the soil it began with: finished first)
	var h := hy()
	var w0 := wx()
	var d0 := wz()
	var w1 := x1 - x0
	var d1 := z1 - z0
	var left := x_lo - x0
	var front := z_lo - z0
	# row by row, the old rows with new soil either side of them (append_array: the engine copies, ~nothing in GDScript)
	var grow := func(a, blank):
		var row_new = blank.duplicate()
		row_new.resize(w1)
		var fill_v = blank[0]
		row_new.fill(fill_v)
		var l = blank.duplicate()
		l.resize(left)
		l.fill(fill_v)
		var r = blank.duplicate()
		r.resize(w1 - left - w0)
		r.fill(fill_v)
		var b = blank.duplicate()
		b.resize(0)
		for z in d1:
			var oz: int = z - front
			for y in h:
				if oz < 0 or oz >= d0:
					b.append_array(row_new)
				else:
					var s: int = (oz * h + y) * w0
					b.append_array(l)
					b.append_array(a.slice(s, s + w0))
					b.append_array(r)
		return b
	rho = grow.call(rho, PackedByteArray([255]))
	dug_at = grow.call(dug_at, PackedInt32Array([-1000000]))
	dist = grow.call(dist, PackedInt32Array([-1]))
	if not work_dist.is_empty():
		work_dist = grow.call(work_dist, PackedInt32Array([-1]))
	var old := Rect2i(x_lo, z_lo, w0, d0)
	x_lo = x0
	nx = x1
	z_lo = z0
	nz = z1
	_recount()
	_stamp_hard()
	# the soil's pieces that change (the mesher's chunks): the box's old sides and its new ones, all the way down, and
	# the ground's surface over the soil taken in; the new soil under it is solid all through - nothing drawn there
	# (every chunk of the new box: ~1,200 for a 1,260-ant nest grown 40 voxels, ~25 s before the view had laid them out)
	var top := Vector2i(floori((ny - 2) / float(CHUNK)), floori(ny / float(CHUNK)))
	var ylo := floori(y_lo / float(CHUNK)) - 1
	var yhi := ceili(ny / float(CHUNK))
	var side := func(v: int, a: int, b: int) -> bool:          # (a chunk along x or z that holds a side at a or b)
		return absi(v - floori(a / float(CHUNK))) <= 1 or absi(v - floori((b - 1) / float(CHUNK))) <= 1
	for cz in range(floori(z_lo / float(CHUNK)) - 1, ceili(nz / float(CHUNK)) + 1):
		for cx in range(floori(x_lo / float(CHUNK)) - 1, ceili(nx / float(CHUNK)) + 1):
			var in_old_x: bool = cx >= floori(old.position.x / float(CHUNK)) - 1 and cx <= floori((old.end.x - 1) / float(CHUNK)) + 1
			var in_old_z: bool = cz >= floori(old.position.y / float(CHUNK)) - 1 and cz <= floori((old.end.y - 1) / float(CHUNK)) + 1
			var at_side: bool = side.call(cx, x_lo, nx) or side.call(cz, z_lo, nz) \
				or (in_old_z and side.call(cx, old.position.x, old.end.x)) or (in_old_x and side.call(cz, old.position.y, old.end.y))
			var new_soil := not old.has_point(Vector2i(cx * CHUNK, cz * CHUNK)) or not old.has_point(Vector2i(cx * CHUNK + CHUNK - 1, cz * CHUNK + CHUNK - 1))
			if at_side:
				for cy in range(ylo, yhi + 1):
					dirty[Vector3i(cx, cy, cz)] = true
			elif new_soil:
				for cy in range(top.x, top.y + 1):
					dirty[Vector3i(cx, cy, cz)] = true
	resized += 1
	return true


var resized := 0                        # counts extend_down (the view lays out its volumes again)


func volume_cm3() -> float:
	return air * pow(VOXEL_MM / 10.0, 3.0)


func depth_cm() -> float:
	var deepest := ny
	for c in chambers:
		deepest = mini(deepest, int(c.c.y - c.r * 0.5))
	return (ny - deepest) * VOXEL_MM / 10.0


# ---------------------------------------------------------------- the way to the work face

## Steps from every voxel an ant can walk to (along the walls) to work_at, so diggers walk the tunnels to it.
## (Worked out as far as it is asked, v0.12.3: work_d() goes on with the search until the voxel asked has its steps, from
## the soil as it was when it began - kept in _wp_rho - so every answer is the one the whole search made at once gave; the
## rest is finished before the nest is saved or resized. It was ~12 ms a time, ~23 times a game day while the colony dug,
## and the diggers ask about a few voxels near them.)
var _wp_q := PackedInt32Array()          # the search's queue: _wp_h .. _wp_t still to look round
var _wp_h := 0
var _wp_t := 0
var _wp_rho := PackedByteArray()         # the soil it searches: a copy of rho as it was when the search began
var _wp_dims := Vector3i.ZERO            # columns, rows, slices held when it began (wx, hy, wz)


func _work_paths() -> void:
	work_dist.resize(wx() * hy() * wz())
	work_dist.fill(-1)
	_wp_h = 0
	_wp_t = 0
	_wp_rho = PackedByteArray()
	if work_at.x < 0 or not inside(work_at) or not is_open(work_at):
		return
	_wp_rho = rho.duplicate()             # (a copy: a packed array assigned is the same array, and the diggers bite on)
	_wp_dims = Vector3i(wx(), ny - y_lo, wz())
	_wp_q.resize(work_dist.size())
	var first := idx(work_at)
	work_dist[first] = 0
	_wp_q[0] = first
	_wp_t = 1


## Steps from voxel i to work_at (-1: not reached), the search taken on as far as needed.
func work_d(i: int) -> int:
	var v := work_dist[i]
	if v >= 0 or _wp_h >= _wp_t or _wp_rho[i] >= AIR:
		return v                           # (solid soil is never reached: only open voxels are searched)
	_wp_more(i)
	return work_dist[i]


## The whole of work_dist, as the search made at once gave it.
func finish_work_paths() -> void:
	if _wp_h < _wp_t:
		_wp_more(-1)


## The breadth-first search along flat indices (idx()'s layout: ~55 ms each game day through inside/is_open/idx for every
## neighbour, v0.11.89), until voxel `until` has its steps (-1: to the end). A voxel's steps are final once it is queued.
func _wp_more(until: int) -> void:
	var nxx := _wp_dims.x
	var rows := _wp_dims.y
	var nzz := _wp_dims.z
	var up := nxx
	var back := rows * nxx
	var d := work_dist
	work_dist = PackedInt32Array()          # (so writing d copies nothing)
	var q := _wp_q
	_wp_q = PackedInt32Array()
	var r := _wp_rho
	var h := _wp_h
	var t := _wp_t
	while h < t:
		if until >= 0 and d[until] >= 0:
			break
		var i: int = q[h]
		h += 1
		var dc: int = d[i] + 1
		var x := i % nxx
		var row := i / nxx
		var yy := row % rows
		var zz := row / rows
		if x + 1 < nxx and r[i + 1] < AIR and d[i + 1] < 0:
			d[i + 1] = dc
			q[t] = i + 1
			t += 1
		if x > 0 and r[i - 1] < AIR and d[i - 1] < 0:
			d[i - 1] = dc
			q[t] = i - 1
			t += 1
		if yy + 1 < rows and r[i + up] < AIR and d[i + up] < 0:
			d[i + up] = dc
			q[t] = i + up
			t += 1
		if yy > 0 and r[i - up] < AIR and d[i - up] < 0:
			d[i - up] = dc
			q[t] = i - up
			t += 1
		if zz + 1 < nzz and r[i + back] < AIR and d[i + back] < 0:
			d[i + back] = dc
			q[t] = i + back
			t += 1
		if zz > 0 and r[i - back] < AIR and d[i - back] < 0:
			d[i - back] = dc
			q[t] = i - back
			t += 1
	work_dist = d
	_wp_q = q
	_wp_h = h
	_wp_t = t
	if h >= t:
		_wp_rho = PackedByteArray()        # (done: the soil is not held on to)


# ---------------------------------------------------------------- save / load

## Everything that affects how digging continues, so a loaded nest carries on exactly where it was.
func to_dict() -> Dictionary:
	finish_work_paths()
	return {"nx": nx, "ny": ny, "nz": nz, "x_lo": x_lo, "z_lo": z_lo, "y_lo": y_lo, "y_floor": y_floor, "slab": slab, "rho": rho, "dug_at": dug_at, "dist": dist,
		"excavated": excavated, "chambers": chambers, "diggers": diggers, "entrance": entrance, "tick": tick,
		"dist_age": _dist_age, "next_id": _next_id, "entrance_r": entrance_r, "work_left": work_left, "work_at": work_at, "work_dist": work_dist, "entrance_done": entrance_done,
		"soil": soil, "exits": exits}


func from_dict(r: RandomNumberGenerator, d: Dictionary) -> void:
	rng = r
	nx = d.nx
	ny = d.ny
	nz = d.nz
	# (saves before v0.11.29: the soil ended at y = 0)
	y_lo = int(d.get("y_lo", 0))                      # (checked: save_check._sizes)
	y_floor = int(d.get("y_floor", y_lo))
	x_lo = int(d.get("x_lo", 0))                      # (saves before v0.12.17: the block from 0; checked: save_check._sizes)
	z_lo = int(d.get("z_lo", 0))
	slab = d.slab
	rho = d.rho
	dug_at = d.dug_at
	dist = d.dist
	excavated = d.excavated
	chambers = d.chambers.duplicate(true)      # (copies: shift_xz moves them in place - a save's dictionary read twice,
	diggers = d.diggers.duplicate(true)        # as the tests do, was moved twice: v0.12.19)
	exits = []                                 # (saves before v0.12.21 have none; each one checked - a save is not trusted)
	var de = d.get("exits", [])
	for ex in de if de is Array else []:
		if ex is Dictionary and ex.get("a") is Vector3 and ex.get("b") is Vector3 and ex.get("open") is bool and exits.size() < 4 				and (ex.a as Vector3).is_finite() and (ex.b as Vector3).is_finite():
			exits.append({"a": ex.a, "b": ex.b, "open": ex.open})
	entrance = d.entrance
	tick = d.tick
	_dist_age = d.dist_age
	_next_id = d.next_id
	entrance_r = float(d.get("entrance_r", -1.0))       # (older saves: worked out by the simulation after loading)
	work_left = int(d.get("work_left", -1))
	work_at = d.get("work_at", Vector3i(-1, -1, -1))
	work_dist = d.get("work_dist", PackedInt32Array())
	entrance_done = float(d.get("entrance_done", 1.0))
	soil = {}
	var sd = d.get("soil", {})              # (saves before v0.11.18: plain soil)
	if sd is Dictionary:
		for k in ["clay", "sand"]:
			if sd.get(k) is float or sd.get(k) is int:
				soil[k] = clampf(float(sd[k]), 2.0, float(ny))
		for k in ["stones", "roots"]:
			var rows := []
			for row in sd.get(k, []) if sd.get(k) is Array else []:
				if row is Array and row.size() == (4 if k == "stones" else 7) and row.all(func(v): return v is float or v is int):
					rows.append(row.duplicate())
			soil[k] = rows.slice(0, 64)
	# nests dug before v0.8.2 left open voxels at half density, which drew as blocky steps
	for i in rho.size():
		if rho[i] < AIR:
			rho[i] = 0
	_recount()
	_stamp_hard()
