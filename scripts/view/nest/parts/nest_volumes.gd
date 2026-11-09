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
