extends "res://scripts/view/nest/parts/nest_scene.gd"
## Nest view, layer 2 of 16 (split from parts/nest_scene.gd in v0.12.17): the soil as 3D textures for the shaders - the
## cut face and the x-ray read the soil's, the ants' feet the soil with the brood stamped in - and where they sit
## (the box held: nest x_lo, y_lo, z_lo up).


## The soil voxels as a 3D texture: the cut face (which parts of it are solid soil) and the ants' feet (the floor
## under them) read it.
func _upload_volume() -> void:
	_vol_dirty = false
	_vol_timer = 0.5
	var layers: Array[Image] = []
	var h: int = nest.hy()
	var w: int = nest.wx()
	var slice: int = w * h
	for z in nest.wz():
		layers.append(Image.create_from_data(w, h, false, Image.FORMAT_R8, nest.rho.slice(z * slice, (z + 1) * slice)))
	if _vol == null or _vol.get_height() != h or _vol.get_width() != w or _vol.get_depth() != nest.wz():
		_vol = ImageTexture3D.new()           # (new, or the soil taken in deeper or wider: a volume of the new size)
		_vol.create(Image.FORMAT_R8, w, h, nest.wz(), false, layers)
		_mat.set_shader_parameter("vol", _vol)
	else:
		_vol.update(layers)
	_set_vol_shape()
	_upload_foot_volume()


## Where the soil volumes sit (the layers held: nest.y_lo up), for every shader that reads them.
func _set_vol_shape() -> void:
	var size := Vector3(nest.wx(), nest.hy(), nest.wz())
	var org := Vector3(nest.x_lo, nest.y_lo, nest.z_lo)
	for m in [_mat] + _vol_mats:
		if m != null:
			m.set_shader_parameter("vol_size", size)
			m.set_shader_parameter("vol_org", org)
	if _xray_mat != null:
		_xray_mat.set_shader_parameter("box_min_y", float(nest.y_lo))
		_xray_mat.set_shader_parameter("box_min_xz", Vector2(nest.x_lo, nest.z_lo))
		_xray_mat.set_shader_parameter("box_max", Vector3(nest.nx - 1, nest.ny - 1, nest.nz - 1))
	if _shelf != null:
		# (it stayed at the first block's foot: chambers dug below it were hidden under it, seen only from below - the
		# keeper, 2026-10-29)
		_shelf.position.y = nest.y_lo - 1.0
	if _ghost != null:
		(_ghost.mesh as BoxMesh).size = size
		_ghost.position = Vector3(nest.x_lo + nest.wx() / 2.0 - 0.5, nest.y_lo + nest.hy() / 2.0 - 0.5, nest.z_lo + nest.wz() / 2.0 - 0.5)


var _resized_seen := 0             # nest.resized when the volumes were last laid out
var _shelf: MeshInstance3D          # the dark shelf under the soil block (nest_view)
var _vol_mats: Array = []          # the ants' materials reading the feet's volume (nest_view setup)


