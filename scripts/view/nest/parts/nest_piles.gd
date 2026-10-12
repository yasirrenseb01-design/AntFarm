extends "res://scripts/view/nest/parts/nest_brood.gd"
## Nest view, layer 4 of 8: the brood piles - each egg, larva and cocoon laid down like a real object on the
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
	if _queen_mm.instance_count > 0:
		# not under the queen (a larva is ~2 units long); in a tiny founding chamber keep the spots farthest from her
		var clear := spots.filter(func(s): return _queen_gap(s) > 1.3)
		if clear.is_empty() and not spots.is_empty():
			clear = spots.duplicate()
			clear.sort_custom(func(a, b): return _queen_gap(a) > _queen_gap(b))
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
		elif pl.is_empty() and _born_at(kind, spots, v):
			_keep_at(_placed[v], s, kind, items[i], col_fn, xs, cs)    # where the egg / larva it came from lay
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
		if _visible(xf.origin):
			xs.append(xf)
			cs.append(col_fn.call(items[i]) if col_fn.is_valid() else Color.WHITE)
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
			if _queen_mm.instance_count > 0 and _queen_gap(p) < r + 0.5:
				continue
			if p.distance_to(c.centre) > c.reach:
				break                          # the heap is as wide as it gets: go on top instead
			if _brood_free(p, r):
				var turn := _fit_turn(p, s, c, i)
				if turn < 0.0:
					continue                       # it would stick into the chamber wall here
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
		var inner := places.filter(func(p): return p.distance_to(c.centre) <= c.reach and (_queen_mm.instance_count == 0 or _queen_gap(p) >= r + 0.5))
		if inner.is_empty():
			inner = places
		# the lowest place on the heap where it lies clear of the walls and roof (from a different place
		# for each item, so they spread over the heap instead of stacking into a tower)
		var shape: Vector2 = c.get("shape", Vector2(0.86, 0.38))
		# (the heap first; if nowhere on it is clear of the roof, anywhere on the chamber floor out of her way)
		var wide := places.filter(func(p): return _queen_mm.instance_count == 0 or _queen_gap(p) >= r + 0.2)
		var nin := mini(inner.size(), 60)
		for k in nin + mini(wide.size(), 60):
			var p: Vector3 = inner[(i + k * 7) % inner.size()] if k < nin else wide[(i + k * 5) % wide.size()]
			p.y = _floor_cached(p)
			var l := 0.0
			for o in _brood_near(p):
				if Vector2(o[0].x - p.x, o[0].z - p.z).length() < r + o[1]:
					# resting on the top of what is under it (top ~ its centre + half its thickness)
					l = maxf(l, float(o[0].y) + float(o[3] if o.size() > 3 else o[1]) - p.y)
			for turn in [0.0, PI * 0.5]:
				var score := l + 100.0 * _in_soil(p + Vector3(0, l, 0), Basis(Vector3.UP, _hash(i, 3) * TAU + turn), s, shape)
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


## Draws a kept item where it lies (its tilt to the floor worked out again only when the soil changes).
func _keep_at(pl: Dictionary, s: float, kind: String, item, col_fn: Callable, xs: Array, cs: Array) -> void:
	if pl.get("tgen", -1) != _soil_gen:
		pl.tb = _floor_tilt(pl.base, pl.b, s) if not pl.top else pl.b
		pl.tgen = _soil_gen
	var xf := _register_brood(pl.base, pl.tb, s, kind, false)
	if _visible(xf.origin):
		xs.append(xf)
		cs.append(col_fn.call(item) if col_fn.is_valid() else Color.WHITE)


## A new larva starts where its egg lay; a new cocoon where its larva spun it, when that is in the cocoon
## pile's own chamber (a founding cell; with workers a nurse carries it up to the pupa chamber instead).
## Records it in _placed and returns true, or false (laid down in the pile as usual).
func _born_at(kind: String, spots: Array, v: int) -> bool:
	var from: String = "eggs" if kind == "larvae" else ("larvae" if kind == "pupae" else "")
	if from == "" or _freed[from].is_empty():
		return false
	var p: Vector3 = _freed[from][0]
	if kind == "pupae" and (_nearest_spot(p, spots) == Vector3.INF or _nearest_spot(p, spots).distance_to(p) > 2.0):
		return false
	_freed[from].pop_front()
	p.y = _floor_cached(p)
	_placed[v] = {"base": p, "b": Basis(Vector3.UP, randf() * TAU), "top": false, "forced": false,
		"src": _pile_key(kind, true)}
	return true


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


## Which pile an item belongs to: larvae have a day pile and a night pile (nurses carry them between).
func _pile_key(kind: String, new_pile: bool) -> String:
	if kind == "larvae":
		# by the chambers the pile is in (a founding cell has one chamber for both: nothing is carried)
		return kind + str(_upper if (_larva_group if new_pile else _larva_prev) == "up" else _lower)
	return kind


## Whether an item stays where it was laid: always - brood moves only when an ant carries it (user,
## 2026-10-12). The one exception is a cocoon resting on another that has since hatched: it settles down
## onto the floor (see _pile).
func _still_lies(pl: Dictionary, s: float) -> bool:
	return true

