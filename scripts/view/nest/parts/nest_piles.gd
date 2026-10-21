extends "res://scripts/view/nest/parts/nest_brood.gd"
## Nest view, layer 4 of 10: the brood piles - each egg, larva and cocoon laid down like a real object on the
## floor (or on the heap), clear of the chamber walls and the queen, and left exactly where it lies until
## nurses carry its pile elsewhere.


# ---------------------------------------------------------------- brood piles

## A view tag for one item of brood (kept in its simulation entry; the simulation never reads it).
func _vtag(item: Dictionary) -> int:
	var v = item.get("_v")
	if v == null or not _tag_ok(int(v)):
		_vnext += 1
		v = _vnext + _vbase
		item["_v"] = v
	return int(v)


var _vbase := randi() % 1000000 * 1000            # (tags from an earlier session are not mistaken for this one's)
func _tag_ok(v: int) -> bool:
	return v > _vbase and v <= _vbase + _vnext


## Egg slots: an egg keeps its place in the packet for life; a new egg takes the lowest free place
## (the middle of the packet first), so nothing else moves when one is laid or hatches.
func _egg_slots(eggs: Array) -> Array:
	var alive := {}
	for e in eggs:
		alive[_vtag(e)] = true
	for v in _egg_slot.keys():
		if not alive.has(v):
			_slot_egg.erase(_egg_slot[v])
			_egg_slot.erase(v)
			if _egg_at.has(v):
				_freed.eggs.append((_egg_at[v] as Transform3D).origin)     # its larva hatches right there
				_egg_at.erase(v)
	var out := []
	var free := 0
	for e in eggs:
		var v: int = e["_v"]
		if not _egg_slot.has(v):
			while _slot_egg.has(free):
				free += 1
			_egg_slot[v] = free
			_slot_egg[free] = v
		out.append(_egg_slot[v])
	return out


## Where the next egg laid will lie (the queen carries it there).
func _next_egg_slot() -> int:
	var s := 0
	while _slot_egg.has(s):
		s += 1
	return s


func _pile(mm: MultiMesh, spots: Array, items: Array, max_n: int, scale_fn: Callable, old_spots := [], moved := 1 << 20,
		col_fn := Callable(), kind := "larvae") -> void:
	var n := mini(items.size(), max_n)
	if _queen_here():
		# not under the queen (a larva is ~2 units long); in a tiny founding chamber keep the spots farthest from her
		var clear := spots.filter(func(s): return _queen_keep(s) > 1.3)
		if clear.is_empty() and not spots.is_empty():
			clear = spots.duplicate()
			clear.sort_custom(func(a, b): return _queen_keep(a) > _queen_keep(b))
			clear = clear.slice(0, maxi(1, clear.size() / 3))
		spots = clear
	if spots.is_empty():
		n = 0
	elif spots.size() * 3 < n and not _spots.all.is_empty():
		# brood is spread in a low layer over the floor, never stacked into a tower: a crowded group
		# spills onto the floors of the other chambers
		spots = spots + _spots.all.filter(func(s): return not spots.has(s))
	var xs := []
	var cs := []
	var cands := {}
	# items already lying somewhere stay exactly there (registered first), unless nurses carried their pile
	# elsewhere or the spot is no longer good (see _still_lies); the rest are laid down
	var todo := []
	var tops := []
	var born := []
	for i in n:
		var src_key := _pile_key(kind, i < moved or old_spots.is_empty())
		var v := _vtag(items[i])
		var s: float = scale_fn.call(items[i])
		var pl: Dictionary = _placed.get(v, {})
		if not pl.is_empty() and pl.src == src_key and _still_lies(pl, s):
			if pl.top:
				tops.append(i)                   # (after everything it could be resting on)
				continue
			_keep_at(pl, s, kind, items[i], col_fn, xs, cs)
		elif pl.is_empty():
			born.append(i)                       # (after all that already lies: so it is laid clear of them all)
		else:
			todo.append(i)
	for i in born:
		var v := _vtag(items[i])
		if _born_at(kind, spots, v, scale_fn.call(items[i])):
			_keep_at(_placed[v], scale_fn.call(items[i]), kind, items[i], col_fn, xs, cs)    # where the egg / larva it came from lay
		else:
			todo.append(i)
	for i in tops:
		var pl: Dictionary = _placed[_vtag(items[i])]
		var s: float = scale_fn.call(items[i])
		var under := false
		for o in _brood_near(pl.base):
			if Vector2(o[0].x - pl.base.x, o[0].z - pl.base.z).length() < 0.95 * s + o[1] and float(o[0].y) < pl.base.y:
				under = true
				break
		if under:
			_keep_at(pl, s, kind, items[i], col_fn, xs, cs)
		else:
			todo.append(i)                       # what it rested on has hatched: it settles onto the floor
	for i in todo:
		# items not yet carried over stay in the old pile
		var src: Array = spots if (i < moved or old_spots.is_empty()) else old_spots
		if not cands.has(src):
			var centre := _pile_centre(src, kind)
			cands[src] = {"list": _pile_places(src, centre), "next": 0, "centre": centre,
				"reach": 0.9 + 0.75 * sqrt(float(n)),
				# half length and half width of one item (mesh_kit larva ~1.7 x 0.76, cocoon 2.7 x 1.24)
				"shape": Vector2(0.86, 0.38) if kind == "larvae" else Vector2(1.35, 0.62), "kind": kind}      # a compact heap: one layer about this wide, then on top
		var s: float = scale_fn.call(items[i])
		var xf := _place_brood(cands[src], s, i)
		_placed[_vtag(items[i])] = {"base": _last_base, "b": _last_yaw, "top": _last_top, "forced": _last_forced,
			"src": _pile_key(kind, i < moved or old_spots.is_empty())}
		if _brood_shown(xf, kind):
			xs.append(xf)
			cs.append(col_fn.call(items[i]) if col_fn.is_valid() else Color.WHITE)
			_brood_drawn[kind].append([xf, items[i]])
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		if mm.use_colors:
			mm.set_instance_color(i, cs[i])


