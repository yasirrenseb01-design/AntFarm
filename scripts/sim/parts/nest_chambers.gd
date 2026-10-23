extends "res://scripts/sim/parts/nest_voxels.gd"
## Nest volume, layer 2 of 3 (split from scripts/sim/nest_volume.gd in v0.8.5): the chamber plan
## (shapes, sizes, where new chambers go).

# the colony's digging habit (sim_state.traits depth / spread; set by the simulation, not saved with the nest)
var depth_k := 1.0
var spread_k := 1.0
# (and how its nest takes shape - hidden traits wind / lean / bush, never told the keeper: _plan_new)
var wind_k := 1.0
var lean_k := 1.0
var bush_k := 1.0
var heat_k := 1.0                 # (deeper under a hotter ground: set daily by the colony, sim_colony)


## Which part of the nest plan a voxel belongs to: 2 = inside a chamber, 1 = on a shaft toward a
## planned chamber, 0 = unplanned soil.
func _plan_at(c: Vector3i) -> int:
	var p := Vector3(c)
	var on_shaft := false
	# the entrance shaft down to the first chamber, widened as more ants use it
	if not chambers.is_empty() and entrance_r > 1.05:
		var ea := Vector3(entrance)
		var eb: Vector3 = chambers[0].c
		var eab := eb - ea
		var et := clampf((p - ea).dot(eab) / maxf(eab.length_squared(), 0.001), 0.0, 1.0)
		if p.distance_to(ea + eab * et) <= entrance_r and p.y < ny - 1:
			on_shaft = true
	for ch in chambers:
		if ch.get("open", true) and chamber_q(p, ch) <= 1.0:
			return 2
		if ch.has("from"):
			for seg in _gallery(ch):
				var a: Vector3 = seg[0]
				var ab: Vector3 = seg[1] - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
				if p.distance_to(a + ab * t) <= 1.3:
					on_shaft = true
	return 1 if on_shaft else 0


## How much planned soil is still solid (in chambers, the shafts to them, the entrance shaft): while any is
## left a few workers keep digging even when the nest is big enough overall (else a planned chamber
## was never finished and the colony stayed crowded in the old one). Counted once a day.
func count_work_left() -> int:
	var n := 0
	work_at = Vector3i(-1, -1, -1)
	var best := [1 << 30]
	for ch in chambers:
		# a chamber already found finished at its present size is not looked at again until it grows
		if ch.get("open", true) and float(ch.get("done", -1.0)) == float(ch.goal):
			continue
		var left := _work_in_chamber(ch, best)
		if left == 0 and ch.get("open", true):
			ch.done = ch.goal
		n += left
	if not chambers.is_empty() and entrance_r > 1.05 and entrance_done != entrance_r:
		var left := _work_on_line(Vector3(entrance), chambers[0].c, entrance_r, false, best)
		if left == 0:
			entrance_done = entrance_r
		n += left
	_work_paths()
	return n


## The gallery dug to a chamber, as straight pieces [[a, b], ...]: from the old chamber's wall to it - bent once on
## the way where the plan says (its "via"; older plans go straight).
static func _gallery(ch: Dictionary) -> Array:
	if ch.has("via"):
		return [[ch.from, ch.via], [ch.via, ch.c]]
	return [[ch.from, ch.c]]


## Planned soil still solid in one chamber (and, while it is not reached yet, the shaft to it). Updates the
## work face in best[0] (dist to the entrance; a new chamber's shaft first).
func _work_in_chamber(ch: Dictionary, best: Array) -> int:
	var n := 0
	if ch.has("from") and not ch.get("open", true):
		for seg in _gallery(ch):
			n += _work_on_line(seg[0], seg[1], 1.3, true, best)
	if not ch.get("open", true):
		return n
	var ax := chamber_axes(ch)
	var m := maxf(ax.x, ax.z) * _lobe_max(ch) + 1.0
	var c: Vector3 = ch.c
	for y in range(maxi(y_lo, floori(c.y - ax.y - 1.0)), mini(ny, ceili(c.y + ax.y + 1.0) + 1)):
		for z in range(maxi(0, floori(c.z - m)), mini(nz, ceili(c.z + m) + 1)):
			for x in range(maxi(0, floori(c.x - m)), mini(nx, ceili(c.x + m) + 1)):
				var v := Vector3i(x, y, z)
				if rho[idx(v)] >= AIR and not is_hard(v) and (not slab or z >= nz - 3) and chamber_q(Vector3(v), ch) <= 1.0:
					n += 1
					_face_at(v, 100000, best)
	return n


