extends RefCounted
## settle_find (v0.12.28) against nest_rest._settle_on's search, the same lines here, for tests/native_guard_test.gd:
## a nest with tunnels cut at random, nestmates' bodies about it, the queen, cells under the brood and in her legs,
## and a stand-in for the view's _cell_fits (C++ asks it for a cell not yet in the cache, as the game's does).

const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const ROOM_FREE := 1.7
const QUEEN_R := 1.05

var nest
var _fit_cache := {}
var _queen_cells := {}
var _brood_wide := {}
var _mate_cells := {}
var _near_bins := {}
var queen_on := true
var qa := Vector3.ZERO
var qb := Vector3.ZERO


## The view's _cell_fits stand-in: some cells fit, some not, by the cell alone; kept in _fit_cache as the view does.
func _cell_fits(c: Vector3i) -> bool:
	var v := (c.x * 73 + c.y * 31 + c.z * 17) % 7 != 0
	_fit_cache[c] = v
	return v


func _walkable(c: Vector3i) -> bool:
	if not nest.is_open(c):
		return false
	for d in DIRS:
		var n: Vector3i = c + d
		if n.y >= nest.ny:
			continue
		if n.x < nest.x_lo or n.y < nest.y_lo or n.z < nest.z_lo or n.x >= nest.nx or n.z >= nest.nz:
			return true
		if nest.rho[((n.z - nest.z_lo) * (nest.ny - nest.y_lo) + n.y - nest.y_lo) * (nest.nx - nest.x_lo) + n.x - nest.x_lo] >= nest.AIR:
			return true
	return false


func _holds(n: Vector3i) -> bool:
	if nest.inside(n):
		return not nest.is_open(n)
	return n.y < nest.ny


func _up_at(c: Vector3i) -> Vector3:
	var u := Vector3.ZERO
	var first := Vector3.ZERO
	for d in DIRS:
		var n := c + d
		if _holds(n):
			u -= Vector3(d)
			if first == Vector3.ZERO:
				first = -Vector3(d)
	if u.length_squared() > 0.01:
		return u.normalized()
	return first if first != Vector3.ZERO else Vector3.UP


func _queen_gap(p: Vector3) -> float:
	var t := clampf((p - qa).dot(qb - qa) / maxf((qb - qa).length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(qa.lerp(qb, t)) - QUEEN_R


func _cell_ok(c: Vector3i) -> bool:
	if not _walkable(c) or _queen_cells.has(c):
		return false
	if queen_on and _queen_gap(Vector3(c)) < 1.35:
		return false
	var v = _fit_cache.get(c)
	return v if v != null else _cell_fits(c)


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


## nest_rest._settle_on from its search on: [found, best, path].
func settle_gd(m: Dictionary, start: Vector3i, near_to: Vector3) -> Array:
	var score := func(c: Vector3i, depth: int) -> float:
		var u: Vector3 = _up_at(c)
		var where := 0.0 if u.y > 0.85 else (2.5 if u.y > -0.3 else 5.0)
		return depth * 0.6 + where + (Vector3(c).distance_to(near_to) if near_to != Vector3.INF else 0.0)
	var parent := {start: start}
	var cands := [[score.call(start, 0) - 0.3, start]] if _cell_ok(start) and not _brood_wide.has(start) else []
	var frontier: Array[Vector3i] = [start]
	var floor_seen := false
	for depth in range(1, 11):
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
	cands.sort_custom(func(x, y): return x[0] < y[0])
	var best := Vector3i(-9999, 0, 0)
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
			return [false, start, []]
		best = roomy
	if best == start:
		return [true, best, []]
	var path := []
	var c := best
	while c != start:
		path.push_front(c)
		c = parent[c]
	return [true, best, path]


func ctx() -> Array:
	return [nest.rho, PackedInt32Array([nest.x_lo, nest.y_lo, nest.z_lo, nest.nx, nest.ny, nest.nz, nest.AIR]), _queen_cells,
		queen_on, qa, qb, QUEEN_R, _fit_cache, _brood_wide, _mate_cells, _near_bins, self]


## Runs the comparison: [cases, same, with a path, none found].
func run(nat: Object, s) -> Array:
	nest = s.nest
	var r := RandomNumberGenerator.new()
	r.seed = 21
	# tunnels and chambers: runs of open cells, a few blocks of them
	for i in 400:
		var c := Vector3i(r.randi_range(nest.x_lo, nest.nx - 1), r.randi_range(nest.y_lo, nest.ny - 1), r.randi_range(nest.z_lo, nest.nz - 1))
		var w := r.randi_range(1, 4)
		for dx in w:
			for dy in mini(w, 2):
				for dz in w:
					var d := c + Vector3i(dx, dy, dz)
					if nest.inside(d):
						nest.rho[((d.z - nest.z_lo) * (nest.ny - nest.y_lo) + d.y - nest.y_lo) * (nest.nx - nest.x_lo) + d.x - nest.x_lo] = 0
	var open := []
	for z in range(nest.z_lo, nest.nz):
		for y in range(nest.y_lo, nest.ny):
			for x in range(nest.x_lo, nest.nx):
				var c := Vector3i(x, y, z)
				if _walkable(c):
					open.append(c)
	var cases := 0
	var same := 0
	var paths := 0
	var none := 0
	var asks := 0
	for round in 40:
		_fit_cache.clear()
		_queen_cells.clear()
		_brood_wide.clear()
		_mate_cells.clear()
		_near_bins.clear()
		queen_on = round % 3 != 0
		var qc: Vector3 = Vector3(open[r.randi() % open.size()])
		qa = qc + Vector3(1.25, 0.5, 0.0)
		qb = qc + Vector3(-1.45, 0.5, 0.0)
		for k in 6:
			_queen_cells[Vector3i(qc) + Vector3i(k - 3, 0, 0)] = true
		for k in 30:
			_brood_wide[open[r.randi() % open.size()]] = true
		for k in 120:                      # (some cells looked at before: in the cache already)
			_cell_fits(open[r.randi() % open.size()])
		var mates := []
		for k in 200:
			var c: Vector3i = open[r.randi() % open.size()]
			var p := Vector3(c) + Vector3(r.randf_range(-0.5, 0.5), -0.4, r.randf_range(-0.5, 0.5))
			var f := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized() * 0.7
			var m := {"cell": c, "d0": p + f, "d1": p - f * 1.2}
			if r.randf() < 0.05:
				m.erase("d0")
			mates.append(m)
			if r.randf() < 0.8:
				_mate_cells[c] = m
			var key := Vector3i(floori(p.x / 3.0), floori(p.y / 3.0), floori(p.z / 3.0))
			if not _near_bins.has(key):
				_near_bins[key] = []
			_near_bins[key].append(m)
		for k in 50:
			var m: Dictionary = mates[r.randi() % mates.size()]
			var near_to: Vector3 = Vector3.INF if r.randf() < 0.5 else Vector3(open[r.randi() % open.size()])
			# (C++ first: the cells it asks the view about are not in the cache yet - its call back to _cell_fits is tried)
			var asked := _fit_cache.size()
			var got: Array = nat.settle_find(m, m.cell, near_to, ctx())
			asks += _fit_cache.size() - asked
			var want := settle_gd(m, m.cell, near_to)
			cases += 1
			if bool(got[0]) == bool(want[0]) and got[1] == want[1] and got[2] == want[2]:
				same += 1
			if not (want[2] as Array).is_empty():
				paths += 1
			if not want[0]:
				none += 1
	return [cases, same, paths, none, asks]
