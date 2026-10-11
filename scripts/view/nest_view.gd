extends Node3D
## 3D view of the underground nest: the soil block sliced open by a camera-facing cut plane,
## with diggers from the simulation, resting nestmates, brood piles and the queen.

const Ant := preload("res://scripts/sim/ant.gd")
const Mesher := preload("res://scripts/view/nest_mesher.gd")
const AntModel := preload("res://scripts/view/ant_model3d.gd")
const CH := 16
const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var sim
var nest
var active := false
var speed := 1.0
var cut_offset := 0.0            # voxels from the block centre toward the camera

var yaw := 0.55
var pitch := 0.22
var cam_dist := 75.0
var target := Vector3.ZERO
# where the camera is heading; input moves these and the view eases toward them each frame
var yaw_t := 0.55
var pitch_t := 0.22
var dist_t := 75.0
var target_t := Vector3.ZERO
var _last_click := 0

var _cam: Camera3D
var _mat: ShaderMaterial
var _xray_mat: ShaderMaterial
var xray := false                 # "see through the soil": tunnels drawn as a translucent cast
var _ghost: MeshInstance3D        # faint outline of the soil block in x-ray view
var _ant_meshes := {}             # "hi"/"lo" -> [pose A, pose B]
var _lod := ""
var _chunks := {}
var _queue: Array = []
var _ant_mm: MultiMesh
var _queen_mm: MultiMesh
var _queen_anim := 0.0
var _queen_lay := 0.0
var _last_eggs := 0
var _egg_mm: MultiMesh
var _larva_mm: MultiMesh
var _pupa_mm: MultiMesh
var _pellet_mm: MultiMesh
var _mates: Array = []
var _dig_vis := {}
var _spots := {"eggs": [], "larvae": [], "larvae_old": [], "pupae": [], "all": [], "queen": Vector3.ZERO}
var _rooms: Array = []             # chambers with a floor: {"y", "spots", "cell", "queen"}
var _upper: Array = []             # brood rooms in the upper half of the nest
var _lower: Array = []
var _fields := {}                  # room index (or -1 = entrance) -> {cell: steps}
var _fields_air := -1000
var _larva_group := ""             # "up" by day, "down" by night
var _larva_prev := ""
var _moved := 1 << 20              # larvae already carried to the current group's rooms
var _carry_larva_mm: MultiMesh
var _carry_pellet_mm: MultiMesh
const CARRY_OFFSET := Transform3D(Basis(Vector3(0.55, 0, 0), Vector3(0, 0.55, 0), Vector3(0, 0, 0.55)), Vector3(1.35, 0.45, 0.0))
var _spot_timer := 0.0
var _rot := false
var _pan := false
var _plane_n := Vector3(0, 0, 1)
var _plane_w := 1e6
var _t := 0.0
signal cut_changed(value: float)
var _brood_sig: Array = []
var _mound_n := -1
var _vol: ImageTexture3D
var _vol_timer := 0.0
var _vol_dirty := true


