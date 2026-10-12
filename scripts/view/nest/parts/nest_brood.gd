extends "res://scripts/view/nest/parts/nest_camera.gd"
## Nest view, layer 3 of 8: chambers and their floors, walking fields, where the brood piles go (eggs, larvae,
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
	var at := centre + Vector3(cos(a) * r, 0.0, sin(a) * r)
	for k in 4:                                    # never inside the chamber wall: drawn in toward the packet's middle
		if _density_at(Vector3(at.x, _floor_cached(at) + 0.3, at.z)) < 0.5:
			break
		at = centre.lerp(at, 0.6)
	at.y = _floor_cached(at) + h                   # on the real floor under it (the spots are only near it)
	return Transform3D(b, at)


func _queen_pose() -> void:
	var qp: Vector3 = _spots.queen
	var show: bool = sim.queen.alive and qp != Vector3.ZERO and _visible(qp)
	_queen_mm.instance_count = 1 if show else 0
	if show:
		# her heavy gaster hangs below her feet: stand her up on her legs so it rests on the floor, not in it
		_queen_xf = Transform3D(Basis(Vector3.UP, _queen_turn).scaled(Vector3.ONE * QUEEN_SCALE), qp + Vector3.UP * QUEEN_LIFT + _queen_step)
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


## Like _queen_gap but for her body only (thorax to gaster tip): her head may reach in among the brood to
## lick or feed it without pushing anything aside.
func _queen_body_gap(p: Vector3) -> float:
	var qa: Vector3 = _queen_xf * Vector3(0.5, 0.5, 0.0)
	var qb: Vector3 = _queen_xf * QUEEN_TAIL
	var t := clampf((p - qa).dot(qb - qa) / maxf((qb - qa).length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(qa.lerp(qb, t)) - QUEEN_R


## Whether the queen is in the middle of a moment (laying, tending the brood, opening a cocoon): she is off
## her place, and the brood she brushes past stays where it is.
func _queen_busy() -> bool:
	for a in _anims:
		if a.k == "egg" or a.k == "care" or (a.k == "eclose" and a.get("queen", false)):
			return true
	return false


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
