extends RefCounted
## Where the brood of a pile can lie (the nest view's brood piles, parts/nest_piles.gd: split out in v0.13.25, that file
## being at its size limit). `v` is the nest view.

## Where brood can lie in a pile: every floor spot and four points around it, nearest the pile's centre first.
static func places(v, spots: Array, centre: Vector3) -> Array:
	if spots.is_empty():
		return []
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
	return kept if kept.size() >= 4 else out