func setup(s) -> void:
	sim = s
	nest = sim.nest
	target = Vector3(nest.nx / 2.0, nest.ny - 16.0, nest.nz / 2.0)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.035, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.45, 0.38)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 38
	_cam.far = 3000
	add_child(_cam)
	var lamp := OmniLight3D.new()       # keeper's lamp riding with the camera so the cut face is lit
	lamp.light_color = Color(1.0, 0.85, 0.7)
	lamp.light_energy = 0.9
	lamp.omni_range = 600
	lamp.omni_attenuation = 0.6
	_cam.add_child(lamp)

	var grain := NoiseTexture2D.new()
	grain.width = 256
	grain.height = 256
	grain.seamless = true
	var gn := FastNoiseLite.new()
	gn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	gn.frequency = 0.03
	gn.fractal_octaves = 4
	grain.noise = gn
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/soil.gdshader")
	_mat.set_shader_parameter("grain", grain)
	_mat.set_shader_parameter("top_y", nest.ny - 0.5)
	_mat.set_shader_parameter("vol_size", Vector3(nest.nx, nest.ny, nest.nz))
	_xray_mat = ShaderMaterial.new()
	_xray_mat.shader = load("res://shaders/xray.gdshader")
	_xray_mat.set_shader_parameter("box_max", Vector3(nest.nx - 1, nest.ny - 1, nest.nz - 1))
	_xray_mat.set_shader_parameter("top_y", nest.ny - 0.5)
	_xray_mat.set_shader_parameter("grain", grain)
	_ghost = MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(nest.nx, nest.ny, nest.nz)
	_ghost.mesh = gb
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.42, 0.3, 0.2, 0.12)
	gm.cull_mode = BaseMaterial3D.CULL_FRONT
	gm.no_depth_test = false
	gm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_ghost.material_override = gm
	_ghost.position = Vector3(nest.nx / 2.0 - 0.5, nest.ny / 2.0 - 0.5, nest.nz / 2.0 - 0.5)
	_ghost.visible = false
	add_child(_ghost)
	_upload_volume()

	# the shelf the block sits on
	var shelf := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	shelf.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.07, 0.06, 0.06)
	sm.roughness = 0.7
	shelf.material_override = sm
	shelf.position = Vector3(nest.nx / 2.0, -1.0, nest.nz / 2.0)
	add_child(shelf)

	# Lasius niger: glossy dark body with a fine pubescence that gives the gaster a dull sheen
	# legs, antennae, head, mandibles and gaster are animated per ant by shaders/ant.gdshader
	var ant_mat := ShaderMaterial.new()
	ant_mat.shader = load("res://shaders/ant.gdshader")
	_ant_meshes = {"hi": AntModel.make(), "lo": AntModel.make(0.0, false, false)}
	_ant_mm = _multimesh(_ant_meshes.lo, ant_mat, true)
	_ant_mm.use_custom_data = true
	_egg_mm = _multimesh(_ellipsoid(0.32, 0.22), _mat_simple(Color(0.96, 0.94, 0.86), 0.25), false)
	_larva_mm = _multimesh(_ellipsoid(1.0, 0.8), _mat_simple(Color(0.93, 0.87, 0.7), 0.35), false)
	_pupa_mm = _multimesh(_ellipsoid(1.35, 0.62), _mat_simple(Color(0.78, 0.62, 0.42), 0.8), false)
	_pellet_mm = _multimesh(_ellipsoid(0.42, 0.34), _mat_simple(Color(0.42, 0.3, 0.2), 0.95), false)
	_carry_larva_mm = _multimesh(_ellipsoid(1.0, 0.8), _mat_simple(Color(0.93, 0.87, 0.7), 0.35), false)
	_carry_pellet_mm = _multimesh(_ellipsoid(0.8, 0.65), _mat_simple(Color(0.45, 0.32, 0.2), 0.95), false)
	_queen_mm = _multimesh(AntModel.make(0.0, true, true), ant_mat, true)
	_queen_mm.use_custom_data = true

	if nest.slab:
		_build_ant_farm_case()
		yaw = 0.0
		pitch = 0.12
		cam_dist = 150.0
		target = Vector3(nest.nx / 2.0, nest.ny / 2.0 + 6.0, nest.nz / 2.0)
	reset_view()
	yaw = yaw_t
	pitch = pitch_t
	cam_dist = dist_t
	target = target_t
	# chunk -1 owns the block faces on the low sides (edges from outside into voxel 0)
	for kz in range(-1, (nest.nz + CH - 1) / CH + 1):
		for ky in range(-1, (nest.ny + CH - 1) / CH + 1):
			for kx in range(-1, (nest.nx + CH - 1) / CH + 1):
				_queue.append(Vector3i(kx, ky, kz))
	nest.dirty.clear()
	visible = false


# ---------------------------------------------------------------- meshes

func _mat_simple(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _ellipsoid(length: float, wid: float) -> Mesh:
	var s := SphereMesh.new()
	s.radius = wid
	s.height = wid * 2.0
	s.radial_segments = 10
	s.rings = 5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(s, 0, Transform3D(Basis.from_scale(Vector3(length / wid, 1, 1)), Vector3.ZERO))
	return st.commit()


func _multimesh(mesh: Mesh, mat: Material, colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)
	return mm


func _seg(st: SurfaceTool, cyl: Mesh, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	st.append_from(cyl, 0, Transform3D(Basis(x * r, y * d.length(), z * r), (a + b) * 0.5))


## Worker ant ~4 mm long (2.7 voxels), facing +x, feet at y = 0.


func _build_ant_farm_case() -> void:
	# two glass panes a few millimetres apart held in a wooden frame
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.85, 0.93, 1.0, 0.07)
	glass.roughness = 0.04
	glass.metallic_specular = 1.0
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.22, 0.12)
	wood.roughness = 0.55
	var w := float(nest.nx)
	var h := float(nest.ny)
	var d := float(nest.nz)
	for z in [d + 0.2, -1.2]:
		_box(Vector3(w + 2, h + 8, 0.4), Vector3(w / 2.0 - 0.5, h / 2.0 + 3.0, z), glass)
	var depth := d + 3.0
	_box(Vector3(w + 8, 4, depth), Vector3(w / 2.0 - 0.5, -2.5, d / 2.0 - 0.5), wood)        # base
	_box(Vector3(4, h + 12, depth), Vector3(-3.0, h / 2.0 + 3.0, d / 2.0 - 0.5), wood)        # sides
	_box(Vector3(4, h + 12, depth), Vector3(w + 2.0, h / 2.0 + 3.0, d / 2.0 - 0.5), wood)
	_box(Vector3(w + 8, 2.5, depth), Vector3(w / 2.0 - 0.5, h + 9.0, d / 2.0 - 0.5), wood)  # lid


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


