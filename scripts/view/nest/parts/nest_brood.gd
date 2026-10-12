extends "res://scripts/view/nest/parts/nest_camera.gd"
## Nest view, layer 3 of 7: chambers and their floors, walking fields, brood piles (eggs, larvae,
## cocoons) and the queen's pose.


# ---------------------------------------------------------------- brood and queen

func _floor_cells(ch: Dictionary) -> Array:
	var out := []
	var c: Vector3 = ch.c
	var g: float = ch.goal
	for y in range(int(c.y - g * 0.5) - 1, int(c.y + g * 0.5) + 2):
		for z in range(int(c.z - g) - 1, int(c.z + g) + 2):
			for x in range(int(c.x - g) - 1, int(c.x + g) + 2):
				var v := Vector3i(x, y, z)
				if nest.is_open(v) and not nest.is_open(v + Vector3i(0, -1, 0)) and nest.inside(v + Vector3i(0, -1, 0)):
					if Vector3(v).distance_to(c) < g + 1.5:
						out.append(Vector3(x, y - 0.45, z))
	return out


## Breadth-first distances from one cell through open space: lets nest ants walk the real tunnels.
func _field_from(start: Vector3i) -> Dictionary:
	var f := {start: 0}
	var q: Array[Vector3i] = [start]
	var head := 0
	while head < q.size():
		var c := q[head]
		head += 1
		var dc: int = f[c]
		for d in DIRS:
			var n := c + d
			if not f.has(n) and nest.is_open(n):
				f[n] = dc + 1
				q.append(n)
	return f


func _refresh_spots() -> void:
	_rooms.clear()
	var all := []
	var queen_room := -1
	for i in nest.chambers.size():
		var ch: Dictionary = nest.chambers[i]
		var cells := _floor_cells(ch)
		if cells.is_empty():
			continue
		all.append_array(cells)
		var mid: Vector3 = cells[cells.size() / 2]
		_rooms.append({"y": ch.c.y, "spots": cells, "cell": Vector3i(roundi(mid.x), roundi(mid.y + 0.45), roundi(mid.z)),
			"queen": ch.kind == "queen"})
		if ch.kind == "queen":
			queen_room = _rooms.size() - 1
	_spots.all = all
	_spots.queen = Vector3.ZERO
	_spots.eggs = all
	if queen_room >= 0:
		_spots.eggs = _rooms[queen_room].spots
		# the queen sits in the middle of her chamber floor
		var qc: Vector3 = nest.chambers.filter(func(ch): return ch.kind == "queen")[0].c
		var best_d := INF
		for sp in _rooms[queen_room].spots:
			var d := Vector2(sp.x - qc.x, sp.z - qc.z).length_squared()
			if d < best_d:
				best_d = d
				_spots.queen = sp
	# egg packets lie a little way from the queen, nearest-first so the first packet is beside her
	_egg_spots = []
	if _spots.queen != Vector3.ZERO:
		var cands := []
		for sp in _spots.eggs:
			var d := Vector2(sp.x - _spots.queen.x, sp.z - _spots.queen.z).length()
			if d > 2.6:
				cands.append([absf(d - 3.4), sp])
		cands.sort_custom(func(a, b): return a[0] < b[0])
		for c in cands:
			_egg_spots.append(c[1])
	# brood chambers from the top down; Lasius keep pupae in the upper, drier chambers
	var brood := []
	for i in _rooms.size():
		if not _rooms[i].queen:
			brood.append(i)
	brood.sort_custom(func(a, b): return _rooms[a].y > _rooms[b].y)
	if brood.is_empty() and queen_room >= 0:
		brood = [queen_room]
	var half := maxi(1, brood.size() / 2)
	_upper = brood.slice(0, half)
	_lower = brood.slice(brood.size() - half) if brood.size() > 1 else brood.duplicate()
	_spots.pupae = _room_spots(_upper, all)

	# a fresh distance field per room only when the tunnels have changed noticeably
	if absi(nest.air - _fields_air) > 25 or _fields.size() != _rooms.size() + 1:
		_fields_air = nest.air
		_fields.clear()
		_fields[-1] = _field_from(nest.entrance)
		for i in _rooms.size():
			_fields[i] = _field_from(_rooms[i].cell)
	_update_larva_group()


