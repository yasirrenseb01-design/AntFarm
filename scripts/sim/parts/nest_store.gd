extends "res://scripts/sim/parts/nest_voxels.gd"
## Underground nest, layer 2 of 4: taking in more soil below as the ants dig deep (extend_down), the nest's size, the
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
		b.resize(nx * h1 * nz)
		b.fill(fill_v)
		if a.size() == nx * h0 * nz:
			for z in nz:
				for yy in h0:
					var s0: int = (z * h0 + yy) * nx
					var d0: int = (z * h1 + yy + add) * nx
					for x in nx:
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
	for cz in range(0, ceili(nz / float(CHUNK)) + 1):
		for cy in range(floori(to / float(CHUNK)) - 1, floori((to + add) / float(CHUNK)) + 1):
			for cx in range(0, ceili(nx / float(CHUNK)) + 1):
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
var _wp_dims := Vector3i.ZERO            # nx, rows, nz it began with


func _work_paths() -> void:
	work_dist.resize(nx * hy() * nz)
	work_dist.fill(-1)
	_wp_h = 0
	_wp_t = 0
	_wp_rho = PackedByteArray()
	if work_at.x < 0 or not inside(work_at) or not is_open(work_at):
		return
	_wp_rho = rho.duplicate()             # (a copy: a packed array assigned is the same array, and the diggers bite on)
	_wp_dims = Vector3i(nx, ny - y_lo, nz)
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
	return {"nx": nx, "ny": ny, "nz": nz, "y_lo": y_lo, "y_floor": y_floor, "slab": slab, "rho": rho, "dug_at": dug_at, "dist": dist,
		"excavated": excavated, "chambers": chambers, "diggers": diggers, "entrance": entrance, "tick": tick,
		"dist_age": _dist_age, "next_id": _next_id, "entrance_r": entrance_r, "work_left": work_left, "work_at": work_at, "work_dist": work_dist, "entrance_done": entrance_done,
		"soil": soil}


func from_dict(r: RandomNumberGenerator, d: Dictionary) -> void:
	rng = r
	nx = d.nx
	ny = d.ny
	nz = d.nz
	# (saves before v0.11.29: the soil ended at y = 0)
	y_lo = int(d.get("y_lo", 0))                      # (checked: save_check._sizes)
	y_floor = int(d.get("y_floor", y_lo))
	slab = d.slab
	rho = d.rho
	dug_at = d.dug_at
	dist = d.dist
	excavated = d.excavated
	chambers = d.chambers
	diggers = d.diggers
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
					rows.append(row)
			soil[k] = rows.slice(0, 64)
	# nests dug before v0.8.2 left open voxels at half density, which drew as blocky steps
	for i in rho.size():
		if rho[i] < AIR:
			rho[i] = 0
	_recount()
	_stamp_hard()