# ---------------------------------------------------------------- per frame

func set_active(on: bool) -> void:
	active = on
	visible = on
	_cam.current = on
	if on:
		_refresh_spots()


func refresh(delta: float) -> void:
	if not active:
		return
	_t += delta
	if not nest.dirty.is_empty():
		_vol_dirty = true
	for k in nest.dirty:
		if not _queue.has(k):
			_queue.append(k)
	nest.dirty.clear()
	_vol_timer -= delta
	if _vol_dirty and _vol_timer <= 0.0:
		_upload_volume()
	var budget := 8
	while budget > 0 and not _queue.is_empty():
		_build_chunk(_queue.pop_front())
		budget -= 1
	_ease_camera(delta)
	_update_camera()
	var lod := "hi" if cam_dist < 90.0 else "lo"      # detailed ants only when they are big on screen
	if lod != _lod:
		_lod = lod
		_ant_mm.mesh = _ant_meshes[lod]
	_mat.set_shader_parameter("cut_plane", Vector4(_plane_n.x, _plane_n.y, _plane_n.z, _plane_w))
	_mat.set_shader_parameter("humidity", sim.humidity)
	_xray_mat.set_shader_parameter("humidity", sim.humidity)
	_spot_timer -= delta
	if _spot_timer <= 0.0:
		_spot_timer = 1.5
		_refresh_spots()
	# brood and the mound change slowly; rebuild their instances only when something moved
	var sig := [sim.eggs.size(), sim.larvae.size(), sim.pupae.size(), nest.excavated / 2, snappedf(_plane_w, 0.5),
		snappedf(_plane_n.x, 0.05), _spot_timer > 1.45, _moved, _larva_group]
	if sig != _brood_sig:
		_brood_sig = sig
		_update_brood()
	_queen_pose()
	_update_ants(delta)


## The cut face needs to know where the plane crosses soil versus open tunnel: give it the voxels.
func _upload_volume() -> void:
	_vol_dirty = false
	_vol_timer = 0.5
	var layers: Array[Image] = []
	var slice: int = nest.nx * nest.ny
	for z in nest.nz:
		layers.append(Image.create_from_data(nest.nx, nest.ny, false, Image.FORMAT_R8, nest.rho.slice(z * slice, (z + 1) * slice)))
	if _vol == null:
		_vol = ImageTexture3D.new()
		_vol.create(Image.FORMAT_R8, nest.nx, nest.ny, nest.nz, false, layers)
		_mat.set_shader_parameter("vol", _vol)
	else:
		_vol.update(layers)


func _build_chunk(k: Vector3i) -> void:
	var mesh: ArrayMesh = Mesher.build(nest, k)
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


func snap_camera() -> void:
	yaw_t = yaw
	pitch_t = pitch
	dist_t = cam_dist
	target_t = target


func _ease_camera(delta: float) -> void:
	# keyboard: WASD / arrows move, Q/E turn, R/F tilt, +/- zoom
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv.y -= 1
	if mv != Vector2.ZERO:
		var right := _cam.global_transform.basis.x
		target_t += (right * mv.x + Vector3.UP * mv.y) * dist_t * 0.9 * delta
	if Input.is_key_pressed(KEY_Q):
		yaw_t += 1.4 * delta
	if Input.is_key_pressed(KEY_E):
		yaw_t -= 1.4 * delta
	if Input.is_key_pressed(KEY_R):
		pitch_t = clampf(pitch_t + 0.9 * delta, -0.2, 1.45)
	if Input.is_key_pressed(KEY_F):
		pitch_t = clampf(pitch_t - 0.9 * delta, -0.2, 1.45)
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		zoom_by(1.0 - 1.6 * delta)
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		zoom_by(1.0 + 1.6 * delta)
	var lo := Vector3(-30, -20, -30)
	var hi := Vector3(nest.nx + 30, nest.ny + 30, nest.nz + 30)
	target_t = target_t.clamp(lo, hi)
	var k := 1.0 - exp(-10.0 * delta)
	yaw = lerp_angle(yaw, yaw_t, k)
	pitch = lerpf(pitch, pitch_t, k)
	cam_dist = lerpf(cam_dist, dist_t, k)
	target = target.lerp(target_t, k)