## Where a pile of brood sits, as Lasius nurses sort it: the larvae heaped beside the egg packet near the
## queen's head (small larvae stay with the eggs), the cocoons in their own heap on the far side of the
## chamber from her (or wherever their chamber is).
func _pile_centre(spots: Array, kind: String) -> Vector3:
	var centre := Vector3.ZERO
	for s in spots:
		centre += s
	centre /= maxi(1, spots.size())
	var q: Vector3 = _spots.queen
	if q == Vector3.ZERO or spots.is_empty():
		return centre
	var near_q := spots.filter(func(s): return s.distance_to(q) < 8.0)
	if near_q.is_empty():
		return centre                           # their own chamber, away from the queen
	if kind == "larvae" and not _egg_spots.is_empty():
		var e: Vector3 = _egg_spots[0]
		var away := (e - q) * Vector3(1, 0, 1)
		var beside := _nearest_spot(e + (away.normalized() if away.length() > 0.1 else Vector3.RIGHT) * 2.2, spots)
		return beside if beside != Vector3.INF else centre
	var far: Vector3 = near_q[0]
	for s in near_q:
		if s.distance_to(q) > far.distance_to(q):
			far = s
	return far


## Where brood can lie in a pile: every floor spot and four points around it, nearest the pile's centre first.
func _pile_places(spots: Array, centre: Vector3) -> Array:
	if spots.is_empty():
		return []
	var out := []
	for s in spots:
		if _near_drop(Vector3i(roundi(s.x), roundi(s.y + 0.45), roundi(s.z))):
			continue                         # (by the mouth of a shaft down from the floor: brood would roll in)
		out.append(s)
		for o in [Vector3(0.45, 0, 0), Vector3(-0.45, 0, 0), Vector3(0, 0, 0.45), Vector3(0, 0, -0.45)]:
			out.append(s + o)
	out.sort_custom(func(a, b): return a.distance_squared_to(centre) < b.distance_squared_to(centre))
	return out