## Puts one item of brood at `base` (the floor, or the top of what it rests on) into `_brood_occ`.
func _register_brood(base: Vector3, b: Basis, s: float, kind: String, on_floor := true) -> Transform3D:
	var shape: Vector2 = Vector2(0.86, 0.38) if kind == "larvae" else Vector2(1.35, 0.62)
	if on_floor:
		b = _floor_tilt(base, b, s)          # lying along the slope of a curving chamber floor, not level across it
	# a larva lies on the floor (its mesh sits on its origin); a cocoon is centred, so it is raised half its height
	var pos := base + b.y * (0.6 * s if shape.y > 0.5 else 0.0)
	var key := Vector3i(floori(pos.x / 1.5), floori(pos.y / 1.5), floori(pos.z / 1.5))
	if not _brood_occ.has(key):
		_brood_occ[key] = []
	_brood_occ[key].append([pos, 0.95 * s, b.x * (shape.x - shape.y) * s, shape.y * s])
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


## A turn (radians, added to the item's own heading) that keeps the whole item in the open, both ends and
## middle a little above the floor; -1 if no heading fits here.
func _fit_turn(p: Vector3, s: float, c: Dictionary, i: int) -> float:
	var shape: Vector2 = c.get("shape", Vector2(0.86, 0.38))
	var base := Vector3(p.x, _floor_cached(p), p.z)
	for turn in [0.0, PI * 0.5, PI * 0.25, PI * 0.75]:
		if _lies_clear(base, Basis(Vector3.UP, _hash(i, 3) * TAU + turn), s * 1.15, shape):    # (room to grow a little)
			return turn
	return -1.0


## How many points of an item lying at `base` (ends, middle, top) are inside the soil (0 = lies clear).
func _in_soil(base: Vector3, b: Basis, s: float, shape: Vector2) -> int:
	var mid := base + Vector3(0, 0.25 * s + 0.05, 0)
	var ax: Vector3 = b.x.normalized() * (shape.x - 0.1) * s
	var n := 0
	for q in [mid, mid + ax, mid - ax, base + Vector3(0, 2.0 * shape.y * s, 0)]:
		if _density_at(q) >= 0.5:
			n += 1
	return n


## Whether an item lying at `base` with heading `b` is clear of the soil along its whole length (low down,
## where it touches a curving floor first): its middle and both ends.
func _lies_clear(base: Vector3, b: Basis, s: float, shape: Vector2) -> bool:
	var mid := base + Vector3(0, 0.25 * s + 0.05, 0)
	var ax: Vector3 = b.x.normalized() * (shape.x - 0.1) * s
	return _density_at(mid) < 0.5 and _density_at(mid + ax) < 0.5 and _density_at(mid - ax) < 0.5


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
	for bin in _brood_occ.values():
		for o in bin:
			var c: Vector3 = o[0]
			var half: float = (o[3] if o.size() > 3 else o[1]) + 0.45       # + an ant's half width
			var ext := half + ((o[2] as Vector3).length() if o.size() > 2 else 0.0)
			for x in range(floori(c.x - ext), ceili(c.x + ext) + 1):
				for y in range(floori(c.y - 1.0), ceili(c.y + 1.0) + 1):
					for z in range(floori(c.z - ext), ceili(c.z + ext) + 1):
						var cell := Vector3i(x, y, z)
						if _brood_cells.has(cell):
							continue
						var d := _brood_offset(Vector3(cell) - Vector3(0, 0.4, 0), o)
						if absf(d.y) < 1.2 and Vector2(d.x, d.z).length() < half:
							_brood_cells[cell] = true


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
			if _visible(xf.origin):
				exs.append(xf)
	_fill(_egg_mm, exs)
	# young larvae are tiny; they grow about tenfold in mass before pupating
	_collect_freed_larvae()
	_pile(_larva_mm, _spots.larvae, sim.larvae, 300, func(l): return 0.28 + l.p * 0.8, _spots.larvae_old, _moved, Callable(), "larvae")
	_freed.eggs.clear()                      # (a hatching larva appears in the same layout as its egg goes)
	var bits := []
	if not sim.larvae.is_empty() and not _spots.larvae.is_empty():
		for k in mini(16, int(sim.protein * 1.5)):
			var base := _pile_xf(_spots.larvae, k * 3 + 1, 1.0).origin
			var xf := Transform3D(Basis(Vector3.UP, _hash(k, 9) * TAU), base + Vector3(_hash(k, 7) - 0.5, 0.1, _hash(k, 8) - 0.5))
			if _visible(xf.origin):
				bits.append(xf)
	_fill(_bits_mm, bits)
	_pile(_pupa_mm, _spots.pupae, sim.pupae.slice(0, maxi(0, sim.pupae.size() - _pending("pupate"))), 300, func(p): return p.get("s", 1.0),
		[], 1 << 20, func(p): return Color.WHITE.lerp(Color(0.72, 0.72, 0.72), smoothstep(0.75, 1.0, p.p)), "pupae")
	_mark_brood_cells()
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