func zoom_by(f: float) -> void:
	dist_t = clampf(dist_t * f, 6.0, 400.0)


func turn_by(a: float) -> void:
	yaw_t += a


func reset_view() -> void:
	if nest.slab:
		yaw_t = 0.0
		pitch_t = 0.12
		dist_t = 150.0
		target_t = Vector3(nest.nx / 2.0, nest.ny / 2.0 + 6.0, nest.nz / 2.0)
	elif nest.chambers.size() == 1:
		# a lone founding queen: start close on her chamber, with the cut just in front of it
		var c: Vector3 = nest.chambers[0].c
		yaw_t = 0.35
		pitch_t = 0.25
		dist_t = 32.0
		target_t = c
		# slice straight through her chamber
		var dir := Vector3(sin(yaw_t), 0, cos(yaw_t))
		cut_offset = clampf(dir.dot(c) - dir.dot(Vector3(nest.nx / 2.0, 0, nest.nz / 2.0)) + 1.0, -32, 32)
		cut_changed.emit(cut_offset)
	else:
		yaw_t = 0.55
		pitch_t = 0.22
		dist_t = 75.0
		target_t = Vector3(nest.nx / 2.0, nest.ny - 16.0, nest.nz / 2.0)


## Glide the camera to something worth looking at: "queen", "larvae", "pupae", "entrance".
func focus(what: String) -> void:
	var p := Vector3.INF
	match what:
		"queen":
			p = _spots.queen if _spots.queen != Vector3.ZERO else p
		"larvae":
			if not _spots.larvae.is_empty():
				p = _spots.larvae[_spots.larvae.size() / 2]
		"pupae":
			if not _spots.pupae.is_empty():
				p = _spots.pupae[_spots.pupae.size() / 2]
		"entrance":
			p = Vector3(nest.entrance)
			dist_t = 45.0
	if p == Vector3.INF:
		return
	target_t = p
	if what != "entrance":
		dist_t = minf(dist_t, 26.0)
	if not xray and not nest.slab:
		# slide the cut so the spot sits just behind it
		var dir := Vector3(sin(yaw_t), 0, cos(yaw_t))
		cut_offset = clampf(dir.dot(p) - dir.dot(Vector3(nest.nx / 2.0, 0, nest.nz / 2.0)) + 1.5, -32, 32)
		cut_changed.emit(cut_offset)


## Double-click: fly to the chamber (or queen) nearest the mouse.
func _focus_at(screen: Vector2) -> void:
	var best := Vector3.INF
	var bd := 140.0
	var cands: Array = []
	for r in _rooms:
		cands.append(Vector3(r.cell))
	if _spots.queen != Vector3.ZERO:
		cands.append(_spots.queen)
	cands.append(Vector3(nest.entrance))
	for c in cands:
		if _cam.is_position_behind(c):
			continue
		var d := _cam.unproject_position(c).distance_to(screen)
		if d < bd:
			bd = d
			best = c
	if best != Vector3.INF:
		target_t = best
		dist_t = minf(dist_t, 30.0)


func _update_camera() -> void:
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	_cam.position = target + dir * cam_dist
	_cam.look_at(target, Vector3.UP)
	if nest.slab:
		# a glass ant farm is watched through the front pane: show the soil right behind the glass
		_plane_n = Vector3(0, 0, 1)
		_plane_w = nest.nz - 1.6
		return
	var h := Vector3(dir.x, 0, dir.z).normalized()
	_plane_n = h
	var centre := Vector3(nest.nx / 2.0, 0, nest.nz / 2.0)
	_plane_w = h.dot(centre) + cut_offset


func set_xray(on: bool) -> void:
	xray = on
	_ghost.visible = on
	for k in _chunks:
		_chunks[k].material_override = _xray_mat if on else _mat
	_brood_sig = []


func _visible(p: Vector3) -> bool:
	if xray:
		return true
	return _plane_n.dot(p) <= _plane_w + 0.3


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


func _hash(i: int, s: int) -> float:
	var x := sin(i * 12.9898 + s * 78.233) * 43758.5453
	return x - floor(x)