## Lay one item of brood down like a real object: on the floor at the first free place (nothing overlapping
## it, not under the queen), or — when the floor of the pile is full — on top of the items already there.
## `_brood_occ` (cleared per layout) holds what has been laid, binned by 1.5 units: [centre, packing radius,
## half its long axis (a vector: the item is a capsule along it), body half width] - eggs only [centre, radius].
func _place_brood(c: Dictionary, s: float, i: int) -> Transform3D:
	var places: Array = c.list
	var r := 0.95 * s                        # a larva or cocoon is long (2-2.7 units): keep their ends apart too
	var best := Vector3.INF
	var lift := 0.0
	var fit := 0.0
	if not c.get("full", false):
		for k in range(c.next, places.size()):
			var p: Vector3 = places[k]
			if _queen_here() and _queen_keep(p) < r + 0.5:
				continue
			if p.distance_to(c.centre) > c.reach:
				break                          # the heap is as wide as it gets: go on top instead
			if _brood_free(p, r):
				var turn := _fit_turn(p, s, c, i)
				if turn < 0.0:
					continue                       # it would stick into the chamber wall here
				var pf := Vector3(p.x, _floor_cached(p), p.z)          # (where it will lie: on the real floor under the spot)
				if _shape_lift(pf, Basis(Vector3.UP, _hash(i, 3) * TAU + turn), s, c.get("kind", "larvae"), true, 0.02) > 0.02:
					continue                       # its ends would lie in a neighbour's (it is long, the room a circle)
				fit = turn
				best = p
				c.next = maxi(c.next, k - 8)      # the places before this are (nearly all) taken
				break
		if best == Vector3.INF:
			c.full = true                      # no floor left in this pile: the rest go on top
	var on_top := false
	var low := INF
	if best == Vector3.INF and not places.is_empty():
		# the heap's floor is full: lie on top, resting on whatever is highest there
		on_top = true
		var inner := places.filter(func(p): return p.distance_to(c.centre) <= c.reach and (not _queen_here() or _queen_keep(p) >= r + 0.5))
		if inner.is_empty():
			inner = places
		# the lowest place on the heap where it lies clear of the walls and roof (from a different place
		# for each item, so they spread over the heap instead of stacking into a tower)
		var kind: String = c.get("kind", "larvae")
		# (the heap first; if nowhere on it is clear of the roof, anywhere on the chamber floor out of her way)
		var wide := places.filter(func(p): return not _queen_here() or _queen_keep(p) >= r + 0.2)
		var nin := mini(inner.size(), 60)
		for k in nin + mini(wide.size(), 36):
			var p: Vector3 = inner[(i + k * 7) % inner.size()] if k < nin else wide[(i + k * 5) % wide.size()]
			p.y = _floor_cached(p)
			for turn in [0.0, PI * 0.5]:
				# resting on what is under it: raised just so far that its body is clear of theirs (by their shapes)
				var bt := Basis(Vector3.UP, _hash(i, 3) * TAU + turn)
				var l := 0.0
				for it in 3:                        # (raised clear of one, it may meet another higher up)
					var more := _shape_lift(p + Vector3(0, l, 0), bt, s, kind, false)
					if more <= 0.02:
						break
					l += more + 0.01
				var score := l + 100.0 * _soil_pts(_brood_xf(p + Vector3(0, l, 0), Basis(Vector3.UP, _hash(i, 3) * TAU + turn), _grown(kind, s), kind, false), kind)
				if score < low:
					low = score
					best = p
					lift = l
					fit = turn
			if low < 0.1:
				break
	if lift == 0.0:
		best.y = _floor_cached(best)               # resting on the real floor under it
	# a larva lies on the floor (its mesh sits on its origin); a cocoon is centred, so it is raised half its height
	_last_base = best + Vector3(0, maxf(0.0, lift), 0)
	_last_top = on_top and lift > 0.05       # (resting on the heap: it may touch what it leans on)
	_last_forced = on_top and low >= 100.0
	_last_yaw = Basis(Vector3.UP, _hash(i, 3) * TAU + fit)
	return _register_brood(_last_base, _last_yaw, s, c.get("kind", "larvae"), not on_top)


var _last_base := Vector3.ZERO
var _last_top := false
var _last_forced := false          # laid where it still touches the soil (nowhere better): left there, not tried again
var _last_yaw := Basis.IDENTITY


## Draws a kept item where it lies (its tilt to the floor worked out again only when the soil changes). It
## grows where it lies, resting on the floor: as it grows its underside is set down on the real floor under it
## (the highest point of the floor under it touches, none is in it) - it never slides across the floor.
func _keep_at(pl: Dictionary, s: float, kind: String, item, col_fn: Callable, xs: Array, cs: Array) -> void:
	var sk := snappedf(s, 0.04)
	if pl.get("tgen", -1) != _soil_gen or pl.get("ts", -1.0) != sk:
		pl.tb = _floor_tilt(pl.base, pl.b, _grown(kind, s)) if not pl.top else pl.b     # (as it was laid: see _brood_xf)
		pl.tgen = _soil_gen
		pl.ts = sk
		pl.lift = 0.0 if pl.top else _rest_on_floor(_register_brood(pl.base, pl.tb, s, kind, false, false), kind)
	var xf := _register_brood(pl.base + Vector3(0, float(pl.lift), 0), pl.tb, s, kind, false)
	if _brood_shown(xf, kind):
		xs.append(xf)
		cs.append(col_fn.call(item) if col_fn.is_valid() else Color.WHITE)
		_brood_drawn[kind].append([xf, item])


