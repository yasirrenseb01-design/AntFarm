extends RefCounted
## Underground nest: a block of soil voxels that workers excavate one bite at a time.
##
## Digging follows simple stigmergic rules seen in real Lasius:
##  - diggers are drawn to spots where nestmates dug recently (digging pheromone)
##  - tunnel tips are favoured over widening an existing tunnel, and digging trends downward
##  - inside a chamber site (around queen/brood) widening is allowed, but chambers stay flat
##  - the colony stops when the open volume matches its population (Buhl et al. 2004)
## Chambers are flat, elongated bulges along the galleries (Lasius: ~1–2 cm wide, 3–5 cm long, a few mm
## high, galleries 1.5–5 mm; Wang et al. 1995), with solid soil between them. Nobody plans them: they
## grow where workers crowd round brood (Römer & Roces 2014) — the plan here stands for that outcome.
## Each bite is carried up the tunnels and dropped on the surface, building the crater mound.

const VOXEL_MM := 1.5
const AIR := 128            # density below this is open space
const BITE := 128           # density removed per bite (two bites empty a voxel)
const STEP_EVERY := 4       # ticks per one-voxel move ≈ 0.37 mm/tick, the pace of surface ants
const CHUNK := 16
const DIG_TAU := 0.35 * 3600.0   # ticks for the digging pheromone to fade by 1/e
const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var nx := 64
var ny := 72
var nz := 64
var slab := false                       # true = thin glass ant-farm instead of a soil block
var rho := PackedByteArray()            # soil density 0..255 per voxel
var dug_at := PackedInt32Array()        # tick of the most recent bite at/near each voxel
var dist := PackedInt32Array()          # steps to the entrance through open space, -1 if cut off
var dirty: Dictionary = {}              # chunk coords (Vector3i) whose mesh must be rebuilt
var air := 0
var proj := PackedInt32Array()       # open voxels along z for each (x, y): the side-view outline
var excavated := 0                      # bites dumped on the surface
var chambers: Array = []                # {"c": Vector3, "r": float, "goal": float, "kind": String}
var diggers: Array = []                 # {"cell", "prev", "carry", "dir", "id"}
var entrance := Vector3i.ZERO
var tick := 0
var rng: RandomNumberGenerator
var _dist_age := 0
var _next_id := 0


func setup(r: RandomNumberGenerator, glass_slab := false, founding := false) -> void:
	rng = r
	slab = glass_slab
	if slab:
		nx = 110
		ny = 72
		nz = 5
	var n := nx * ny * nz
	rho.resize(n)
	rho.fill(255)
	dug_at.resize(n)
	dug_at.fill(-1000000)
	dist.resize(n)
	dist.fill(-1)
	entrance = Vector3i(nx / 2, ny - 1, nz - 2 if slab else nz / 2)
	# in a glass farm the ants work against the front pane; the back layers stay soil
	var mid := Vector3(nx / 2.0, 0, nz - 2.0 if slab else nz / 2.0)
	var flat := 2.9 if slab else 0.0
	if founding:
		# what a lone queen digs after her mating flight: a short shaft and one small chamber
		carve_line(Vector3(entrance), Vector3(mid.x, ny - 9, mid.z), 1.0)
		var fc := Vector3(mid.x + 1, ny - 11, mid.z)
		carve_ellipsoid(fc, Vector3(5.0, 2.2, 5.0 - (2.6 if slab else 0.0)))   # ~1.5 cm across
		chambers.append({"c": fc, "r": 5.0, "goal": 5.0, "kind": "queen"})
		_recount()
		_bfs()
		return
	# A three-month-old nest: the queen's shaft, her chamber, and a first brood chamber.
	carve_line(Vector3(entrance), Vector3(mid.x, ny - 18, mid.z), 1.2)
	var qc := Vector3(mid.x + 3, ny - 20, mid.z)
	carve_ellipsoid(qc, Vector3(4.5, 2.0, 4.5 - flat))
	chambers.append({"c": qc, "r": 4.5, "goal": 5.0, "kind": "queen"})
	var bc := Vector3(mid.x - 6, ny - 11, mid.z + (0.0 if slab else 2.0))
	carve_line(Vector3(mid.x, ny - 10, mid.z), bc, 1.1)
	carve_ellipsoid(bc, Vector3(4.0, 1.8, 4.0 - flat))
	chambers.append({"c": bc, "r": 4.0, "goal": 4.5, "kind": "brood"})
	_recount()
	_bfs()