func _pile_xf(spots: Array, i: int, scale: float) -> Transform3D:
	var sp: Vector3 = spots[i % spots.size()]
	var layer := i / spots.size()
	var p := sp + Vector3(_hash(i, 1) - 0.5, 0.25 + layer * 0.45, _hash(i, 2) - 0.5) * Vector3(0.8, 1, 0.8)
	return Transform3D(Basis(Vector3.UP, _hash(i, 3) * TAU).scaled(Vector3.ONE * scale), p)


func _pile(mm: MultiMesh, spots: Array, items: Array, max_n: int, scale_fn: Callable, old_spots := [], moved := 1 << 20) -> void:
	var n := mini(items.size(), max_n)
	if spots.is_empty():
		n = 0
	var xs := []
	for i in n:
		# items not yet carried over stay in the old pile
		var src: Array = spots if (i < moved or old_spots.is_empty()) else old_spots
		var xf := _pile_xf(src, i, scale_fn.call(items[i]))
		if _visible(xf.origin):
			xs.append(xf)
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])


func _update_brood() -> void:
	_pile(_egg_mm, _spots.eggs, sim.eggs, 400, func(_e): return 1.0)
	_pile(_larva_mm, _spots.larvae, sim.larvae, 300, func(l): return 0.35 + l.p * 0.65, _spots.larvae_old, _moved)
	_pile(_pupa_mm, _spots.pupae, sim.pupae, 300, func(p): return p.get("s", 1.0))
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
		_queen_mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, sin(_t * 0.15) * 0.3).scaled(Vector3.ONE * 2.3), qp))
		_queen_mm.set_instance_color(0, AntModel.tint(Color(0.075, 0.05, 0.038)))

func _up_at(c: Vector3i) -> Vector3:
	var u := Vector3.ZERO
	for d in DIRS:
		var n := c + d
		if not nest.inside(n) or not nest.is_open(n):
			u -= Vector3(d)
	return u.normalized() if u.length_squared() > 0.01 else Vector3.UP


func _pose(from: Vector3, to: Vector3, t: float, up: Vector3, scale := 1.0) -> Transform3D:
	var p := from.lerp(to, clampf(t, 0.0, 1.0))
	var f := to - from
	if f.length_squared() < 0.0001:
		f = Vector3.RIGHT
	f = f.normalized()
	var y := (up - f * f.dot(up))
	if y.length_squared() < 0.01:
		y = Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT
	y = y.normalized()
	var z := f.cross(y)
	return Transform3D(Basis(f, y, z).scaled(Vector3.ONE * scale), p - up * 0.4)


## Eases the drawn ant along its voxel path: position, heading and body tilt follow the hops
## smoothly instead of snapping at each cell; distance walked drives the leg gait (radians) and
## `mv` (0..1) tells the shader how much the legs should be stepping. If `face` is set the ant
## turns to look at that point (meeting a nestmate, tending brood).
func _smooth(v: Dictionary, path_pos: Vector3, up: Vector3, delta: float, scale: float) -> Transform3D:
	if not v.has("vp") or v.vp.distance_squared_to(path_pos) > 36.0:
		v.vp = path_pos
		v.vf = Vector3.RIGHT
		v.vu = up
		v.gait = randf() * TAU
		v.mv = 0.0
	var np: Vector3 = v.vp.lerp(path_pos, 1.0 - exp(-12.0 * delta))
	var step: Vector3 = np - v.vp
	var moving := step.length() > 0.12 * delta
	if moving:
		var want := step.normalized()
		v.vf = (v.vf as Vector3).slerp(want, minf(1.0, 9.0 * delta)) if (v.vf as Vector3).dot(want) > -0.99 else want
		v.gait = fmod(v.gait + step.length() * 6.0 / scale, TAU * 64.0)
	var face: Vector3 = v.get("face", Vector3.INF)
	if face != Vector3.INF and not moving:
		var to := face - np
		to -= v.vu * to.dot(v.vu)
		if to.length_squared() > 0.01:
			var want := to.normalized()
			v.vf = (v.vf as Vector3).slerp(want, minf(1.0, 5.0 * delta)) if (v.vf as Vector3).dot(want) > -0.99 else want
	v.mv = lerpf(v.mv, 1.0 if moving else 0.0, minf(1.0, 8.0 * delta))
	v.vu = (v.vu as Vector3).lerp(up, minf(1.0, 6.0 * delta)).normalized()
	v.vp = np
	var f: Vector3 = v.vf
	var y: Vector3 = v.vu - f * f.dot(v.vu)
	if y.length_squared() < 0.01:
		y = Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT
	y = y.normalized()
	f = (f - y * f.dot(y)).normalized()
	return Transform3D(Basis(f, y, f.cross(y)).scaled(Vector3.ONE * scale), np - v.vu * 0.4)


