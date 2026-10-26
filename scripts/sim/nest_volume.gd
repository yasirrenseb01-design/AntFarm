extends "res://scripts/sim/parts/nest_chambers.gd"
## Underground nest, layer 3 of 3 (top): the diggers — where they dig, bites, carrying the soil out.
## Layers: parts/nest_voxels <- parts/nest_chambers <- nest_volume (this file). Split in v0.8.5.


# ---------------------------------------------------------------- digging

const BITES_PER_PELLET := 3     # bites at the face before the pellet is carried out
const BITE_STEPS := 40          # digger steps (STEP_EVERY ticks each) one bite takes: ~2.7 s at 1x

func _dig_signal(c: Vector3i) -> float:
	var t := dug_at[idx(c)]
	return exp(-(tick - t) / DIG_TAU)


func _dig_chance(s: Vector3i, from: Vector3i, humidity: float) -> float:
	if not inside(s) or rho[idx(s)] < AIR:
		return 0.0
	if not hard.is_empty() and hard[idx(s)] == 1:
		return 0.0                                       # a stone or a root: dug round, never through
	if slab and s.z < nz - 3:
		return 0.0
	# never break through the surface except around the entrance shaft
	if s.y >= ny - 2 and Vector2(s.x - entrance.x, s.z - entrance.z).length() > 1.5:
		return 0.0
	# loam near the surface is soft, the clay band below is stiff, sand deeper is loose
	var depth := ny - s.y
	var soft := 1.0 if depth < clay_top() else (0.45 if depth < sand_top() else 0.75)
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
		# (not often: dug at 0.25 every chamber had blind tunnels hanging from it like a fringe, the keeper saw the
		# nests cluttered with them, 2026-10-23; real nests have a few - García Ibarra et al. 2024)
		k = 0.06 if s.y > _lowest_chamber() - 7.0 else 0.003
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
		dug += 1
		proj[(s.y - y_lo) * nx + s.x] += 1
		if s.y < y_lo + 4 and y_lo > y_floor:
			_extend_to = s.y - EXTEND_BY         # (near the bottom of the soil held: more of it, before the next step)
		var best := -1
		for d in DIRS:
			var n := s + d
			if inside(n):
				var dn := dist[idx(n)]
				if dn >= 0 and (best < 0 or dn < best):
					best = dn
		dist[i] = best + 1 if best >= 0 else -1


var _extend_to := 100000                # a layer to take the soil in down to, at the next step (_bite)


## Whether the work face (work_at) still has planned soil beside it to dig.
func _face_left() -> bool:
	if work_at.x < 0:
		return false
	for dd in DIRS:
		var n: Vector3i = work_at + dd
		if inside(n) and rho[idx(n)] >= AIR and not is_hard(n) and _plan_at(n) > 0:
			return true
	return false


## An open cell a few voxels from the face of the planned work (work_at), for a digger to make for.
func _near_work() -> Vector3i:
	for attempt in 6:
		var c := work_at + Vector3i(rng.randi_range(-3, 3), rng.randi_range(-2, 2), 0 if slab else rng.randi_range(-3, 3))
		if is_open(c) and dist[idx(c)] >= 0:
			return c
	return work_at


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
	if _extend_to < 100000:
		extend_down(_extend_to)
		_extend_to = 100000
	_dist_age += 1
	if _dist_age > 120:
		_dist_age = 0
		_bfs()
	# the face the diggers make for, dug out: the next one now, not at the next daily count (until then they all walked
	# round a finished face with nothing on it to dig)
	if work_left > 0 and tick % (STEP_EVERY * 30) == 0 and not _face_left():
		work_left = count_work_left()
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
			if work_left > 0 and work_at.x >= 0:
				d.site = _near_work()   # (or to the planned work, if any is waiting - somewhere along its face, not all at one spot)
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

	if air < target_air or work_left > 0:
		if int(d.get("biting", 0)) > 0:
			d.biting = int(d.biting) - 1         # still at the face, biting and working the soil into a pellet
			return
		var best := Vector3i.ZERO
		var best_p := 0.0
		for dd in DIRS:
			if air >= target_air and _plan_at(c + dd) == 0:
				continue                 # big enough: only the planned work is finished off
			var p := _dig_chance(c + dd, c, humidity)
			if p > best_p:
				best_p = p
				best = c + dd
		if best_p > 0.0 and (int(d.get("bites", 0)) > 0 and best_p > 0.02 or rng.randf() < best_p):
			# a pellet takes a few bites at the same face, each a moment of work (BITE_STEPS), then it is carried out
			# [inference: Lasius workers bite soil loose and shape it into a pellet in their mandibles before carrying
			# it; how long that takes was not found - chosen ~8 s a pellet at 1x]
			_bite(best)
			d.bites = int(d.get("bites", 0)) + 1
			d.site = c
			if int(d.bites) >= BITES_PER_PELLET:
				d.bites = 0
				d.carry = true
			else:
				d.biting = BITE_STEPS
			return
		if int(d.get("bites", 0)) > 0:
			d.bites = 0
			d.carry = true                       # nothing more to bite right here: off with what it has
			return

	# wander along the walls, drawn toward fresh digging and slightly downward
	var cands: Array[Vector3i] = []
	var weights: Array[float] = []
	var total := 0.0
	var to_work: bool = work_left > 0 and work_at.x >= 0 and work_dist.size() == rho.size() and work_dist[idx(c)] >= 0
	for dd in DIRS:
		var n := c + dd
		var on_way: bool = to_work and inside(n) and work_dist[idx(n)] >= 0 and work_dist[idx(n)] < work_dist[idx(c)]
		if not walkable(n) and not on_way:
			continue                     # (on the way to planned work it may cross a tunnel's middle)
		var w := 1.0 + 6.0 * _dig_signal(n)
		if on_way:
			w += 20.0                    # planned work waiting: along the tunnels to its face
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