## Whether an item of brood drawn at `xf` is shown: unless the soil is seen through, all of it behind the cut (one
## lying across it lay on floor that is cut away: it hung in the air in front of the face). Not whether it is on
## screen: the brood is laid out again only when it changes, and what was off screen then stayed missing as the
## camera came round to it (the graphics card leaves out what is off screen anyway).
func _brood_shown(xf: Transform3D, kind: String) -> bool:
	if xray:
		return true
	var f := xf.basis.x * (1.1 if kind == "larvae" else (1.35 if kind == "pupae" else 0.35))
	var lim := _plane_w + 0.05
	return _plane_n.dot(xf.origin + f) <= lim and _plane_n.dot(xf.origin - f) <= lim


## The brood drawn in the last layout, for clicking on it: kind -> [[transform, the simulation's item], ...].
var _brood_drawn := {"eggs": [], "larvae": [], "pupae": []}


## How far an item drawn at `xf` must be raised (or lowered: -) for its underside to rest on the floor under it.
func _rest_on_floor(xf: Transform3D, kind: String) -> float:
	var lift := -INF
	for q in (_larva_under() if kind == "larvae" else _COCOON_UNDER):
		var w: Vector3 = xf * q
		lift = maxf(lift, _floor_cached(w) - w.y)
	return clampf(lift, -0.4, 0.4) if lift > -INF else 0.0


## The underside of a larva lying at its origin (size 1): the bottom of its curved body at seven places.
static var _larva_under_cache: Array = []
static func _larva_under() -> Array:
	if _larva_under_cache.is_empty():
		for i in 7:
			var t := float(i) / 6.0
			var th := lerpf(-0.75, 0.95, t)
			var r := maxf(0.36 * sin(lerpf(0.35, 2.75, t)), 0.1)
			_larva_under_cache.append(Vector3(sin(th) * 1.15, r * 0.95 - r, (1.0 - cos(th)) * 0.55 - 0.18))
	return _larva_under_cache


const _COCOON_UNDER := [Vector3(0, -0.62, 0), Vector3(0.7, -0.53, 0), Vector3(-0.7, -0.53, 0), Vector3(1.1, -0.35, 0),
	Vector3(-1.1, -0.35, 0), Vector3(0, -0.53, 0.32), Vector3(0, -0.53, -0.32)]


## A new larva starts where its egg lay; a new cocoon where its larva spun it, when that is in the cocoon
## pile's own chamber (a founding cell; with workers a nurse carries it up to the pupa chamber instead).
## It lies there turned so that, fully grown, no part of it is in the chamber wall (else as near the spot as
## that can be: an egg by the wall hatches into a larva lying along it, not into it). Records it in _placed
## and returns true, or false (laid down in the pile as usual).
func _born_at(kind: String, spots: Array, v: int, s: float) -> bool:
	var from: String = "eggs" if kind == "larvae" else ("larvae" if kind == "pupae" else "")
	if from == "" or _freed[from].is_empty():
		return false
	var p: Vector3 = _freed[from][0]
	if kind == "pupae" and (_nearest_spot(p, spots) == Vector3.INF or _nearest_spot(p, spots).distance_to(p) > 2.0):
		return false
	var sf := _grown(kind, s)
	var yaw0 := randf() * TAU
	var best := [99, Vector3.INF, Basis(Vector3.UP, yaw0)]
	for off in _BORN_OFFS:
		var q: Vector3 = p + off
		q.y = _floor_cached(q)
		if _density_at(q + Vector3(0, 0.3, 0)) >= 0.5:
			continue
		if kind == "pupae" and (not _brood_free(q, 0.95 * sf) or (_queen_here() and _queen_keep(q) < 0.95 * sf + 0.5)):
			continue                    # (a cocoon is much bigger than the larva that spun it: not into its neighbours or the queen)
		for k in 8:
			var b := Basis(Vector3.UP, yaw0 + k * TAU / 8.0)
			if kind == "pupae" and _shape_lift(q, b, s, kind) > 0.02:
				continue                # (clear of its neighbours by their shapes too)
			var n := _soil_pts(_brood_xf(q, b, sf, kind, true), kind)
			if n < int(best[0]):
				best = [n, q, b]
		if int(best[0]) == 0:
			break
	if best[1] == Vector3.INF:
		if kind == "pupae":
			return false                # no room right there: laid with the rest of the pile (the nurse carries it there)
		best[1] = p
	_freed[from].pop_front()
	_placed[v] = {"base": best[1], "b": best[2], "top": false, "forced": int(best[0]) > 0,
		"src": _pile_key(kind, true)}
	return true