func _room_spots(rooms: Array, fallback: Array) -> Array:
	var out := []
	for r in rooms:
		out.append_array(_rooms[r].spots)
	return out if not out.is_empty() else fallback


## Nurses move larvae up toward the warm surface layer by day and back down at night.
func _update_larva_group() -> void:
	var warm_above: bool = sim.climate.air > sim.climate.nest + 0.5
	var group := "up" if warm_above else "down"
	if _larva_group == "":
		_larva_group = group
		_larva_prev = group
		_moved = 1 << 20
	elif group != _larva_group and _moved >= sim.larvae.size():
		_larva_prev = _larva_group
		_larva_group = group
		_moved = 0
	_spots.larvae = _room_spots(_upper if _larva_group == "up" else _lower, _spots.all)
	_spots.larvae_old = _room_spots(_upper if _larva_prev == "up" else _lower, _spots.all)


func _pile_xf(spots: Array, i: int, scale: float) -> Transform3D:
	var sp: Vector3 = spots[i % spots.size()]
	var layer := mini(i / spots.size(), 2)
	var p := sp + Vector3(_hash(i, 1) - 0.5, 0.25 + layer * 0.45, _hash(i, 2) - 0.5) * Vector3(0.8, 1, 0.8)
	return Transform3D(Basis(Vector3.UP, _hash(i, 3) * TAU).scaled(Vector3.ONE * scale), p)


## Egg i in its packet: Lasius eggs are sticky, so nurses keep (and carry) them as small heaps.
func _egg_xf(i: int) -> Transform3D:
	var spots: Array = _egg_spots if not _egg_spots.is_empty() else _spots.eggs
	var c := i / CLUMP
	var j := i % CLUMP
	var centre: Vector3 = spots[(c * 3) % spots.size()]
	var rmax := 0.3 * pow(float(CLUMP), 0.42)
	var r := 0.3 * pow(float(j), 0.42)
	var a := j * 2.39996
	var h := 0.2 + 0.42 * (1.0 - r / rmax)
	var b := Basis(Vector3.UP, _hash(i, 3) * TAU) * Basis(Vector3.BACK, (_hash(i, 4) - 0.5) * 1.2)
	return Transform3D(b, centre + Vector3(cos(a) * r, h, sin(a) * r))


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
	for i in n:
		# items not yet carried over stay in the old pile
		var src: Array = spots if (i < moved or old_spots.is_empty()) else old_spots
		if not cands.has(src):
			var centre := _pile_centre(src, kind)
			cands[src] = {"list": _pile_places(src, centre), "next": 0, "centre": centre,
				"reach": 0.9 + 0.75 * sqrt(float(n))}      # a compact heap: one layer about this wide, then on top
		var s: float = scale_fn.call(items[i])
		var xf := _place_brood(cands[src], s, i)
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
## `_brood_occ` (cleared per layout) holds what has been laid: [centre, radius] binned by 1.5 units.
func _place_brood(c: Dictionary, s: float, i: int) -> Transform3D:
	var places: Array = c.list
	var r := 0.95 * s                        # a larva or cocoon is long (2-2.7 units): keep their ends apart too
	var best := Vector3.INF
	var lift := 0.0
	if not c.get("full", false):
		for k in range(c.next, places.size()):
			var p: Vector3 = places[k]
			if _queen_mm.instance_count > 0 and _queen_gap(p) < r + 0.5:
				continue
			if p.distance_to(c.centre) > c.reach:
				break                          # the heap is as wide as it gets: go on top instead
			if _brood_free(p, r):
				best = p
				c.next = maxi(c.next, k - 8)      # the places before this are (nearly all) taken
				break
		if best == Vector3.INF:
			c.full = true                      # no floor left in this pile: the rest go on top
	if best == Vector3.INF and not places.is_empty():
		# the heap's floor is full: lie on top, resting on whatever is highest there
		var inner := places.filter(func(p): return p.distance_to(c.centre) <= c.reach and (_queen_mm.instance_count == 0 or _queen_gap(p) >= r + 0.5))
		if inner.is_empty():
			inner = places
		best = inner[i % inner.size()]
		for o in _brood_near(best):
			if Vector2(o[0].x - best.x, o[0].z - best.z).length() < r + o[1]:
				lift = maxf(lift, o[0].y - best.y + o[1] * 0.75)
	var pos := best + Vector3(0, 0.25 * s + lift, 0)
	var key := Vector3i(floori(pos.x / 1.5), floori(pos.y / 1.5), floori(pos.z / 1.5))
	if not _brood_occ.has(key):
		_brood_occ[key] = []
	_brood_occ[key].append([pos, r])
	return Transform3D(Basis(Vector3.UP, _hash(i, 3) * TAU).scaled(Vector3.ONE * s), pos)


