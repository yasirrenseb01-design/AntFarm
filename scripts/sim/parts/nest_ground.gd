extends "res://scripts/sim/parts/nest_voxels.gd"
## Nest volume, layer 2 of 5 (split from parts/nest_voxels.gd in v0.12.17): what the soil holds besides earth - stones and
## roots the ants dig round, the clay and sand layers - laid out from the plot's seed and stamped into `hard`.
## Layers: parts/nest_voxels <- parts/nest_ground <- parts/nest_store <- parts/nest_chambers <- nest_volume.


# ---------------------------------------------------------------- what is in the soil

## Stones, roots and the depth of the clay for this colony's patch of ground (a generator of its own). Kept clear of
## what is dug already and of the entrance shaft. [inference: a garden's soil has pebbles and roots in it, and ants
## dig round them; the layer depths are chosen to differ by a few cm] Roots only in the garden (wild): a keeper's box of
## soil has none (the keeper, 2026-11-03: "the roots in the tank out - it is a plain box; and they did not look real").
func lay_out_soil(seed_v: int, wild := false) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = seed_v
	var stones := []
	var roots := []
	var mid := Vector2(entrance.x, entrance.z)
	var want := g.randi_range(12, 24)
	for attempt in 200:
		if stones.size() >= want:
			break
		var r := g.randf_range(1.6, 2.6) if g.randf() < 0.65 else g.randf_range(2.6, 4.8)       # 5-14 mm across
		var c := Vector3(g.randf_range(x_lo + r + 1.0, nx - 2.0 - r), g.randf_range(float(y_floor) + r + 2.0, ny - 4.0 - r),
			(nz - 2.5) if slab else g.randf_range(z_lo + r + 1.0, nz - 2.0 - r))
		if g.randf() < 0.6:
			# most where the nest is dug: within ~3 cm of the entrance shaft, in the top 8 cm
			c.x = clampf(mid.x + g.randf_range(-22.0, 22.0), x_lo + r + 1.0, nx - 2.0 - r)
			c.y = g.randf_range(ny - 55.0, ny - 6.0 - r)
			if not slab:
				c.z = clampf(mid.y + g.randf_range(-22.0, 22.0), z_lo + r + 1.0, nz - 2.0 - r)
		if Vector2(c.x, c.z).distance_to(mid) < r + 5.0 and c.y > ny - 30:
			continue                                   # (not in the way of the entrance shaft)
		if _open_near(c, r + 3.0):
			continue
		var clear := true
		for o in stones:
			if c.distance_to(Vector3(o[0], o[1], o[2])) < r + float(o[3]) + 2.0:
				clear = false
		if clear:
			stones.append([c.x, c.y, c.z, r])
	if wild:
		roots = _lay_out_roots(g, mid)
	var clay := g.randf_range(9.0, 20.0)
	soil = {"stones": stones, "roots": roots, "clay": clay, "sand": clay + g.randf_range(18.0, 34.0)}
	_stamp_hard()


const MAX_ROOTS := 32          # root segments held (soil.gdshader's arrays, nest_view's pieces)

## A plant's roots in the garden's soil, as roots grow (the keeper's drawing of root systems, 2026-11-03): one to three
## from the surface, each a tap root wandering down in a few segments that thin as they go, side roots branching off
## it out and down, and on some of those finer ones again - segments [a.xyz, b.xyz, radius], up to MAX_ROOTS.
## [inference: shapes after drawings of root systems; no measurement of a garden plant's roots by an ant nest]
func _lay_out_roots(g: RandomNumberGenerator, mid: Vector2) -> Array:
	var out := []
	var lo := Vector3(x_lo + 2, 3, 1 if slab else z_lo + 2)
	var hi := Vector3(nx - 3, ny - 1, nz - 2 if slab else nz - 3)
	var grow := func(from: Vector3, dir: Vector3, r: float, steps: int, seg_len: Vector2, spread: float) -> Array:
		var segs := []
		var p := from
		var d := dir
		for k in steps:
			if out.size() + segs.size() >= MAX_ROOTS or r < 0.12:
				break
			d = (d + Vector3(g.randf_range(-spread, spread), g.randf_range(-spread * 0.6, spread * 0.2),
				0.0 if slab else g.randf_range(-spread, spread))).normalized()
			if d.y > -0.15:
				d = (d + Vector3(0, -0.4, 0)).normalized()         # (roots go down)
			var q: Vector3 = (p + d * g.randf_range(seg_len.x, seg_len.y)).clamp(lo, hi)
			if q.distance_to(p) < 1.0 or _open_near(q, r + 1.5) or _open_near(p.lerp(q, 0.5), r + 1.5):
				break
			segs.append([p.x, p.y, p.z, q.x, q.y, q.z, r])
			p = q
			r *= 0.88
		return segs
	for i in g.randi_range(1, 3):
		var a := Vector3(g.randf_range(x_lo + 4.0, nx - 5.0), ny - 1.0, (nz - 2.5) if slab else g.randf_range(z_lo + 4.0, nz - 5.0))
		if Vector2(a.x, a.z).distance_to(mid) < 8.0:
			continue
		var tap: Array = grow.call(a, Vector3(g.randf_range(-0.3, 0.3), -1.0, 0.0 if slab else g.randf_range(-0.3, 0.3)).normalized(),
			g.randf_range(0.6, 0.9), g.randi_range(6, 9), Vector2(3.5, 6.0), 0.45)
		out.append_array(tap)
		# side roots from the tap root's joints, out to either side and down, some with finer ones on them
		for sg in tap:
			if out.size() >= MAX_ROOTS or g.randf() > 0.8:
				continue
			var at := Vector3(sg[3], sg[4], sg[5])
			var side := Vector3(g.randf_range(-1.0, 1.0), g.randf_range(-0.7, -0.2), 0.0 if slab else g.randf_range(-1.0, 1.0)).normalized()
			var branch: Array = grow.call(at, side, float(sg[6]) * 0.65, g.randi_range(2, 4), Vector2(2.5, 4.5), 0.6)
			out.append_array(branch)
			if not branch.is_empty() and g.randf() < 0.5 and out.size() < MAX_ROOTS:
				var b0: Array = branch[0]
				var fine := Vector3(g.randf_range(-1.0, 1.0), -0.5, 0.0 if slab else g.randf_range(-1.0, 1.0)).normalized()
				out.append_array(grow.call(Vector3(b0[3], b0[4], b0[5]), fine, float(b0[6]) * 0.65, 2, Vector2(2.0, 3.5), 0.7))
	return out.slice(0, MAX_ROOTS)