const _BORN_OFFS := [Vector3.ZERO, Vector3(0.4, 0, 0), Vector3(-0.4, 0, 0), Vector3(0, 0, 0.4), Vector3(0, 0, -0.4),
	Vector3(0.3, 0, 0.3), Vector3(-0.3, 0, 0.3), Vector3(0.3, 0, -0.3), Vector3(-0.3, 0, -0.3),
	Vector3(0.8, 0, 0), Vector3(-0.8, 0, 0), Vector3(0, 0, 0.8), Vector3(0, 0, -0.8),
	Vector3(0.6, 0, 0.6), Vector3(-0.6, 0, 0.6), Vector3(0.6, 0, -0.6), Vector3(-0.6, 0, -0.6),
	Vector3(1.3, 0, 0), Vector3(-1.3, 0, 0), Vector3(0, 0, 1.3), Vector3(0, 0, -1.3),
	Vector3(0.95, 0, 0.95), Vector3(-0.95, 0, 0.95), Vector3(0.95, 0, -0.95), Vector3(-0.95, 0, -0.95)]


## The size an item will reach where it lies: a larva grows from ~0.3 to ~1.1 before it pupates (it is laid
## down with room for that), a cocoon stays the size it is.
static func _grown(kind: String, s: float) -> float:
	return maxf(s, 1.08) if kind == "larvae" else s


## The larvae that are gone since the last layout (they pupated, or were eaten): where they lay goes to
## _freed.larvae for the cocoons, oldest first.
func _collect_freed_larvae() -> void:
	var alive := {}
	for l in sim.larvae:
		alive[_vtag(l)] = true
	for v in _placed.keys():
		var pl: Dictionary = _placed[v]
		if String(pl.src).begins_with("larvae") and not alive.has(v):
			_freed.larvae.append(pl.base)
			_placed.erase(v)
	while _freed.larvae.size() > 12:
		_freed.larvae.pop_front()


## A cocoon gone from its pile since the last layout (its ant has come out): where it lay and how it was
## turned, so the eclosion is acted out on that very cocoon. [] if none.
func _take_freed_pupa() -> Array:
	var alive := {}
	for p in sim.pupae:
		alive[_vtag(p)] = true
	var out := []
	for v in _placed.keys():
		var pl: Dictionary = _placed[v]
		if String(pl.src) == "pupae" and not alive.has(v):
			_placed.erase(v)
			if out.is_empty():
				out = [pl.base, pl.get("tb", pl.b)]
	return out


## Which pile an item belongs to: larvae have a day pile and a night pile (nurses carry them between).
func _pile_key(kind: String, new_pile: bool) -> String:
	if kind == "larvae":
		# by the chambers the pile is in (a founding cell has one chamber for both: nothing is carried)
		return kind + str(_group_rooms(_larva_group if new_pile else _larva_prev))
	if kind == "pupae" and _pupa_group != "":
		return kind + str(_group_rooms(_pupa_group if new_pile else _pupa_prev))
	return kind


## Whether an item stays where it was laid: always - brood moves only when an ant carries it (user,
## 2026-10-12). The one exception is a cocoon resting on another that has since hatched: it settles down
## onto the floor (see _pile).
func _still_lies(pl: Dictionary, s: float) -> bool:
	return true

## Puts one item of brood at `base` (the floor, or the top of what it rests on) into `_brood_occ` (unless
## `record` is false: only where it would be drawn).
func _register_brood(base: Vector3, b: Basis, s: float, kind: String, on_floor := true, record := true) -> Transform3D:
	var shape: Vector2 = Vector2(0.86, 0.38) if kind == "larvae" else Vector2(1.35, 0.62)
	var xf := _brood_xf(base, b, s, kind, on_floor)
	if not record:
		return xf
	var bb := xf.basis.orthonormalized()
	var pos := xf.origin
	var key := Vector3i(floori(pos.x / 1.5), floori(pos.y / 1.5), floori(pos.z / 1.5))
	if not _brood_occ.has(key):
		_brood_occ[key] = []
	# [centre (a larva: on the floor under it), packing radius, half its long axis, half its thickness, larva?]
	_brood_occ[key].append([pos, 0.95 * s, bb.x * (shape.x - shape.y) * s, shape.y * s, kind == "larvae", _pile_spheres(xf, kind)])
	return xf


## How an item lying at `base` with heading `b` is drawn: on the floor it lies along the slope of a curving
## chamber floor, not level across it (the slope under it fully grown, the same at every size: a growing larva
## tipped a little differently and its ends went into a curving floor); a larva's mesh sits on its origin, a
## cocoon is centred (raised half its height).
func _brood_xf(base: Vector3, b: Basis, s: float, kind: String, on_floor := true) -> Transform3D:
	if on_floor:
		b = _floor_tilt(base, b, _grown(kind, s))
	var pos := base + b.y * (0.6 * s if kind != "larvae" else 0.0)
	return Transform3D(b.scaled(Vector3.ONE * s), pos)