## Planned soil still solid along a shaft of radius r from a to b.
func _work_on_line(a: Vector3, b: Vector3, r: float, first: bool, best: Array) -> int:
	var n := 0
	var ab := b - a
	var lo := Vector3i(floori(minf(a.x, b.x) - r - 1.0), floori(minf(a.y, b.y) - r - 1.0), floori(minf(a.z, b.z) - r - 1.0))
	var hi := Vector3i(ceili(maxf(a.x, b.x) + r + 1.0), ceili(maxf(a.y, b.y) + r + 1.0), ceili(maxf(a.z, b.z) + r + 1.0))
	for y in range(maxi(y_lo, lo.y), mini(ny - 1, hi.y + 1)):
		for z in range(maxi(0, lo.z), mini(nz, hi.z + 1)):
			for x in range(maxi(0, lo.x), mini(nx, hi.x + 1)):
				var v := Vector3i(x, y, z)
				if rho[idx(v)] < AIR or (slab and z < nz - 3) or is_hard(v):
					continue
				# (the surface crust is never broken but at the entrance - _dig_chance; planned all the same, the top of
				# a slanting entrance shaft kept its diggers standing there a whole year, the nest never dug)
				if y >= ny - 2 and Vector2(x - entrance.x, z - entrance.z).length() > 1.5:
					continue
				var p := Vector3(v)
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
				if p.distance_to(a + ab * t) <= r:
					n += 1
					_face_at(v, 0 if first else 100000, best)
	return n


## Keeps in work_at the open voxel beside planned soil v nearest the entrance (pri added: lower goes first).
func _face_at(v: Vector3i, pri: int, best: Array) -> void:
	for dd in DIRS:
		var o: Vector3i = v + dd
		if inside(o) and is_open(o) and dist[idx(o)] >= 0 and dist[idx(o)] + pri < best[0]:
			best[0] = dist[idx(o)] + pri
			work_at = o


## Steps from every voxel an ant can walk to (along the walls) to work_at, so diggers walk the tunnels to it.
func _work_paths() -> void:
	work_dist.resize(nx * hy() * nz)
	work_dist.fill(-1)
	if work_at.x < 0 or not inside(work_at) or not is_open(work_at):
		return
	work_dist[idx(work_at)] = 0
	var q: Array[Vector3i] = [work_at]
	var h := 0
	while h < q.size():
		var c: Vector3i = q[h]
		h += 1
		var dc: int = work_dist[idx(c)]
		for dd in DIRS:
			var n: Vector3i = c + dd
			if inside(n) and is_open(n) and work_dist[idx(n)] < 0:
				work_dist[idx(n)] = dc + 1
				q.append(n)


## Half-axes of a chamber's planned shape: long, wide (across), high. Flat: about two ants high.
func chamber_axes(ch: Dictionary) -> Vector3:
	var g: float = ch.goal
	if slab:     # seen edge-on against the glass: a room one ant-layer deep, so a little higher and shorter
		return Vector3(minf(g, 10.0), clampf(2.2 + g * 0.08, 2.2, 3.0), 1.0)
	# (wide across as a share of its length: the swellings along an X-rayed L. niger tunnel are rounder than the
	# chambers planned before v0.11.30 - those keep their 0.6)
	if ch.has("round"):
		# (since v0.11.31 the new ones are swellings more than halls: shorter for their size and a little higher -
		# side on they looked like thin plates beside the X-rayed lumps; García Ibarra et al. 2024 Fig S2-S4)
		var l := g * 0.78
		return Vector3(l, clampf(2.0 + g * 0.08, 2.0, 2.8), maxf(2.6, l * float(ch.round)))
	return Vector3(g, clampf(1.7 + g * 0.06, 1.7, 2.4), maxf(2.6, g * float(ch.get("round", 0.6))))