func _move_mate(m: Dictionary, n: Vector3i) -> void:
	m.prev = m.cell
	m.cell = n
	m.from = m.to
	m.to = Vector3(n)
	m.up = _up_at(n)


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


## What an ant does when it reaches the place it was heading for.
func _arrive(m: Dictionary) -> void:
	match m.role:
		"nurse":
			m.rest = randi_range(30, 140)
			m.wander = randi_range(2, 6)              # then a short shuffle around the brood pile
		"attend":
			m.rest = randi_range(80, 260)             # the queen's retinue stays close to her
			m.wander = randi_range(1, 3)
		"idle":
			m.rest = randi_range(60, 240)
			if randf() < 0.25:
				m.goal = _random_room()
		"traffic":
			# a forager passing through: in at the entrance (crop full of honeydew), down to a chamber
			m.rest = randi_range(2, 10)
			if m.goal == -1:
				m.fed = randf() < 0.7
				m.goal = _random_room()
			else:
				m.goal = -1
		"carry":
			if _moved >= sim.larvae.size():
				m.role = "nurse"
				m.carry = false
				m.goal = _brood_room(_larva_group)
			elif not m.carry:
				m.carry = true                          # picks up a larva from the old pile
				m.goal = _brood_room(_larva_group)
				m.rest = 3
			else:
				m.carry = false                         # sets it down in the new chamber
				_moved += maxi(1, sim.larvae.size() / 10)
				m.goal = _brood_room(_larva_prev)
				m.rest = 3


func _step_mate(m: Dictionary) -> void:
	var c: Vector3i = m.cell
	if m.rest > 0:
		m.rest -= 1
		m.from = m.to
		return
	if m.wander > 0:
		m.wander -= 1
		var opts: Array[Vector3i] = []
		for d in DIRS:
			if c + d != m.prev and nest.walkable(c + d):
				opts.append(c + d)
		if not opts.is_empty():
			_move_mate(m, opts[randi() % opts.size()])
		return
	var field: Dictionary = _fields.get(m.goal, {})
	var here: int = field.get(c, -1)
	if here == 0:
		_arrive(m)
		return
	if here < 0:
		# off the map (new tunnel, stale field): pick another goal and drift
		m.goal = _random_room()
		m.wander = 3
		return
	var best: Array[Vector3i] = []
	var floaty: Array[Vector3i] = []
	for d in DIRS:
		var n := c + d
		if field.get(n, 1 << 20) < here:
			if nest.walkable(n):
				best.append(n)
			else:
				floaty.append(n)
	if best.is_empty():
		best = floaty
	if not best.is_empty():
		_move_mate(m, best[randi() % best.size()])


func _sample_size() -> float:
	return sim.workers[randi() % sim.workers.size()].size if not sim.workers.is_empty() else 1.0


func _spawn_mate(role: String, inside: int) -> bool:
	if _spots.all.is_empty() or _rooms.is_empty():
		return false
	var sp: Vector3 = _spots.all[randi() % _spots.all.size()]
	var c := Vector3i(roundi(sp.x), roundi(sp.y + 0.45), roundi(sp.z))
	if not nest.walkable(c):
		return false
	var goal := _random_room()
	match role:
		"nurse": goal = _brood_room(_larva_group)
		"attend": goal = _queen_room()
		"traffic": goal = -1
	_mates.append({"cell": c, "prev": c, "from": Vector3(c), "to": Vector3(c), "t": 1.0, "rest": randi_range(0, 30),
		"up": _up_at(c), "callow": randf() < float(sim.callow) / maxf(1.0, inside), "role": role, "goal": goal,
		"wander": 0, "carry": false, "size": _sample_size(), "act": ACT_WALK, "act_left": 0.0, "cool": randf() * 4.0,
		"anim": randf() * 100.0, "fed": false})
	return true


# ---------------------------------------------------------------- activities

const ACT_WALK := 0
const ACT_REST := 1
const ACT_DIG := 2
const ACT_ANTENNATE := 3
const ACT_GROOM := 4
const ACT_LAY := 5
const ACT_FEED := 6
const ACT_TEND := 7
const ACT_CARRY := 8
const STILL_ACTS := [ACT_ANTENNATE, ACT_GROOM, ACT_FEED]    # the ant stops walking while doing these


func _begin(m: Dictionary, act: int, secs: float, face := Vector3.INF) -> void:
	m.act = act
	m.act_left = secs
	m.face = face