## The heading `b` tipped to lie flat on the floor around `base` (its slope from four floor heights a body
## length apart; at most ~35 degrees, beyond that it is a wall).
func _floor_tilt(base: Vector3, b: Basis, s: float) -> Basis:
	var d := 0.6 * s
	var hx := _floor_cached(base + Vector3(d, 0, 0)) - _floor_cached(base - Vector3(d, 0, 0))
	var hz := _floor_cached(base + Vector3(0, 0, d)) - _floor_cached(base - Vector3(0, 0, d))
	var n := Vector3(-hx, 2.0 * d, -hz).normalized()
	if n.y < 0.82:
		n = Vector3.UP.slerp(n, acos(0.82) / acos(clampf(n.y, -1.0, 1.0)))
	var x: Vector3 = (b.x - n * b.x.dot(n)).normalized()
	return Basis(x, n, x.cross(n))


## A turn (radians, added to the item's own heading) that keeps the whole item - grown to full size - in the
## open, clear of the floor's curve and the walls; -1 if no heading fits here.
func _fit_turn(p: Vector3, s: float, c: Dictionary, i: int) -> float:
	var kind: String = c.get("kind", "larvae")
	var base := Vector3(p.x, _floor_cached(p), p.z)
	for k in 8:
		var turn: float = [0.0, PI * 0.5, PI * 0.25, PI * 0.75, PI, PI * 1.5, PI * 1.25, PI * 1.75][k]
		if _soil_pts(_brood_xf(base, Basis(Vector3.UP, _hash(i, 3) * TAU + turn), _grown(kind, s), kind, true), kind) == 0:
			return turn
	return -1.0


## How many points on the surface of an item drawn at `xf` are inside the soil (0: it lies clear).
func _soil_pts(xf: Transform3D, kind: String) -> int:
	var n := 0
	for q in (_larva_pts() if kind == "larvae" else _COCOON_PTS):
		if _density_at(xf * q) >= 0.5:
			n += 1
	return n


## Points on a larva lying at its origin (size 1; mesh_kit.larva): the middle, top and both sides of its
## curved body at seven places along it, both ends and the head - all that shows if it is in the soil (not
## its underside, which rests on the floor).
static var _larva_cache: Array = []
static func _larva_pts() -> Array:
	if _larva_cache.is_empty():
		for i in 7:
			var t := float(i) / 6.0
			var th := lerpf(-0.75, 0.95, t)
			var r := maxf(0.36 * sin(lerpf(0.35, 2.75, t)), 0.1)
			var c := Vector3(sin(th) * 1.15, r * 0.95, (1.0 - cos(th)) * 0.55 - 0.18)
			_larva_cache.append_array([c, c + Vector3(0, r * 0.9, 0), c + Vector3(0, 0.1, r * 0.9), c + Vector3(0, 0.1, -r * 0.9)])
			if i == 0 or i == 6:
				var tan := Vector3(cos(th) * 1.15, 0.0, sin(th) * 0.55).normalized() * (1.0 if i == 6 else -1.0)
				_larva_cache.append(c + tan * r)
		_larva_cache.append(Vector3(sin(0.95) * 1.15 + 0.2, 0.15, (1.0 - cos(0.95)) * 0.55 - 0.1))     # the head
	return _larva_cache


## The same for a cocoon (an ellipsoid 2.7 x 1.24, centred): ends, top, sides.
const _COCOON_PTS := [Vector3(1.25, 0, 0), Vector3(-1.25, 0, 0), Vector3(0.9, 0.4, 0), Vector3(-0.9, 0.4, 0),
	Vector3(0.9, 0, 0.42), Vector3(0.9, 0, -0.42), Vector3(-0.9, 0, 0.42), Vector3(-0.9, 0, -0.42),
	Vector3(0, 0.58, 0), Vector3(0, 0, 0.58), Vector3(0, 0, -0.58), Vector3(0, 0.4, 0.4), Vector3(0, 0.4, -0.4)]


## Dev (--trace-crowd): how many larvae and cocoons drawn have some part of them in the soil (x, y), and how
## many lie off the floor (z: the larvae on the floor whose underside is more than a little above it).
func brood_in_soil() -> Vector3i:
	var out := Vector3i.ZERO
	for i in _larva_mm.instance_count:
		var xf := _larva_mm.get_instance_transform(i)
		if _soil_pts(xf, "larvae") > 0:
			out.x += 1
		if _rest_on_floor(xf, "larvae") < -0.08 and _brood_near(xf.origin).size() <= 1:
			out.z += 1
	for i in _pupa_mm.instance_count:
		if _soil_pts(_pupa_mm.get_instance_transform(i), "pupae") > 0:
			out.y += 1
	return out


