extends "res://scripts/sim/parts/nest_voxels.gd"
## Nest volume, layer 2 of 3 (split from scripts/sim/nest_volume.gd in v0.8.5): the chamber plan
## (shapes, sizes, where new chambers go).

# the colony's digging habit (sim_state.traits depth / spread; set by the simulation, not saved with the nest)
var depth_k := 1.0
var spread_k := 1.0


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
			var a: Vector3 = ch.from
			var b: Vector3 = ch.c
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
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


## Planned soil still solid in one chamber (and, while it is not reached yet, the shaft to it). Updates the
## work face in best[0] (dist to the entrance; a new chamber's shaft first).
func _work_in_chamber(ch: Dictionary, best: Array) -> int:
	var n := 0
	if ch.has("from") and not ch.get("open", true):
		n += _work_on_line(ch.from, ch.c, 1.3, true, best)
	if not ch.get("open", true):
		return n
	var ax := chamber_axes(ch)
	var m := maxf(ax.x, ax.z) + 1.0
	var c: Vector3 = ch.c
	for y in range(maxi(0, floori(c.y - ax.y - 1.0)), mini(ny, ceili(c.y + ax.y + 1.0) + 1)):
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
	for y in range(maxi(0, lo.y), mini(ny - 1, hi.y + 1)):
		for z in range(maxi(0, lo.z), mini(nz, hi.z + 1)):
			for x in range(maxi(0, lo.x), mini(nx, hi.x + 1)):
				var v := Vector3i(x, y, z)
				if rho[idx(v)] < AIR or (slab and z < nz - 3) or is_hard(v):
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
	work_dist.resize(nx * ny * nz)
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
	return Vector3(g, clampf(1.7 + g * 0.06, 1.7, 2.4), maxf(2.6, g * 0.6))


## Where a point lies relative to a chamber's planned shape (<= 1 inside), turned to its heading.
func chamber_q(p: Vector3, ch: Dictionary) -> float:
	var d: Vector3 = p - ch.c
	var yaw: float = ch.get("yaw", 0.0)
	var ax := chamber_axes(ch)
	if slab:
		return room_q(Vector3(d.x, d.y, 0.0), ax)     # one layer deep: no heading
	var u := d.x * cos(yaw) + d.z * sin(yaw)
	var v := -d.x * sin(yaw) + d.z * cos(yaw)
	return room_q(Vector3(u, d.y, v), ax)


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

## How deep (voxels below the surface) the nest's lowest chamber reaches for a colony of this size: the nest
## sinks as the colony grows (nest depth rises with colony size in the ants studied, e.g. Tschinkel 2004;
## Lasius nests mostly lie in the top ~30 cm with a few deep shafts). The curve is an estimate fitted to this
## 10.8 cm block: ~1.7 cm founding, ~5 cm at 100 workers, ~6.6 cm at 300, ~8 cm at 1000.
func target_depth(workers: int) -> float:
	return minf((11.0 + 22.0 * log(1.0 + workers / 10.0) / log(10.0)) * depth_k, ny - 8.0)


## Called by the colony once a day. Chambers grow while brood is crowded; a growing colony also
## plans a new chamber a little deeper and sinks a shaft down to it, giving the stacked layout of
## Lasius nests (flat chambers in series along vertical shafts).
func plan_chambers(brood: int, workers: int, target_air := 0) -> String:
	var event := ""
	# busier traffic: the entrance shaft is widened from one ant's width toward ~two (L. niger nest entrances are
	# a few mm across; the rate is chosen)
	entrance_r = clampf(1.0 + workers * 0.012, 1.0, 1.7)
	for ch in chambers:
		if not ch.get("open", true) and is_open(Vector3i(ch.c)):
			ch.open = true
			event = "opened"
	# how big a chamber gets grows with the colony: ~1.5 cm long for a founding queen, up to ~3.3 cm (Lasius
	# chambers are 1-2 cm wide, 3-5 cm long); a growing colony then adds chambers rather than ever-bigger ones
	var cap := clampf(7.0 + workers / 12.0, 7.0, 11.0)        # the first workers soon need more than the founding cell
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
	var crowded := load > floor_cap * 0.7
	if pending > 0 or chambers.size() >= 24 or (chambers.size() >= wanted and not short and not crowded and not deeper):
		return event
	# a new chamber: beside an existing one on the same level (nests are top-heavy) or a level deeper,
	# reached by a gallery from the side of the old chamber
	var deepest: Dictionary = chambers[0]
	for ch in chambers:
		if ch.c.y < deepest.c.y:
			deepest = ch
	for attempt in 60:
		var src: Dictionary = deepest if deeper else chambers[rng.randi() % chambers.size()]
		var depth: float = ny - float(src.c.y)
		var sideways := false if deeper else rng.randf() < minf(0.92, (0.65 if depth < 30.0 else 0.35) * spread_k)
		var ang := rng.randf() * TAU
		var reach := rng.randf_range(src.goal + 8.0, src.goal + 14.0) if sideways else rng.randf_range(4.0, 12.0)
		var off := Vector3(cos(ang) * reach, rng.randf_range(-2.0, 1.0) if sideways else -rng.randf_range(8.0, 13.0), sin(ang) * reach)
		if slab:
			off.x = (reach if cos(ang) >= 0.0 else -reach) * (1.0 if sideways else 0.6)
			off.z = 0.0
		var site := Vector3(src.c) + off
		if site.x < 8 or site.x > nx - 9 or site.y < 6 or site.y > ny - 9 or site.z < (1 if slab else 8) or site.z > nz - (2 if slab else 9):
			continue
		var ok := not hard_near(site, 6.0)            # not on a stone or a root ...
		var src_rim: Vector3 = _rim_toward(src, (site - Vector3(src.c)) * Vector3(1, 0, 1))
		for k in 7:
			if ok and hard_near(src_rim.lerp(site, k / 6.0), 2.0):
				ok = false                            # ... nor with one in the way of the gallery to it
		for ch in chambers:
			# chambers are flat (~2 voxels high): one 7+ voxels below another clears it whatever its width, so
			# only chambers on about the same level must keep their width apart (a straight distance against
			# the old chamber's width ruled out every chamber below a grown one: nests never got deeper)
			var dd: Vector3 = site - Vector3(ch.c)
			if absf(dd.y) < 7.0 and Vector2(dd.x, dd.z).length() < ch.goal + 9.0:
				ok = false
				break
		if ok:
			var dir := (site - Vector3(src.c)) * Vector3(1, 0, 1)
			var from: Vector3 = _rim_toward(src, dir)
			chambers.append({"c": site, "r": 3.5, "goal": 3.5, "kind": "brood", "from": from, "open": false,
				"yaw": ang + rng.randf_range(-0.6, 0.6)})
			return "planned"
	return event