## Where a point lies relative to a chamber's planned shape (<= 1 inside), turned to its heading.
func chamber_q(p: Vector3, ch: Dictionary) -> float:
	var d: Vector3 = p - ch.c
	var yaw: float = ch.get("yaw", 0.0)
	var ax := chamber_axes(ch)
	if slab:
		return room_q(Vector3(d.x / _lobe(ch, 0.0 if d.x >= 0.0 else PI), d.y, 0.0), ax)     # one layer deep: no heading
	var u := d.x * cos(yaw) + d.z * sin(yaw)
	var v := -d.x * sin(yaw) + d.z * cos(yaw)
	var f := _lobe(ch, atan2(v / ax.z, u / ax.x))
	return room_q(Vector3(u / f, d.y, v / f), ax)


## How far out a chamber's wall bulges toward angle a (round its middle, level), as a share of its plain oval: its
## "lobe" [amp, waves, phase, amp, waves, phase] - chambers swell unevenly, lobed as they are enlarged (Tschinkel
## 2015; the X-rayed L. niger chambers are lumps, not smooth ovals: García Ibarra et al. 2024). 1 = the oval.
static func _lobe(ch: Dictionary, a: float) -> float:
	var l: Array = ch.get("lobe", [])
	if l.size() < 6:
		return 1.0
	return 1.0 + float(l[0]) * cos(float(l[1]) * a + float(l[2])) + float(l[3]) * cos(float(l[4]) * a + float(l[5]))


## The farthest out a chamber's wall goes, as a share of its oval (bounds for looking over its cells).
static func _lobe_max(ch: Dictionary) -> float:
	var l: Array = ch.get("lobe", [])
	return 1.0 + (absf(float(l[0])) + absf(float(l[3])) if l.size() >= 6 else 0.0)


## Where a gallery leaves a chamber toward `dir` (level): at its wall, just inside it. Shafts down to lower
## chambers mostly leave the chamber above at its edge (Tschinkel 2011, casts of Aphaenogaster nests) - the ants
## walk on down the wall without crossing the middle of the floor, where the brood lies. (It left at 0.7 of the
## chamber's length that way: on the narrow sides of a long chamber that was well inside the floor.)
func _rim_toward(ch: Dictionary, dir: Vector3) -> Vector3:
	var c: Vector3 = ch.c
	if dir.length() < 0.1:
		return c
	var d := dir.normalized()
	var t := 0.0
	while t < float(ch.goal) + 4.0 and chamber_q(c + d * (t + 0.5), ch) <= 0.85:
		t += 0.5
	return c + d * t


func _chamber_volume(ch: Dictionary) -> float:
	var ax := chamber_axes(ch)
	return 4.0 / 3.0 * PI * ax.x * ax.y * (1.0 if slab else ax.z)


## The bottom of the deepest chamber (voxel y).
func _lowest_chamber() -> float:
	var low := float(ny)
	for ch in chambers:
		low = minf(low, float(ch.c.y) - chamber_axes(ch).y)
	return low


# ---------------------------------------------------------------- chambers

## How deep (voxels below the surface) the nest's lowest chamber reaches for a colony of this size, at most the
## block's depth. Young L. niger colonies of ~100 workers dug 13.7-19.3 cm down in soil columns, within the first
## week (García Ibarra et al. 2024: deeper with a warmer surface); nests sink as colonies grow (Tschinkel 2015).
## They went no deeper as they grew to 250-790 workers in the 100 days: depth rises only slowly with colony size here
## [inference: ~15 cm at 100 workers, ~11 cm at 10, ~17 cm at 300, ~19 cm at 1000 - at 10 cm a tenfold, the
## nests reached the bottom of the 30 cm soil and spread along it in a flat sheet]
func target_depth(workers: int) -> float:
	var cm := 15.0 + 4.0 * log(maxf(float(workers), 1.0) / 100.0) / log(10.0)
	return clampf(cm * depth_k * heat_k / (VOXEL_MM / 10.0), 0.0, float(ny - y_floor) - 6.0)


