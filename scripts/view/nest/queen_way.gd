extends RefCounted
## The queen's way from one chamber to another (nest_brood._refresh_spots): down the middle of the tunnels, where her body
## fits, and set on what she stands on. The walking field (nest_brood._field_from) keeps to the walls, a worker's way: her
## body is wider than a cell, and walked along it one side of her was in the soil (v0.11.90: gaster right 44% of the frames,
## left 8% - --queen-walk, the keeper's colony).

const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const CLEAR_MAX := 4                  # how far from the soil is told apart (voxels); more is all the same
const NARROW_COST := [0, 12, 4, 1, 0]      # added to a step by the room there (its steps to the nearest soil): a tunnel's middle over its side
const FLOOR_LOOK := 4.5               # further down than this it is not a floor she walks: a shaft's wall
const FLOOR_FEET := 0.05              # her feet's point over the floor, and off a shaft's wall (as the walking field set them)
const WALL_FEET := 0.1


## The way from p to goal, or [] if there is none (the caller then has the walking field's).
static func find(nv, p: Vector3, goal: Vector3) -> Array:
	var nest = nv.nest
	var from := Vector3i(roundi(p.x), roundi(p.y + 0.45), roundi(p.z))
	var to := Vector3i(roundi(goal.x), roundi(goal.y + 0.45), roundi(goal.z))
	if not nest.is_open(from) or not nest.is_open(to):
		return []
	var clear := _room(nest, from)
	if not clear.has(to):
		return []
	var cost := _steps_to(clear, to)
	if not cost.has(from):
		return []
	var out := []
	var c := from
	var last_side := Vector3.ZERO
	for k in 600:
		var best := c
		var bd: int = cost[c]
		for d in DIRS:
			var v: int = cost.get(c + d, 1 << 30)
			if v < bd:
				bd = v
				best = c + d
		if best == c:
			break
		c = best
		var seat: Array = _seat(nv, Vector3(c), last_side)
		out.append(seat[0])
		last_side = seat[1]
	out.append(goal)
	return out


## Every open cell reached from start, with its steps to the nearest soil (1 beside it, up to CLEAR_MAX).
static func _room(nest, start: Vector3i) -> Dictionary:
	var clear := {start: 0}
	var q: Array[Vector3i] = [start]
	var head := 0
	var ring: Array[Vector3i] = []
	while head < q.size():
		var c: Vector3i = q[head]
		head += 1
		var beside := false
		for d in DIRS:
			var n: Vector3i = c + d
			if not nest.is_open(n):
				beside = true
			elif not clear.has(n):
				clear[n] = 0
				q.append(n)
		if beside:
			clear[c] = 1
			ring.append(c)
	for step in range(2, CLEAR_MAX + 1):
		var next: Array[Vector3i] = []
		for c in ring:
			for d in DIRS:
				var n: Vector3i = c + d
				if clear.get(n, -1) == 0:
					clear[n] = step
					next.append(n)
		ring = next
	for c in q:
		if clear[c] == 0:
			clear[c] = CLEAR_MAX
	return clear


## The cost to `to` from each cell, a step dearer the nearer the soil.
static func _steps_to(clear: Dictionary, to: Vector3i) -> Dictionary:
	var cost := {to: 0}
	var buckets := {0: [to]}
	var cur := 0
	var left := 1
	while left > 0:
		var b: Array = buckets.get(cur, [])
		buckets.erase(cur)
		for c in b:
			left -= 1
			if int(cost[c]) != cur:
				continue
			for d in DIRS:
				var n: Vector3i = c + d
				if not clear.has(n):
					continue
				var nd: int = cur + 1 + int(NARROW_COST[int(clear[n])])
				if nd < int(cost.get(n, 1 << 30)):
					cost[n] = nd
					if not buckets.has(nd):
						buckets[nd] = []
					buckets[nd].append(n)
					left += 1
		cur += 1
	return cost


## A cell of the way's middle set on what she stands on there: the floor under it, or in a shaft the wall nearest it (the
## same one as long as she can: she does not cross from wall to wall). [point, the side it went to]
static func _seat(nv, c: Vector3, last_side: Vector3) -> Array:
	var down := _reach(nv, c, Vector3.DOWN, FLOOR_LOOK)
	if down < FLOOR_LOOK:
		return [c + Vector3.DOWN * (down - FLOOR_FEET), Vector3.ZERO]
	var side := Vector3.RIGHT
	var best := INF
	var at := 0.0
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var r := _reach(nv, c, dir, 6.0)
		var score: float = r - 1.5 * dir.dot(last_side)
		if score < best:
			best = score
			side = dir
			at = r
	return [c + side * (at - WALL_FEET), side]


## How far along dir from p the nest stays open (at most `most`).
static func _reach(nv, p: Vector3, dir: Vector3, most: float) -> float:
	var d := 0.2
	while d < most and nv._density_at(p + dir * d) < 0.5:
		d += 0.2
	return d