## What the ants' feet stand on (the ant shaders' `vol`): the soil, and the brood lying on it - an ant crossing the
## pile had its feet set down on the soil under the cocoons, through them (or, out of reach, hanging in the air).
## The brood's bodies (nest_piles: as drawn) are stamped in as solid voxels. Again at most twice a second.
func _upload_foot_volume() -> void:
	_foot_timer = 0.5 if _foot_climbs == 0 else 0.2
	_foot_rho = nest.rho.duplicate()
	var nx: int = nest.nx
	var ny: int = nest.ny
	var nz: int = nest.nz
	var y_lo: int = nest.y_lo
	var x_lo: int = nest.x_lo
	var z_lo: int = nest.z_lo
	var h: int = ny - y_lo
	var w: int = nx - x_lo
	var all_sph := []
	for bin in _brood_occ.values():
		for o in bin:
			all_sph.append(o[5] if o.size() >= 6 else ([[o[0], 0.25]] if o.size() == 2 else []))
	# and the nestmates someone is climbing over: the climber's feet stand on their backs
	_foot_climbs = 0
	for m in _mates:
		var o = m.get("over_on")
		if o != null and o.has("xf") and float(m.get("over", 0.0)) > 0.2:
			all_sph.append(call("_body_spheres", o))
			_foot_climbs += 1
	for sph in all_sph:
		if true:
			for q in sph:
				# (a density falling off across a voxel at the body's surface: read trilinearly, as the shader reads it,
				# it crosses one half right at the surface - stamped solid, the feet stood up to half a voxel off it)
				var c: Vector3 = q[0]
				var r: float = float(q[1])
				var e := r + 0.8
				for z in range(maxi(z_lo, floori(c.z - e)), mini(nz, ceili(c.z + e) + 1)):
					for y in range(maxi(y_lo, floori(c.y - e)), mini(ny, ceili(c.y + e) + 1)):
						for x in range(maxi(x_lo, floori(c.x - e)), mini(nx, ceili(c.x + e) + 1)):
							var v := int(clampf(0.6 + (r - Vector3(x, y, z).distance_to(c)), 0.0, 1.0) * 255.0)     # (0.6: its surface a touch outside the body - the feet on it, not in it)
							var ix := ((z - z_lo) * h + y - y_lo) * w + x - x_lo
							if v > _foot_rho[ix]:
								_foot_rho[ix] = v
	var layers: Array[Image] = []
	var slice: int = w * h
	for z in nz - z_lo:
		layers.append(Image.create_from_data(w, h, false, Image.FORMAT_R8, _foot_rho.slice(z * slice, (z + 1) * slice)))
	if _foot_vol == null or _foot_vol.get_height() != h or _foot_vol.get_width() != w or _foot_vol.get_depth() != nz - z_lo:
		_foot_vol = ImageTexture3D.new()
		_foot_vol.create(Image.FORMAT_R8, w, h, nz - z_lo, false, layers)
		for m in _vol_mats:
			m.set_shader_parameter("vol", _foot_vol)
	else:
		_foot_vol.update(layers)


# ---------------------------------------------------------------- the ways in (v0.12.22, sim/parts/nest_exits.gd)

## The cells the nest opens to the surface by: the entrance, and every way out dug up since. The steps out (field -1)
## run from all of them: a nestmate walking out goes to the nearest.
func _holes_in() -> Array:
	var out := [Vector3i(nest.entrance)]
	for ex in nest.exits:
		if ex.open:
			out.append(Vector3i((ex.b as Vector3).round()))
	return out


## The way in worker w came by: the one nearest where it stood on the ground when it went in (sim_foragers: its pos is
## kept; the outworld's holes are 3 px a voxel across from the entrance). The entrance for none.
func _hole_for(w) -> Vector3i:
	var best := Vector3i(nest.entrance)
	if w == null:
		return best
	var bd: float = (w.pos as Vector2).distance_to(sim.nest_pos)
	for ex in nest.exits:
		if ex.open:
			var at: Vector2 = sim.nest_pos + Vector2(ex.b.x - nest.entrance.x, ex.b.z - nest.entrance.z) * (2.0 * nest.VOXEL_MM)
			if (w.pos as Vector2).distance_to(at) < bd:
				bd = (w.pos as Vector2).distance_to(at)
				best = Vector3i((ex.b as Vector3).round())
	return best


## A distance field's first cells, at step 0 (nest_brood._field_job): one cell, or several.
func _seed_job(start) -> Dictionary:
	var ss: Array = start if start is Array else [start]
	var f := {}
	for c in ss:
		f[c] = 0
	return {"f": f, "buckets": {0: ss.duplicate()}, "cur": 0, "left": ss.size()}


# ---------------------------------------------------------------- distance fields (moved from nest_brood, v0.12.23)