func _brood_near(p: Vector3) -> Array:
	var out := []
	var key := Vector3i(floori(p.x / 1.5), floori(p.y / 1.5), floori(p.z / 1.5))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1, 2]:
			for dz in [-1, 0, 1]:
				out.append_array(_brood_occ.get(key + Vector3i(dx, dy, dz), []))
	return out


## From the nearest point of a brood item (a capsule along its long axis; an egg is a point) to a.
func _brood_offset(a: Vector3, o: Array) -> Vector3:
	var c: Vector3 = o[0]
	if o.size() > 2:
		var ax: Vector3 = o[2]
		var l2 := ax.length_squared()
		if l2 > 0.0001:
			c += ax * clampf((a - c).dot(ax) / l2, -1.0, 1.0)
	return a - c


## Marks the cells an ant could not stand in without being on the brood (`_brood_cells`), so routes go round
## the egg packet, the larvae and the cocoons. Rebuilt with each brood layout.
func _mark_brood_cells() -> void:
	_brood_cells.clear()
	_brood_wide.clear()
	for bin in _brood_occ.values():
		for o in bin:
			var c: Vector3 = o[0]
			var half: float = (o[3] if o.size() > 3 else o[1]) + 0.45       # + an ant's half width
			var wide: float = half + 0.65                                    # + a body width (where to stop)
			var ext := wide + ((o[2] as Vector3).length() if o.size() > 2 else 0.0)
			for x in range(floori(c.x - ext), ceili(c.x + ext) + 1):
				for y in range(floori(c.y - 1.0), ceili(c.y + 1.0) + 1):
					for z in range(floori(c.z - ext), ceili(c.z + ext) + 1):
						var cell := Vector3i(x, y, z)
						if _brood_cells.has(cell):
							continue
						var d := _brood_offset(Vector3(cell) - Vector3(0, 0.4, 0), o)
						if absf(d.y) < 1.2:
							var l := Vector2(d.x, d.z).length()
							if l < wide:
								_brood_wide[cell] = true
							if l < half:
								_brood_cells[cell] = true


## How far an item laid at `base` with heading `b` must be raised to lie clear of the brood already there - by the
## bodies as they are drawn (tilted with the floor under them): a cocoon three spheres along its length, a larva two.
## 0 = it lies there clear of them all.
func _shape_lift(base: Vector3, b: Basis, s: float, kind: String, on_floor := true, enough := INF) -> float:
	var mine := _pile_spheres(_brood_xf(base, b, _grown(kind, s), kind, on_floor), kind)
	var need := 0.0
	# (two bins round it each way: a cocoon is 2.7 long, a bin 1.5 - _brood_near's one bin missed a neighbour 1.5 away)
	var key := Vector3i(floori(base.x / 1.5), floori(base.y / 1.5), floori(base.z / 1.5))
	for dx in range(-2, 3):
		for dy in range(-1, 2):
			for dz in range(-2, 3):
				for o in _brood_occ.get(key + Vector3i(dx, dy, dz), []):
					if (o[0] as Vector3).distance_squared_to(base) > 12.0:
						continue                  # (too far to touch it)
					var sph: Array = o[5] if o.size() >= 6 else ([[o[0], 0.25]] if o.size() == 2 else [])     # (an egg: a small ball)
					for q in sph:
						for m in mine:
							var reach: float = (float(m[1]) + float(q[1])) * 1.06
							var d: Vector3 = (m[0] as Vector3) - (q[0] as Vector3)
							var dxz := Vector2(d.x, d.z).length()
							if dxz < reach and d.length() < reach:
								need = maxf(need, sqrt(reach * reach - dxz * dxz) - d.y)
								if need > enough:
									return need       # (it is already too much: no need to know how much)
	return need


## A drawn item of brood as spheres (as dev/body_check.gd measures them): [[centre, radius], ...].
static func _pile_spheres(xf: Transform3D, kind: String) -> Array:
	var sc := xf.basis.get_scale().x
	if kind == "larvae":
		return [[xf * Vector3(0.45, 0.32, 0.0), 0.34 * sc], [xf * Vector3(-0.35, 0.32, 0.0), 0.36 * sc]]
	return [[xf * Vector3(0.75, 0, 0), 0.55 * sc], [xf.origin, 0.6 * sc], [xf * Vector3(-0.75, 0, 0), 0.55 * sc]]