func _brood_near(p: Vector3) -> Array:
	var out := []
	var key := Vector3i(floori(p.x / 1.5), floori(p.y / 1.5), floori(p.z / 1.5))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1, 2]:
			for dz in [-1, 0, 1]:
				out.append_array(_brood_occ.get(key + Vector3i(dx, dy, dz), []))
	return out


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
		for i in mini(400, maxi(0, sim.eggs.size() - _pending("egg"))):
			var xf := _egg_xf(i)
			var ek := Vector3i(floori(xf.origin.x / 1.5), floori(xf.origin.y / 1.5), floori(xf.origin.z / 1.5))
			if not _brood_occ.has(ek):
				_brood_occ[ek] = []
			_brood_occ[ek].append([xf.origin, 0.3])       # larvae and cocoons are not laid on the eggs
			if _visible(xf.origin):
				exs.append(xf)
	_fill(_egg_mm, exs)
	# young larvae are tiny; they grow about tenfold in mass before pupating
	_pile(_larva_mm, _spots.larvae, sim.larvae, 300, func(l): return 0.28 + l.p * 0.8, _spots.larvae_old, _moved, Callable(), "larvae")
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


func _queen_pose() -> void:
	var qp: Vector3 = _spots.queen
	var show: bool = sim.queen.alive and qp != Vector3.ZERO and _visible(qp)
	_queen_mm.instance_count = 1 if show else 0
	if show:
		# her heavy gaster hangs below her feet: stand her up on her legs so it rests on the floor, not in it
		_queen_xf = Transform3D(Basis(Vector3.UP, _queen_turn).scaled(Vector3.ONE * QUEEN_SCALE), qp + Vector3.UP * QUEEN_LIFT)
		_queen_mm.set_instance_transform(0, _queen_xf)
		_queen_mm.set_instance_color(0, AntModel.tint(Color(0.075, 0.05, 0.038)))
		# the cells under her body, for the nestmates' routes
		_queen_cells.clear()
		var qa: Vector3 = _queen_xf * QUEEN_HEAD
		var qb: Vector3 = _queen_xf * QUEEN_TAIL
		for x in range(int(qp.x) - 5, int(qp.x) + 6):
			for y in range(int(qp.y) - 1, int(qp.y) + 3):
				for z in range(int(qp.z) - 5, int(qp.z) + 6):
					var c := Vector3(x, y, z)
					var t := clampf((c - qa).dot(qb - qa) / maxf((qb - qa).length_squared(), 0.001), 0.0, 1.0)
					if c.distance_to(qa.lerp(qb, t)) < 1.1:
						_queen_cells[Vector3i(x, y, z)] = true


## How far a point is from the surface of the queen's body (negative: inside it).
func _queen_gap(p: Vector3) -> float:
	var qa: Vector3 = _queen_xf * QUEEN_HEAD
	var qb: Vector3 = _queen_xf * QUEEN_TAIL
	var t := clampf((p - qa).dot(qb - qa) / maxf((qb - qa).length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(qa.lerp(qb, t)) - QUEEN_R


func _nearest_spot(p: Vector3, spots: Array) -> Vector3:
	var best := Vector3.INF
	var bd := 9.0
	for s in spots:
		var d := p.distance_squared_to(s)
		if d < bd:
			bd = d
			best = s
	return best


func _random_room() -> int:
	return randi() % _rooms.size() if not _rooms.is_empty() else -1


func _brood_room(group: String) -> int:
	var list: Array = _upper if group == "up" else _lower
	return list[randi() % list.size()] if not list.is_empty() else _random_room()


func _queen_room() -> int:
	for i in _rooms.size():
		if _rooms[i].queen:
			return i
	return _random_room()