# ---------------------------------------------------------------- voxel access

func idx(c: Vector3i) -> int:
	return (c.z * ny + c.y) * nx + c.x   # z-major: each z slice is contiguous (uploaded as a 3D texture layer)


func inside(c: Vector3i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < nx and c.y < ny and c.z < nz


func is_open(c: Vector3i) -> bool:
	return inside(c) and rho[idx(c)] < AIR


## Soil density as seen by the mesher: outside the block counts as air so the block gets faces.
func density(x: int, y: int, z: int) -> float:
	if x < 0 or y < 0 or z < 0 or x >= nx or y >= ny or z >= nz:
		return 0.0
	return rho[(z * ny + y) * nx + x] / 255.0


func walkable(c: Vector3i) -> bool:
	if not is_open(c):
		return false
	for d in DIRS:
		var n := c + d
		if not inside(n) or rho[idx(n)] >= AIR:
			return true
	return false


func carve_ellipsoid(center: Vector3, r: Vector3) -> void:
	for y in range(maxi(0, int(center.y - r.y)), mini(ny, int(center.y + r.y) + 2)):
		for z in range(maxi(0, int(center.z - r.z)), mini(nz, int(center.z + r.z) + 2)):
			for x in range(maxi(0, int(center.x - r.x)), mini(nx, int(center.x + r.x) + 2)):
				var q := (Vector3(x, y, z) - center) / r
				if q.length_squared() <= 1.0:
					rho[(z * ny + y) * nx + x] = 0
					_mark(Vector3i(x, y, z))


func carve_line(a: Vector3, b: Vector3, radius: float) -> void:
	var steps := int(a.distance_to(b) * 2.0) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		carve_ellipsoid(p, Vector3.ONE * radius)


func _mark(c: Vector3i) -> void:
	# surface nets reads one cell across chunk borders, so neighbours' chunks change too
	dirty[Vector3i(floori(c.x / float(CHUNK)), floori(c.y / float(CHUNK)), floori(c.z / float(CHUNK)))] = true
	for d in DIRS:
		var n := c + d
		dirty[Vector3i(floori(n.x / float(CHUNK)), floori(n.y / float(CHUNK)), floori(n.z / float(CHUNK)))] = true


func _recount() -> void:
	air = 0
	proj.resize(nx * ny)
	proj.fill(0)
	for z in nz:
		for y in ny:
			for x in nx:
				if rho[(z * ny + y) * nx + x] < AIR:
					air += 1
					proj[y * nx + x] += 1


func _bfs() -> void:
	dist.fill(-1)
	var q: Array[Vector3i] = [entrance]
	dist[idx(entrance)] = 0
	var head := 0
	while head < q.size():
		var c := q[head]
		head += 1
		var dc := dist[idx(c)]
		for d in DIRS:
			var n := c + d
			if inside(n):
				var i := idx(n)
				if dist[i] < 0 and rho[i] < AIR:
					dist[i] = dc + 1
					q.append(n)


func volume_cm3() -> float:
	return air * pow(VOXEL_MM / 10.0, 3.0)


func depth_cm() -> float:
	var deepest := ny
	for c in chambers:
		deepest = mini(deepest, int(c.c.y - c.r * 0.5))
	return (ny - deepest) * VOXEL_MM / 10.0


# ---------------------------------------------------------------- digging

func _dig_signal(c: Vector3i) -> float:
	var t := dug_at[idx(c)]
	return exp(-(tick - t) / DIG_TAU)


## Which part of the nest plan a voxel belongs to: 2 = inside a chamber, 1 = on a shaft toward a
## planned chamber, 0 = unplanned soil.
func _plan_at(c: Vector3i) -> int:
	var p := Vector3(c)
	var on_shaft := false
	for ch in chambers:
		if ch.get("open", true) and chamber_q(p, ch) <= 1.0:
			return 2
		if ch.has("from"):
			var a: Vector3 = ch.from
			var b: Vector3 = ch.c
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			if p.distance_to(a + ab * t) <= 1.3:
				on_shaft = true
	return 1 if on_shaft else 0


## Half-axes of a chamber's planned shape: long, wide (across), high. Flat: about two ants high.
func chamber_axes(ch: Dictionary) -> Vector3:
	var g: float = ch.goal
	if slab:     # seen edge-on against the glass: a room one ant-layer deep, so a little higher and shorter
		return Vector3(minf(g, 10.0), clampf(2.2 + g * 0.08, 2.2, 3.0), 1.0)
	return Vector3(g, clampf(1.7 + g * 0.06, 1.7, 2.4), maxf(2.6, g * 0.6))


## Where a point lies relative to a chamber's planned shape (<= 1 inside), turned to its heading.
func chamber_q(p: Vector3, ch: Dictionary) -> float:
	var d: Vector3 = p - ch.c
	var yaw: float = ch.get("yaw", 0.0)
	var ax := chamber_axes(ch)
	if slab:
		return Vector2(d.x / ax.x, d.y / ax.y).length_squared()     # one layer deep: no heading
	var u := d.x * cos(yaw) + d.z * sin(yaw)
	var v := -d.x * sin(yaw) + d.z * cos(yaw)
	return Vector3(u / ax.x, d.y / ax.y, v / ax.z).length_squared()


func _chamber_volume(ch: Dictionary) -> float:
	var ax := chamber_axes(ch)
	return 4.0 / 3.0 * PI * ax.x * ax.y * (1.0 if slab else ax.z)


## The bottom of the deepest chamber (voxel y).
func _lowest_chamber() -> float:
	var low := float(ny)
	for ch in chambers:
		low = minf(low, float(ch.c.y) - chamber_axes(ch).y)
	return low


func _dig_chance(s: Vector3i, from: Vector3i, humidity: float) -> float:
	if not inside(s) or rho[idx(s)] < AIR:
		return 0.0
	if slab and s.z < nz - 3:
		return 0.0
	# never break through the surface except around the entrance shaft
	if s.y >= ny - 2 and Vector2(s.x - entrance.x, s.z - entrance.z).length() > 1.5:
		return 0.0
	# loam near the surface is soft, the clay band below is stiff, sand deeper is loose
	var depth := ny - s.y
	var soft := 1.0 if depth < 14 else (0.45 if depth < 40 else 0.75)
	soft *= clampf(0.35 + humidity * 0.9, 0.3, 1.1)   # dry soil crumbles badly, damp soil holds shape
	var open_n := 0
	for d in DIRS:
		if is_open(s + d):
			open_n += 1
	var plan := _plan_at(s)
	var k := 0.03                                      # unplanned digging is rare: soil stays solid between chambers
	var from_room := plan == 0 and _plan_at(from) == 2   # the walls and floor of a finished chamber stay smooth
	if depth < 6 and Vector2(s.x - entrance.x, s.z - entrance.z).length() > 2.0:
		k = 0.1                                        # the surface crust is left intact around the shaft
	elif plan == 2:
		k = 4.0                                        # hollowing out a chamber
	elif plan == 1:
		k = 3.5                                        # sinking a shaft toward a planned chamber
	elif from_room:
		k = 0.005
	elif open_n >= 3:
		k = 0.05                                       # would widen a tunnel beyond ant width
	elif open_n == 1 and s.y < from.y:
		# an exploratory tunnel tip going down, but not far below the deepest chamber
		k = 0.25 if s.y > _lowest_chamber() - 7.0 else 0.003
	var dirk := 1.0
	if s.y < from.y:
		dirk = 1.6
	elif s.y > from.y:
		dirk = 0.3
	# fresh digging draws more digging, but only where there is a reason to dig (a chamber, a shaft)
	var lure := 4.0 if plan > 0 else 0.8
	return 0.05 * soft * k * dirk * (1.0 + lure * _dig_signal(s))


func _bite(s: Vector3i) -> void:
	var i := idx(s)
	var v := rho[i] - BITE
	rho[i] = maxi(0, v) if v >= AIR else 0      # once open, all of it is carried off (a smooth surface for the mesher)
	dug_at[i] = tick
	for d in DIRS:
		var n := s + d
		if inside(n):
			dug_at[idx(n)] = tick
	_mark(s)
	if rho[i] < AIR:
		air += 1
		proj[s.y * nx + s.x] += 1
		var best := -1
		for d in DIRS:
			var n := s + d
			if inside(n):
				var dn := dist[idx(n)]
				if dn >= 0 and (best < 0 or dn < best):
					best = dn
		dist[i] = best + 1 if best >= 0 else -1


func _spawn_digger() -> void:
	var start: Vector3i = Vector3i(chambers[rng.randi() % chambers.size()].c)
	if not is_open(start):
		start = entrance
	# settle onto the chamber floor
	while not walkable(start) and is_open(start + Vector3i(0, -1, 0)):
		start += Vector3i(0, -1, 0)
	diggers.append({"cell": start, "prev": start, "carry": false, "dir": Vector3i(0, -1, 0), "id": _next_id,
		"site": start, "back": false})
	_next_id += 1


## One digging step for every active digger. `wanted` = how many diggers the colony assigns.
func step(now: int, wanted: int, target_air: int, humidity: float) -> void:
	tick = now
	_dist_age += 1
	if _dist_age > 120:
		_dist_age = 0
		_bfs()
	while diggers.size() < wanted:
		_spawn_digger()
	if diggers.size() > wanted:
		for i in range(diggers.size() - 1, -1, -1):
			if diggers.size() <= wanted:
				break
			if not diggers[i].carry:
				diggers.remove_at(i)
	for d in diggers:
		_step_digger(d, target_air, humidity)


func _step_digger(d: Dictionary, target_air: int, humidity: float) -> void:
	var c: Vector3i = d.cell
	if d.carry:
		# climb the tunnels toward the entrance and drop the pellet on the mound
		var here := dist[idx(c)]
		if c == entrance or here <= 0:
			d.carry = false
			d.back = true          # head back down to the dig front it came from
			d.tries = 0
			excavated += 1
			d.dir = Vector3i(0, -1, 0)
			return
		var opts: Array[Vector3i] = []
		for dd in DIRS:
			var n := c + dd
			if inside(n):
				var dn := dist[idx(n)]
				if dn >= 0 and dn < here:
					opts.append(n)
		if not opts.is_empty():
			_move(d, opts[rng.randi() % opts.size()])
		return

	if d.back:
		var site: Vector3i = d.site
		d.tries = d.get("tries", 0) + 1
		if Vector3(c).distance_to(Vector3(site)) <= 2.0 or d.tries > 60:
			d.back = false
		else:
			# retrace: step to the open neighbour that is farther from the entrance and closer to the site
			var here := dist[idx(c)]
			var best_n := c
			var best_s := INF
			for dd in DIRS:
				var n := c + dd
				if not is_open(n):
					continue
				var s := Vector3(n).distance_to(Vector3(site)) - 0.5 * float(dist[idx(n)] > here)
				if n == d.prev:
					s += 1.5
				if s < best_s:
					best_s = s
					best_n = n
			if best_n != c:
				_move(d, best_n)
			return

	if air < target_air:
		var best := Vector3i.ZERO
		var best_p := 0.0
		for dd in DIRS:
			var p := _dig_chance(c + dd, c, humidity)
			if p > best_p:
				best_p = p
				best = c + dd
		if best_p > 0.0 and rng.randf() < best_p:
			_bite(best)
			d.carry = true
			d.site = c
			return

	# wander along the walls, drawn toward fresh digging and slightly downward
	var cands: Array[Vector3i] = []
	var weights: Array[float] = []
	var total := 0.0
	for dd in DIRS:
		var n := c + dd
		if not walkable(n):
			continue
		var w := 1.0 + 6.0 * _dig_signal(n)
		if dd == d.dir:
			w += 1.5
		if dd.y < 0:
			w += 0.6
		if n == d.prev:
			w *= 0.25
		cands.append(n)
		weights.append(w)
		total += w
	if cands.is_empty():
		# no wall within reach: drop down (gravity) or step into any open neighbour
		var below := c + Vector3i(0, -1, 0)
		if is_open(below):
			_move(d, below)
			return
		for dd in DIRS:
			if is_open(c + dd):
				_move(d, c + dd)
				return
		return
	var pick := rng.randf() * total
	for i in cands.size():
		pick -= weights[i]
		if pick <= 0.0:
			_move(d, cands[i])
			return
	_move(d, cands[cands.size() - 1])


func _move(d: Dictionary, n: Vector3i) -> void:
	d.dir = n - d.cell
	d.prev = d.cell
	d.cell = n


# ---------------------------------------------------------------- chambers

## Called by the colony once a day. Chambers grow while brood is crowded; a growing colony also
## plans a new chamber a little deeper and sinks a shaft down to it, giving the stacked layout of
## Lasius nests (flat chambers in series along vertical shafts).
func plan_chambers(brood: int, workers: int, target_air := 0) -> String:
	var event := ""
	for ch in chambers:
		if not ch.get("open", true) and is_open(Vector3i(ch.c)):
			ch.open = true
			event = "opened"
	# how big a chamber gets grows with the colony: ~1.5 cm long for a founding queen, up to ~4 cm
	var cap := clampf(5.0 + workers / 20.0, 5.0, 13.0)
	var planned := 0.0
	var floor_cap := 0.0
	for ch in chambers:
		planned += _chamber_volume(ch)
		if ch.get("open", true):
			var ax := chamber_axes(ch)
			floor_cap += PI * ax.x * (1.0 if slab else ax.z) * 1.5
	var load := brood + workers * 0.3
	var short := target_air > 0 and planned < target_air * 0.8      # the colony needs more room
	if load > floor_cap * 0.7 or short:
		# crowded brood: workers widen the chamber they crowd in (the smallest one that can still grow)
		var best := -1
		for i in chambers.size():
			var ch: Dictionary = chambers[i]
			if ch.get("open", true) and ch.goal < cap and (best < 0 or ch.goal < chambers[best].goal):
				best = i
		if best >= 0:
			chambers[best].goal = minf(cap, chambers[best].goal + 0.5)
			if event == "" and load > floor_cap * 0.7 and int(chambers[best].goal * 2.0) % 4 == 0:
				event = "grown"         # told now and then, not every day it grows
			return event
	var wanted := 1 if workers < 10 else 2          # a founding queen makes do with one chamber
	var pending := 0
	for ch in chambers:
		if not ch.get("open", true):
			pending += 1
	if pending > 0 or chambers.size() >= 24 or (chambers.size() >= wanted and not short):
		return event
	# a new chamber: beside an existing one on the same level (nests are top-heavy) or a level deeper,
	# reached by a gallery from the side of the old chamber
	for attempt in 60:
		var src: Dictionary = chambers[rng.randi() % chambers.size()]
		var depth: float = ny - float(src.c.y)
		var sideways := rng.randf() < (0.65 if depth < 30.0 else 0.35)
		var ang := rng.randf() * TAU
		var reach := rng.randf_range(src.goal + 8.0, src.goal + 14.0) if sideways else rng.randf_range(4.0, 12.0)
		var off := Vector3(cos(ang) * reach, rng.randf_range(-2.0, 1.0) if sideways else -rng.randf_range(8.0, 13.0), sin(ang) * reach)
		if slab:
			off.x = (reach if cos(ang) >= 0.0 else -reach) * (1.0 if sideways else 0.6)
			off.z = 0.0
		var site := Vector3(src.c) + off
		if site.x < 8 or site.x > nx - 9 or site.y < 6 or site.y > ny - 9 or site.z < (1 if slab else 8) or site.z > nz - (2 if slab else 9):
			continue
		var ok := true
		for ch in chambers:
			if site.distance_to(ch.c) < ch.goal + 9.0:
				ok = false
				break
		if ok:
			var dir := (site - Vector3(src.c)) * Vector3(1, 0, 1)
			var from: Vector3 = Vector3(src.c) + (dir.normalized() * float(src.goal) * 0.7 if dir.length() > 0.1 else Vector3.ZERO)
			chambers.append({"c": site, "r": 3.5, "goal": 3.5, "kind": "brood", "from": from, "open": false,
				"yaw": ang + rng.randf_range(-0.6, 0.6)})
			return "planned"
	return event


# ---------------------------------------------------------------- save / load

## Everything that affects how digging continues, so a loaded nest carries on exactly where it was.
func to_dict() -> Dictionary:
	return {"nx": nx, "ny": ny, "nz": nz, "slab": slab, "rho": rho, "dug_at": dug_at, "dist": dist,
		"excavated": excavated, "chambers": chambers, "diggers": diggers, "entrance": entrance, "tick": tick,
		"dist_age": _dist_age, "next_id": _next_id}


func from_dict(r: RandomNumberGenerator, d: Dictionary) -> void:
	rng = r
	nx = d.nx
	ny = d.ny
	nz = d.nz
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
	# nests dug before v0.8.2 left open voxels at half density, which drew as blocky steps
	for i in rho.size():
		if rho[i] < AIR:
			rho[i] = 0
	_recount()
