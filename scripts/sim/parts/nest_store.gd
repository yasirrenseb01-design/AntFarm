extends "res://scripts/sim/parts/nest_voxels.gd"
## Underground nest, layer 2 of 4: taking in more soil below as the ants dig deep (extend_down), the nest's size,
## saving and loading. Split from nest_voxels.gd in v0.12.2 (it had grown past ~500 lines).


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


# ---------------------------------------------------------------- save / load

## Everything that affects how digging continues, so a loaded nest carries on exactly where it was.
func to_dict() -> Dictionary:
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
