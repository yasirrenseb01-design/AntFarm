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


# ---------------------------------------------------------------- the heaps on top of the block (moved from nest_piles, v0.12.22)

## The crater round the entrance on top of the block: a heap as big as the soil dug out (sim/mound.gd, as the outworld's
## ground), pellets on its surface in three shapes (view/common/lumps.gd; until v0.12.8 the pellets alone, at most 900) -
## and one round each way out the nest has dug up, as big as the soil carried out of that one (nest_exits.gd, v0.12.22).
var _crater_key := []
var _mound_mis: Array = []              # a heap's mesh for each way out (the entrance's: _mound_mi)

func _craters() -> void:
	var heaps := [[Vector3(nest.entrance) + Vector3(0, 0.6, 0), nest.excavated]]
	var key := [nest.excavated / 4, nest.exits_ver]
	for ex in nest.exits:
		if ex.open:
			heaps.append([Vector3(ex.b.x, nest.ny - 1, ex.b.z).round() + Vector3(0, 0.6, 0), int(ex.get("soil", 0))])
			key.append(int(ex.get("soil", 0)) / 4)
	if key == _crater_key:
		return
	_crater_key = key
	var xfs := []
	for k in heaps.size():
		var e: Vector3 = heaps[k][0]
		var soil: int = heaps[k][1]
		var hr := Mound.size(soil)
		_mound_mesh(k, e, hr)
		var reach: float = hr.y * 1.8
		for i in mini(soil / 2, 900 if k == 0 else 420):
			var a := _hash(i + k * 5003, 5) * TAU
			var r: float = lerpf(Mound.HOLE.y - 0.6, reach, sqrt(_hash(i + k * 5003, 6)))
			var p := e + Vector3(cos(a) * r, 0.0, sin(a) * r)
			if p.x < nest.x_lo - 0.4 or p.z < nest.z_lo - 0.4 or p.x > nest.nx - 0.6 or p.z > nest.nz - 0.6:
				continue                                  # (past the block's edge: the glass)
			p.y += Mound.height(r, hr.x, hr.y) - 0.15 + 0.2 * _hash(i + k * 5003, 7)
			xfs.append(Transform3D(Basis(Vector3.UP, a), p))
	Lumps.fill(_pellet_mm, xfs)


## Heap k's surface as a mesh over the block's top round its hole (cut off at the block's edges, as by the glass).
func _mound_mesh(k: int, e: Vector3, hr: Vector2) -> void:
	while _mound_mis.size() <= k:
		var mi := MeshInstance3D.new()
		var mm := _mat_simple(Color(0.36, 0.26, 0.17), 1.0)
		mm.cull_mode = BaseMaterial3D.CULL_DISABLED      # (seen from its top; its underside is never in view but through the soil)
		mi.material_override = mm
		add_child(mi)
		_mound_mis.append(mi)
		if _mound_mis.size() == 1:
			_mound_mi = mi
	var reach: float = hr.y * 2.0
	var g := 48
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for j in g + 1:
		for i in g + 1:
			var x := clampf(e.x + lerpf(-reach, reach, float(i) / g), nest.x_lo - 0.5, nest.nx - 0.5)
			var z := clampf(e.z + lerpf(-reach, reach, float(j) / g), nest.z_lo - 0.5, nest.nz - 0.5)
			var d := Vector2(x - e.x, z - e.z).length()
			pts.append(Vector3(x, e.y - 0.35 + Mound.height(d, hr.x, hr.y), z))
	for j in g:
		for i in g:
			var a: Vector3 = pts[j * (g + 1) + i]
			var b: Vector3 = pts[j * (g + 1) + i + 1]
			var c: Vector3 = pts[(j + 1) * (g + 1) + i]
			var d2: Vector3 = pts[(j + 1) * (g + 1) + i + 1]
			if maxf(maxf(a.y, b.y), maxf(c.y, d2.y)) < e.y - 0.3:
				continue                              # (flat ground: the block's own top is there)
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(b)
			st.add_vertex(d2)
			st.add_vertex(c)
	st.generate_normals()
	_mound_mis[k].mesh = st.commit()


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