## Two ants that bump into each other stop and drum antennae; a forager back from outside
## regurgitates a droplet of honeydew to the other (trophallaxis).
func _meetings() -> void:
	var by_cell := {}
	for m in _mates:
		by_cell[m.cell] = m
	for m in _mates:
		if m.cool > 0.0 or m.act in STILL_ACTS or m.carry:
			continue
		for d in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
				Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
			var o = by_cell.get(m.cell + d)
			if o == null or is_same(o, m) or o.cool > 0.0 or o.act in STILL_ACTS or o.carry:
				continue
			if m.fed or o.fed:
				var secs := randf_range(3.0, 6.0)
				_begin(m, ACT_FEED, secs, o.vp if o.has("vp") else o.to)
				_begin(o, ACT_FEED, secs, m.vp if m.has("vp") else m.to)
				m.fed = false
				o.fed = false
			else:
				var secs := randf_range(1.0, 2.2)
				_begin(m, ACT_ANTENNATE, secs, o.vp if o.has("vp") else o.to)
				_begin(o, ACT_ANTENNATE, secs, m.vp if m.has("vp") else m.to)
			m.cool = randf_range(5.0, 10.0)
			o.cool = randf_range(5.0, 10.0)
			break


## Choose what a mate is doing this frame from its role and situation.
func _update_activity(m: Dictionary, delta: float) -> void:
	m.cool = maxf(0.0, m.cool - delta)
	if m.act_left > 0.0:
		m.act_left -= delta
		if m.act_left > 0.0:
			return
	m.face = Vector3.INF
	if m.carry:
		m.act = ACT_CARRY
	elif m.rest > 0:
		if m.role == "nurse" and _rooms.size() > 0:
			# nurses at the brood pile lick and feed the larvae
			m.act = ACT_TEND
			m.face = _nearest_spot(m.to, _spots.larvae)
		elif m.role == "attend":
			m.act = ACT_TEND
			m.face = _spots.queen
		elif randf() < 0.04 * delta:
			_begin(m, ACT_GROOM, randf_range(2.0, 4.5))     # resting ants groom every so often
		else:
			m.act = ACT_REST
	else:
		m.act = ACT_WALK


func _nearest_spot(p: Vector3, spots: Array) -> Vector3:
	var best := Vector3.INF
	var bd := 9.0
	for s in spots:
		var d := p.distance_squared_to(s)
		if d < bd:
			bd = d
			best = s
	return best


func _custom(v: Dictionary, act: int) -> Color:
	return Color(v.get("gait", 0.0), act, fmod(v.get("anim", 0.0), 600.0), v.get("mv", 0.0))