## Called by the colony once a day. Chambers grow while brood is crowded; a growing colony also
## plans a new chamber a little deeper and sinks a shaft down to it, giving the stacked layout of
## Lasius nests (flat chambers in series along vertical shafts).
func plan_chambers(brood: int, workers: int, target_air := 0) -> String:
	var event := ""
	# busier traffic: the entrance shaft is widened from one ant's width toward ~two (L. niger nest entrances are
	# a few mm across; the rate is chosen)
	# (never narrower again: a shaft dug wider does not close up when a worker dies - the plan shrinking under the
	# work counted in the morning left the diggers walking round a face with nothing on it to dig, all day)
	entrance_r = maxf(entrance_r, clampf(1.0 + workers * 0.012, 1.0, 1.7))
	for ch in chambers:
		# (its centre's nearest cell: the gallery ends at the centre, and cut down to the cell below and behind it
		# that cell lay outside the gallery - the chamber never opened, the colony stuck with two chambers all year)
		if not ch.get("open", true) and is_open(Vector3i((ch.c as Vector3).round())):
			ch.open = true
			event = "opened"
	# how big a chamber gets grows a little with the colony, ~1.8 cm long up to ~2.4 cm; a growing colony then adds
	# chambers rather than ever-bigger ones. (L. neoniger chambers are 1-2 cm wide, 3-5 cm long - Wang et al. 1995 - but
	# the X-rayed young L. niger nests show smaller swellings along the tunnel, a few mm high: García Ibarra et al. 2024;
	# up to ~3.3 cm they were wide flat discs that hid the tunnel between them [inference: between the two])
	# (and bigger in a big colony: with chambers too few or too small for its numbers the diggers made room anywhere,
	# and widened the tunnel to a trench - 500 workers, 2026-10-24)
	var cap := clampf(6.0 + workers / 80.0, 6.0, 11.0)
	# the first workers open up and widen the founding cell they share with the queen and her brood (~0.25 voxel
	# a worker) - only while it is the nest's one chamber; after that new chambers take the growth
	for ch in chambers:
		if chambers.size() == 1 and ch.get("kind", "") == "queen" and ch.get("open", true):
			var room_for := minf(cap, 6.0 + workers * 0.25)
			if ch.goal < room_for:
				ch.goal = minf(room_for, ch.goal + 0.5)
				return event
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
	# a growing colony sinks its nest deeper (new chambers below the deepest, down a shaft)
	var deeper := workers >= 20 and ny - _lowest_chamber() < target_depth(workers)
	if deeper:
		# (and room below the deepest chamber for another: at the bottom of the box the nest spreads out instead)
		var low_c := float(ny)
		for ch in chambers:
			low_c = minf(low_c, float(ch.c.y))
		deeper = low_c - 14.0 >= maxf(float(ny) - target_depth(workers), float(y_floor) + 8.0)
	var crowded := load > floor_cap * 0.7
	if pending > 0 or chambers.size() >= 44 or (chambers.size() >= wanted and not short and not crowded and not deeper):
		return event
	return _plan_new(deeper, workers, event)