## Marks the stones' and roots' voxels hard (and solid) - in the layers held (y_lo up).
func _stamp_hard() -> void:
	hard.resize(wx() * hy() * wz())
	hard.fill(0)
	for s in soil.get("stones", []):
		var c := Vector3(s[0], s[1], s[2])
		var r: float = s[3]
		for y in range(maxi(y_lo, floori(c.y - r)), mini(ny, ceili(c.y + r) + 1)):
			for z in range(maxi(z_lo, floori(c.z - r)), mini(nz, ceili(c.z + r) + 1)):
				for x in range(maxi(x_lo, floori(c.x - r)), mini(nx, ceili(c.x + r) + 1)):
					if Vector3(x, y, z).distance_to(c) <= r:
						_harden(Vector3i(x, y, z))
	for rt in soil.get("roots", []):
		var a := Vector3(rt[0], rt[1], rt[2])
		var b := Vector3(rt[3], rt[4], rt[5])
		var r: float = rt[6]
		var ab := b - a
		var lo := Vector3i(floori(minf(a.x, b.x) - r), floori(minf(a.y, b.y) - r), floori(minf(a.z, b.z) - r))
		var hi := Vector3i(ceili(maxf(a.x, b.x) + r), ceili(maxf(a.y, b.y) + r), ceili(maxf(a.z, b.z) + r))
		for y in range(maxi(y_lo, lo.y), mini(ny, hi.y + 1)):
			for z in range(maxi(z_lo, lo.z), mini(nz, hi.z + 1)):
				for x in range(maxi(x_lo, lo.x), mini(nx, hi.x + 1)):
					var p := Vector3(x, y, z)
					var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
					if p.distance_to(a + ab * t) <= r:
						_harden(Vector3i(x, y, z))


func _harden(v: Vector3i) -> void:
	var i := idx(v)
	if rho[i] >= AIR:                      # (never where it is dug already)
		hard[i] = 1


## Any stone or root within r of p.
func hard_near(p: Vector3, r: float) -> bool:
	if hard.is_empty():
		return false
	for y in range(maxi(y_lo, floori(p.y - r)), mini(ny, ceili(p.y + r) + 1)):
		for z in range(maxi(z_lo, floori(p.z - r)), mini(nz, ceili(p.z + r) + 1)):
			for x in range(maxi(x_lo, floori(p.x - r)), mini(nx, ceili(p.x + r) + 1)):
				if hard[idx(Vector3i(x, y, z))] == 1 and Vector3(x, y, z).distance_to(p) <= r:
					return true
	return false


func _open_near(p: Vector3, r: float) -> bool:
	for y in range(maxi(y_lo, floori(p.y - r)), mini(ny, ceili(p.y + r) + 1)):
		for z in range(maxi(z_lo, floori(p.z - r)), mini(nz, ceili(p.z + r) + 1)):
			for x in range(maxi(x_lo, floori(p.x - r)), mini(nx, ceili(p.x + r) + 1)):
				if is_open(Vector3i(x, y, z)) and Vector3(x, y, z).distance_to(p) <= r:
					return true
	return false


## Where the stiff clay and the loose sand start (voxels below the surface).
func clay_top() -> float:
	return float(soil.get("clay", 14.0))


func sand_top() -> float:
	return float(soil.get("sand", 40.0))
