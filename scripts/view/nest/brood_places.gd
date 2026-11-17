extends RefCounted
## Where the brood of a pile can lie (the nest view's brood piles, parts/nest_piles.gd: split out in v0.13.25, that file
## being at its size limit). `v` is the nest view.

static var _cache := {}             # the places worked out, by view, soil, spots and centre: the brood is laid out again
                                    # often (the queen turning, a count changing) and working them out each time (the floor
                                    # under ~2,500 places and round them) took the nest at 300 ants from 59 to 11-19 fps


## Where brood can lie in a pile: every floor spot and four points around it, nearest the pile's centre first.
static func places(v, spots: Array, centre: Vector3) -> Array:
	if spots.is_empty():
		return []
	var key := "%d|%d|%d|%s" % [v.get_instance_id(), v._soil_gen, spots.hash(), centre.snapped(Vector3.ONE * 0.25)]
	if _cache.has(key):
		return (_cache[key] as Array).duplicate()
	if _cache.size() > 64:
		_cache.clear()
	var got := _work_out(v, spots, centre)
	_cache[key] = got
	return got.duplicate()


## A pile whose chamber floor is full (`own` its spots, n items): the floor of the chambers next to it, nearest the pile
## first, before anything goes on top (the keeper's 56 cocoons, 2026-11-17: three deep in a bowl-shaped chamber with
## chambers to spare). Only as many floor cells as it may need, the nearest: all of them (~500) took 3-9 s for larvae laid
## out again as nurses carried them (v0.13.26). [Inference: nurses spread a crowded brood into the next chambers.]
static func spill(v, own: Array, centre: Vector3, n: int) -> Array:
	var mine := {}
	for q in own:
		mine[q] = true
	# chamber by chamber, the nearest first, each on its own floor level (all of them as one list kept only the level of
	# the nearest: the queen's chamber, full of eggs - 33 of 47 larvae still went on top)
	var rooms := []
	for r in v._rooms:
		var sp: Array = (r.spots as Array).filter(func(q): return not mine.has(q))
		if not sp.is_empty():
			rooms.append([Vector3(r.cell).distance_squared_to(centre), sp])
	rooms.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	for e in rooms:
		out.append_array(places(v, e[1], centre))
		if out.size() > 12 * n + 60:
			break                          # (enough to try: a chamber's floor more than they need)
	return out


static func _work_out(v, spots: Array, centre: Vector3) -> Array:
	var out := []
	for s in spots:
		if v._near_drop(Vector3i(roundi(s.x), roundi(s.y + 0.45), roundi(s.z))):
			continue                         # (by the mouth of a shaft down from the floor: brood would roll in)
		out.append(s)
		for o in [Vector3(0.45, 0, 0), Vector3(-0.45, 0, 0), Vector3(0, 0, 0.45), Vector3(0, 0, -0.45)]:
			out.append(s + o)
	out.sort_custom(func(a, b): return a.distance_squared_to(centre) < b.distance_squared_to(centre))
	# one floor level: places up or down a ramp or a shaft (more than ~half a cocoon off) are not used - brood down a ramp
	# lay one over the next like a column (the keeper, 2026-10-28). The level of most places near the middle, not of the
	# one nearest it: in a dip by the queen that kept 10 of 760 places and 15 larvae stood in a column (v0.13.25)
	if out.is_empty():
		return out
	var level: float = v._floor_cached(out[0])
	var most := 0
	for j in mini(out.size(), 40):
		var lj: float = v._floor_cached(out[j])
		var c: int = out.slice(0, mini(out.size(), 200)).filter(func(p): return absf(v._floor_cached(p) - lj) <= 0.9).size()
		if c > most:
			most = c
			level = lj
	var kept := out.filter(func(p): return absf(v._floor_cached(p) - level) <= 0.9)
	if kept.size() < 4:
		return out
	# then, once that level is full, the floor round it up the chamber's sides where it is not steep: a chamber floor is a
	# bowl, its flat bottom held 15-20 of the keeper's 56 cocoons and the rest went on top (v0.13.25, the keeper's
	# picture); a cocoon on a gentle slope still lies on the floor, on its own
	var up := out.filter(func(p): return _gentle(v, p, level))
	return kept + up


## A place up the chamber's side: not more than ~2.5 voxels above or below the pile's level, and not steep there.
static func _gentle(v, p: Vector3, level: float) -> bool:
	var dl: float = absf(v._floor_cached(p) - level)
	if dl <= 0.9 or dl > 2.6:
		return false
	var sx: float = absf(v._floor_cached(p + Vector3(0.8, 0, 0)) - v._floor_cached(p - Vector3(0.8, 0, 0)))
	var sz: float = absf(v._floor_cached(p + Vector3(0, 0, 0.8)) - v._floor_cached(p - Vector3(0, 0, 0.8)))
	return sx < 0.9 and sz < 0.9