## Where a new chamber goes: the shape of L. niger nests X-rayed in soil (García Ibarra et al. 2024, all 17 nests,
## Fig S2-S4) - one tunnel winding down from the entrance, chambers swelling along it like beads; it goes down
## fast, then the nest grows by side branches and chambers round its lower part (bushy at the bottom, in some a
## long level gallery there: an L or a T). A nest that reaches the bottom of its box spreads out along it the same
## way. How much the tunnel winds and slants and the nest branches is the colony's own habit (wind/lean/bush,
## hidden traits) - colonies alike in habit dig alike, never the same. (It used to place chambers round the old
## ones at a set distance, a stack under the entrance: every nest a column with petals; the keeper, 2026-10-23.)
func _plan_new(deeper: bool, workers: int, event: String) -> String:
	var deepest: Dictionary = chambers[0]
	for ch in chambers:
		if ch.c.y < deepest.c.y:
			deepest = ch
	var floor_y := maxf(float(ny) - target_depth(workers), float(y_floor) + 8.0)     # how far down it means to go (voxel y)
	var at_bottom := float(deepest.c.y) - 14.0 < floor_y             # no room for another bead below
	var low := chambers.filter(func(ch): return float(ch.c.y) < float(deepest.c.y) + 12.0)
	for attempt in 60:
		var bead := deeper and not at_bottom and attempt < 40
		var src: Dictionary = deepest
		if not bead:
			# a branch: off the lower part of the nest mostly (bushier with bush_k), else off the tunnel higher up
			# (the X-rayed nests grew bushy at the bottom; the tunnel above kept its few chambers - branching off it all
			# the way up, the nest looked like a ladder: the keeper, 2026-10-24)
			var pick: Array = low if rng.randf() < clampf(0.85 * bush_k, 0.6, 0.97) else chambers
			src = pick[rng.randi() % pick.size()]
		if not src.has("hd"):
			src.hd = rng.randf() * TAU                    # (the way its tunnel heads on, level)
		var hd: float = src.hd
		var site: Vector3
		if bead:
			# the next bead down: the tunnel bends a little its own way (wind) and slants off (lean)
			hd += rng.randfn(0.0, 1.1 * wind_k)
			# (the beads lie some 2-4 cm apart down the tunnel in the X-rayed nests - 1-1.6 cm, they stacked like a ladder)
			var drop := rng.randf_range(14.0, 26.0)
			var run := drop * clampf(rng.randfn(0.7, 0.3) * lean_k, 0.05, 2.4)
			site = Vector3(src.c) + Vector3(cos(hd) * run, -drop, sin(hd) * run)
		else:
			# a branch: off to the side, level or a little down (along the bottom where there is no more room)
			hd = rng.randf() * TAU
			# (a branch is a gallery out to a chamber, often long - the level runs at the bottom of the L- and T-shaped nests)
			# - or, as often in a bushy-habited nest, a chamber close beside it: the clusters at the bottom of A5, B6
			var near := rng.randf() < clampf(0.45 * bush_k, 0.15, 0.75)
			var reach := (rng.randf_range(float(src.goal) + 3.0, float(src.goal) + 8.0) if near
				else rng.randf_range(float(src.goal) + 8.0, float(src.goal) + 26.0)) * spread_k
			# (a little up or down at the bottom too: level every time, they lay in one flat sheet along it)
			var dy := rng.randf_range(-3.5, 3.0) if float(src.c.y) - 5.0 < floor_y else -rng.randf_range(0.0, 4.0)
			site = Vector3(src.c) + Vector3(cos(hd) * reach, dy, sin(hd) * reach)
		if slab:
			site = Vector3(src.c.x + (1.0 if cos(hd) >= 0.0 else -1.0) * Vector2(site.x - src.c.x, site.z - src.c.z).length(),
				site.y, src.c.z)
		if site.x < 8 or site.x > nx - 9 or site.y < y_floor + 6 or site.y > ny - 9 or site.z < (1 if slab else 8) or site.z > nz - (2 if slab else 9):
			continue
		if site.y - 10.0 < float(y_lo):
			extend_down(int(site.y) - 12)         # (the soil down there, taken in before it is planned in)
		if hard_near(site, 6.0):
			continue                                      # not on a stone or a root ...
		var from: Vector3 = _rim_toward(src, (site - Vector3(src.c)) * Vector3(1, 0, 1))
		# ... nor with one in the way of the gallery to it, which bends once on the way (wind)
		var side := (site - from).cross(Vector3.UP)
		side = side.normalized() if side.length() > 0.1 else Vector3.RIGHT
		if slab:
			side = Vector3(side.x, 0.0, 0.0).normalized() if absf(side.x) > 0.1 else Vector3.ZERO
		var via := from.lerp(site, rng.randf_range(0.35, 0.65)) + side * rng.randfn(0.0, 2.6 * wind_k)
		var ok := true
		for k in 7:
			if hard_near(from.lerp(via, k / 6.0), 2.0) or hard_near(via.lerp(site, k / 6.0), 2.0):
				ok = false
		for ch in chambers:
			# (clear of the other chambers: those about level with it by their length, those above or below by height)
			var dd: Vector3 = site - Vector3(ch.c)
			if absf(dd.y) < 6.0 and Vector2(dd.x, dd.z).length() < chamber_axes(ch).x + 4.0:
				ok = false
				break
		if ok:
			chambers.append({"c": site, "r": 3.5, "goal": 3.5, "kind": "brood", "from": from, "via": via, "open": false,
				"hd": hd, "yaw": hd + rng.randf_range(-0.6, 0.6), "round": rng.randf_range(0.65, 0.9),
				"lobe": [rng.randf_range(0.1, 0.28), float(rng.randi_range(2, 3)), rng.randf() * TAU,
					rng.randf_range(0.05, 0.16), float(rng.randi_range(4, 5)), rng.randf() * TAU]})
			return "planned"
	return event