## Breadth-first distances from one cell through open space: lets nest ants walk the real tunnels.
func _field_from(start) -> Dictionary:
	# Steps to `start` through the open nest, a step along a wall costing 1 and one across open air (the middle
	# of a wide shaft) 3: ants keep to the walls, but can still get everywhere (a field along the walls only
	# left parts of the nest cut off; one through the air ignored that ants walk on surfaces, and a widened
	# shaft then sent them sideways for ever beside its open middle)
	if _native != null:                 # (the same steps in C++: ~0.3 s a field here in a nest of 800, v0.12.23)
		var nf: Dictionary = _native.field_from(nest.rho, PackedInt32Array([nest.x_lo, nest.y_lo, nest.z_lo, nest.nx, nest.ny,
			nest.nz, nest.AIR]), start if start is Array else [start])
		if not nf.is_empty():
			return nf
	var job := _field_job(start)
	_field_run(job, 0)
	return job.f


## A distance field to be worked out over several frames (_field_run): until v0.11.87 every room's was redone in one
## frame each time ~25 cells were dug, ~1.2 s with the game standing still in the keeper's 12-chamber nest.
func _field_job(start) -> Dictionary:
	return _seed_job(start)                 # (a cell, or several: the entrance and the ways out - nest_volumes)


## Works the job on, step by step as _field_from did, until it is done (true) or the clock passes until_us (0: no limit).
func _field_run(job: Dictionary, until_us: int) -> bool:
	var f: Dictionary = job.f
	var buckets: Dictionary = job.buckets
	var cur: int = job.cur
	var left: int = job.left
	var rounds := 0
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
				var nd := cur + (1 if _walkable(n) else 12)     # (12: round the rim of a shaft's mouth, not over it - drawn there it hung in the air)
				if nd < int(f.get(n, 1 << 30)):
					f[n] = nd
					if not buckets.has(nd):
						buckets[nd] = []
					buckets[nd].append(n)
					left += 1
		cur += 1
		rounds += 1
		if until_us > 0 and rounds % 4 == 0 and Time.get_ticks_usec() > until_us:
			break
	job.cur = cur
	job.left = left
	return left <= 0


# ---- the soil's mesh, chunk by chunk (moved from nest_scene, v0.12.24)

## Mesher.sample, in C++ when it is there (the same values: ~1.3 ms a chunk in GDScript, v0.12.24).
func _sample(k: Vector3i) -> PackedFloat32Array:
	if _native != null:
		return _native.chunk_sample(nest.rho, PackedInt32Array([nest.x_lo, nest.y_lo, nest.z_lo, nest.nx, nest.ny, nest.nz,
			nest.AIR]), k, Mesher.CH)
	return Mesher.sample(nest, k)


## Rebuild changed chunks without stalling the frame: the soil is sampled here (fast), the mesh is made on a
## worker thread, and finished meshes are swapped in on a later frame. At most a few milliseconds a frame.
func _pump_chunks(queue: Array) -> void:
	for k in _meshing.keys():
		var job: Dictionary = _meshing[k]
		if WorkerThreadPool.is_task_completed(job.task):
			WorkerThreadPool.wait_for_task_completion(job.task)
			_meshing.erase(k)
			_set_chunk(k, job.out[0] if not job.out.is_empty() else null)
	var t0 := Time.get_ticks_usec()
	while not queue.is_empty() and _meshing.size() < 6 and Time.get_ticks_usec() - t0 < 3000:
		var k: Vector3i = queue[0]
		if _meshing.has(k):
			break                         # still being made: wait for it, then remake with the newer soil
		queue.pop_front()
		var dens := _sample(k)
		if dens.is_empty():
			_set_chunk(k, null)
			continue
		var out := []
		var task := WorkerThreadPool.add_task(func(): out.append(Mesher.mesh_from(dens, k)))
		_meshing[k] = {"task": task, "out": out}


func _set_chunk(k: Vector3i, mesh: ArrayMesh) -> void:
	var mi: MeshInstance3D = _chunks.get(k)
	if mesh == null:
		if mi:
			mi.queue_free()
			_chunks.erase(k)
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.material_override = _xray_mat if xray else _mat
		add_child(mi)
		_chunks[k] = mi
	mi.mesh = mesh