func _brood_free(p: Vector3, r: float) -> bool:
	var q := p + Vector3(0, 0.25, 0)
	var key := Vector3i(floori(p.x / 1.5), floori(p.y / 1.5), floori(p.z / 1.5))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var bin = _brood_occ.get(key + Vector3i(dx, dy, dz))
				if bin == null:
					continue
				for o in bin:
					var lim: float = (r + o[1]) * 0.92
					if (o[0] as Vector3).distance_squared_to(q) < lim * lim:
						return false
	return true


func _update_brood() -> void:
	_brood_occ.clear()                       # larvae, cocoons and eggs share the floor: laid out together
	_brood_drawn = {"eggs": [], "larvae": [], "pupae": []}
	var exs := []
	if not _spots.eggs.is_empty():
		var shown: Array = sim.eggs.slice(0, mini(400, maxi(0, sim.eggs.size() - _pending("egg"))))
		var slots := _egg_slots(shown)
		for j in shown.size():
			var v: int = shown[j]["_v"]
			if not _egg_at.has(v):
				_egg_at[v] = _egg_xf(slots[j])          # laid here; it stays here
			var xf: Transform3D = _egg_at[v]
			var ek := Vector3i(floori(xf.origin.x / 1.5), floori(xf.origin.y / 1.5), floori(xf.origin.z / 1.5))
			if not _brood_occ.has(ek):
				_brood_occ[ek] = []
			_brood_occ[ek].append([xf.origin, 0.3])       # larvae and cocoons are not laid on the eggs
			if _brood_shown(xf, "eggs"):
				exs.append(xf)
				_brood_drawn.eggs.append([xf, shown[j]])
	_fill(_egg_mm, exs)
	# young larvae are tiny; they grow about tenfold in mass before pupating
	_collect_freed_larvae()
	_pile(_larva_mm, _spots.larvae, sim.larvae, 300, func(l): return 0.28 + l.p * 0.8, _spots.larvae_old, _moved, Callable(), "larvae")
	_freed.eggs.clear()                      # (a hatching larva appears in the same layout as its egg goes)
	var bits := []
	if not sim.larvae.is_empty() and not _spots.larvae.is_empty():
		for k in mini(16, int(sim.protein * 1.5)):
			# (scraps of prey by the larvae, lying on the floor - they floated a layer up, or hung in a shaft)
			var sp: Vector3 = _spots.larvae[(k * 3 + 1) % _spots.larvae.size()]
			var base := sp + Vector3(_hash(k, 1) - 0.5, 0.0, _hash(k, 2) - 0.5) * 0.8
			base.y = _floor_cached(base) + 0.08
			var xf := Transform3D(Basis(Vector3.UP, _hash(k, 9) * TAU), base)
			if _visible(xf.origin):
				bits.append(xf)
	_fill(_bits_mm, bits)
	_pile(_pupa_mm, _spots.pupae, sim.pupae.slice(0, maxi(0, sim.pupae.size() - _pending("pupate"))), 300, func(p): return p.get("s", 1.0),
		_spots.pupae_old if _pupa_group != _pupa_prev else [], _moved_p if _pupa_group != _pupa_prev else 1 << 20, func(p): return Color.WHITE.lerp(Color(0.72, 0.72, 0.72), smoothstep(0.75, 1.0, p.p)), "pupae")
	_mark_brood_cells()
	_brood_gen += 1
	# the crater mound of excavated pellets around the entrance on top of the block
	var n := mini(nest.excavated / 2, 900)
	if n == _mound_n:
		return
	_mound_n = n
	var e: Vector3 = Vector3(nest.entrance) + Vector3(0, 0.6, 0)
	_pellet_mm.instance_count = n
	for i in n:
		var a := _hash(i, 5) * TAU
		var r := 2.0 + sqrt(_hash(i, 6)) * (3.0 + sqrt(float(n)) * 0.35)
		var h := maxf(0.0, 1.0 - r / (4.0 + sqrt(float(n)) * 0.4)) * 2.0
		_pellet_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, a), e + Vector3(cos(a) * r, h * _hash(i, 7), sin(a) * r)))


## (dev, body_check --trace-crowd) how the item drawn at p was laid: on top, forced, where from.
func _placed_at(p: Vector3) -> String:
	for v in _placed:
		var pl: Dictionary = _placed[v]
		if (pl.base as Vector3).distance_to(p) < 1.2:
			return "top %s forced %s src %s" % [pl.top, pl.get("forced", false), pl.src]
	return "?"
