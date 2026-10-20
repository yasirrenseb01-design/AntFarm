extends "res://scripts/view/nest/parts/nest_camera.gd"
## Nest view, layer 3 of 10: chambers and their floors, walking fields, where the brood piles go (eggs, larvae,
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


## Whether floor cell v is within two cells of a drop - the mouth of a shaft or gallery going down from the
## floor: no brood is laid there (it rolled over the lip and lay down the shaft). Cached until the soil changes.
func _near_drop(v: Vector3i) -> bool:
	var k = _drop_cache.get(v)
	if k != null and int(_drop_cache.get("gen", -1)) == _soil_gen:
		return k
	if int(_drop_cache.get("gen", -1)) != _soil_gen:
		_drop_cache.clear()
		_drop_cache["gen"] = _soil_gen
	var r := _near_drop_now(v)
	_drop_cache[v] = r
	return r


var _drop_cache := {}
func _near_drop_now(v: Vector3i) -> bool:
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var n := v + Vector3i(dx, 0, dz)
			# (a shaft: open four cells down - a chamber floor that only dips toward its middle is not one)
			if nest.is_open(n) and nest.is_open(n + Vector3i(0, -1, 0)) and nest.is_open(n + Vector3i(0, -2, 0)) 					and nest.is_open(n + Vector3i(0, -3, 0)) and nest.is_open(n + Vector3i(0, -4, 0)):
				return true
	return false


## Breadth-first distances from one cell through open space: lets nest ants walk the real tunnels.
func _field_from(start: Vector3i) -> Dictionary:
	# Steps to `start` through the open nest, a step along a wall costing 1 and one across open air (the middle
	# of a wide shaft) 3: ants keep to the walls, but can still get everywhere (a field along the walls only
	# left parts of the nest cut off; one through the air ignored that ants walk on surfaces, and a widened
	# shaft then sent them sideways for ever beside its open middle)
	var f := {start: 0}
	var buckets := {0: [start]}
	var cur := 0
	var left := 1
	while left > 0:
		var b: Array = buckets.get(cur, [])
		buckets.erase(cur)
		for c in b:
			left -= 1
			if int(f[c]) != cur:
				continue
			for d in DIRS:
				var n: Vector3i = c + d
				if not nest.is_open(n):
					continue
				var nd := cur + (1 if _walkable(n) else 3)
				if nd < int(f.get(n, 1 << 30)):
					f[n] = nd
					if not buckets.has(nd):
						buckets[nd] = []
					buckets[nd].append(n)
					left += 1
		cur += 1
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
		# carried only if the day pile and the night pile are in different chambers (a founding nest has one
		# chamber for both: nobody carries larvae round and round inside it)
		_moved = 0 if _upper != _lower else 1 << 20
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
	# the first dozen lie side by side on the floor in a spiral from the middle; the rest on top of those
	# (a packet of a few eggs is one layer: nothing to stack on)
	var on_top := j >= 12
	var r := 0.3 * pow(float(j - 12 if on_top else j), 0.42) * (0.8 if on_top else 1.0)
	var a := j * 2.39996
	var tilt := (_hash(i, 4) - 0.5) * 1.2
	# resting on its lowest point: an egg (0.32 x 0.2) tipped by `tilt` stands that high on its middle
	var h := sqrt(pow(0.32 * sin(tilt), 2.0) + pow(0.2 * cos(tilt), 2.0)) + (0.34 if on_top else 0.0)
	var b := Basis(Vector3.UP, _hash(i, 3) * TAU) * Basis(Vector3.BACK, tilt)
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
		# her heavy gaster hangs below her feet: stand her up on her legs so it rests on the floor, not in it;
		# and stand on the floor where she is - off her spot (stepping to the brood) a chamber floor curves up
		# to the walls, so she rises with it and her front tips up or down with its slope (else her face
		# went into the soil as she bent to the eggs)
		var home := qp + Vector3.UP * QUEEN_LIFT
		var at := home + _queen_step
		var fwd := Vector3(cos(_queen_turn), 0.0, -sin(_queen_turn))
		var f0 := _floor_cached(home)
		var fc := _floor_cached(at)
		var ff := _floor_cached(at + fwd * 1.6)
		var fb := _floor_cached(at - fwd * 1.6)
		var want_dy := clampf(fc - f0, -0.6, 0.8) if _queen_step.length() > 0.05 else 0.0
		var want_pitch := clampf(atan2(ff - fb, 3.2), -0.3, 0.35) if _queen_step.length() > 0.05 else 0.0
		var k := minf(1.0, 4.0 * get_process_delta_time())
		_queen_dy = lerpf(_queen_dy, want_dy, k)
		_queen_pitch = lerpf(_queen_pitch, want_pitch, k)
		var qbasis := Basis(Vector3.UP, _queen_turn) * Basis(Vector3.BACK, _queen_pitch)
		_queen_xf = Transform3D(qbasis.scaled(Vector3.ONE * QUEEN_SCALE), at + Vector3.UP * _queen_dy)
		_queen_mm.set_instance_transform(0, _queen_xf)
		_queen_mm.set_instance_color(0, AntModel.body_linear(Color(0.07, 0.055, 0.047)))     # glossy black-brown, darker than her workers
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