func _update_ants(delta: float) -> void:
	var inside: int = sim.workers.size() - sim.out_count
	var want := clampi(inside - nest.diggers.size(), 0, 250)
	var nurses_want := mini(sim.nurses + sim.callow, want / 2 + 1)
	var attend_want := mini(3, want / 6) if sim.queen.alive else 0
	var traffic_want := mini(mini(sim.out_count, 4), want)
	while _mates.size() < want:
		var counts := {"nurse": 0, "attend": 0, "traffic": 0}
		for m in _mates:
			var r: String = "nurse" if m.role == "carry" else m.role
			if counts.has(r):
				counts[r] += 1
		var role := "idle"
		if counts.attend < attend_want:
			role = "attend"
		elif counts.nurse < nurses_want:
			role = "nurse"
		elif counts.traffic < traffic_want:
			role = "traffic"
		if not _spawn_mate(role, inside):
			break
	while _mates.size() > want:
		_mates.pop_back()
	# while larvae are being moved between chambers, a few nurses do the carrying
	if _moved < sim.larvae.size():
		var carriers := 0
		for m in _mates:
			if m.role == "carry":
				carriers += 1
		for m in _mates:
			if carriers >= 4:
				break
			if m.role == "nurse" or (m.role == "idle" and carriers == 0):
				m.role = "carry"
				m.goal = _brood_room(_larva_prev)
				m.rest = 0
				m.wander = 0
				m.act_left = 0.0
				carriers += 1
		if carriers == 0:
			_moved = 1 << 20

	var running := speed > 0
	var cells_per_sec := clampf(60.0 * speed / nest.STEP_EVERY, 0.0, 25.0) if running else 0.0
	var dt := delta * cells_per_sec
	var adt := delta if running else 0.0          # body animation freezes with the clock
	if running:
		_meetings()
	var body: Color = AntModel.tint(sim.sp["body_color"])
	var young: Color = AntModel.tint(sim.sp["callow_color"])
	var xs := []
	var cols := []
	var cus := []
	var larva_loads := []
	var pellet_loads := []
	for m in _mates:
		m.anim += adt
		_update_activity(m, adt)
		if not m.act in STILL_ACTS:
			m.t += dt
			while m.t >= 1.0 and dt > 0.0:
				m.t -= 1.0
				_step_mate(m)
		var tr := _smooth(m, (m.from as Vector3).lerp(m.to, clampf(m.t, 0.0, 1.0)), m.up, delta, m.size)
		if _visible(tr.origin):
			xs.append(tr)
			cols.append(young if m.callow else body)
			cus.append(_custom(m, m.act))
			if m.carry:
				larva_loads.append(tr * CARRY_OFFSET)

	# diggers come from the simulation; we smooth their hops and show them biting at the dig face
	var seen := {}
	for d in nest.diggers:
		var id: int = d.id
		seen[id] = true
		var c := Vector3(d.cell)
		var v: Dictionary = _dig_vis.get(id, {})
		if v.is_empty():
			v = {"from": c, "to": c, "t": 1.0, "up": _up_at(d.cell), "still": 0.0, "anim": randf() * 100.0}
			_dig_vis[id] = v
		if v.to != c:
			v.from = v.from.lerp(v.to, clampf(v.t, 0.0, 1.0))
			v.to = c
			v.t = 0.0
			v.up = _up_at(d.cell)
			v.still = 0.0
		else:
			v.still += adt
		v.t += dt
		v.anim += adt
		if not v.has("size"):
			v.size = _sample_size()
		var tr := _smooth(v, (v.from as Vector3).lerp(v.to, clampf(v.t, 0.0, 1.0)), v.up, delta, v.size)
		if _visible(tr.origin):
			var act := ACT_CARRY if d.carry else (ACT_DIG if v.still > 0.25 else ACT_WALK)
			xs.append(tr)
			cols.append(body)
			cus.append(_custom(v, act))
			if d.carry:
				pellet_loads.append(tr * CARRY_OFFSET)
	for id in _dig_vis.keys():
		if not seen.has(id):
			_dig_vis.erase(id)

	_ant_mm.instance_count = xs.size()
	for i in xs.size():
		_ant_mm.set_instance_transform(i, xs[i])
		_ant_mm.set_instance_color(i, cols[i])
		_ant_mm.set_instance_custom_data(i, cus[i])
	_fill(_carry_larva_mm, larva_loads)
	_fill(_carry_pellet_mm, pellet_loads)

	# the queen: rests among her retinue, curls her gaster to lay whenever a new egg appears
	_queen_anim += adt
	if sim.eggs.size() > _last_eggs and running:
		_queen_lay = 2.5
	_last_eggs = sim.eggs.size()
	_queen_lay = maxf(0.0, _queen_lay - adt)
	if _queen_mm.instance_count > 0:
		_queen_mm.set_instance_custom_data(0, Color(0.0, ACT_LAY if _queen_lay > 0.0 else ACT_REST, fmod(_queen_anim, 600.0), 0.0))


func debug_summary() -> String:
	var roles := {}
	var acts := {}
	var carrying := 0
	for m in _mates:
		roles[m.role] = roles.get(m.role, 0) + 1
		acts[m.act] = acts.get(m.act, 0) + 1
		if m.carry:
			carrying += 1
	return "%s %s  roles %s  acts %s  carrying %d  larvae moved %d/%d (%s→%s)  rooms %d  fields %d" % [sim.clock_text(),
		"air>nest" if sim.climate.air > sim.climate.nest + 0.5 else "air<nest", roles, acts, carrying,
		mini(_moved, sim.larvae.size()), sim.larvae.size(), _larva_prev, _larva_group, _rooms.size(), _fields.size()]


func _fill(mm: MultiMesh, xs: Array) -> void:
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])


# ---------------------------------------------------------------- input

func _unhandled_input(e: InputEvent) -> void:
	if not active:
		return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			zoom_by(1.0 / 1.18)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			zoom_by(1.18)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed and e.double_click:
				_focus_at(e.position)
			_pan = e.pressed and e.shift_pressed
			_rot = e.pressed and not e.shift_pressed
		elif e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE:
			_pan = e.pressed
			_rot = false
	elif e is InputEventMouseMotion:
		if _rot:
			yaw_t -= e.relative.x * 0.007
			pitch_t = clampf(pitch_t + e.relative.y * 0.006, -0.2, 1.45)
		elif _pan:
			var right := _cam.global_transform.basis.x
			var up := _cam.global_transform.basis.y
			target_t += (-right * e.relative.x + up * e.relative.y) * dist_t * 0.0016
	elif e is InputEventKey and e.pressed and e.keycode == KEY_HOME:
		reset_view()
