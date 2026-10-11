extends Node3D
## 3D view of the underground nest: the soil block sliced open by a camera-facing cut plane,
## with diggers from the simulation, resting nestmates, brood piles and the queen.

const Ant := preload("res://scripts/sim/ant.gd")
const Mesher := preload("res://scripts/view/nest_mesher.gd")
const AntModel := preload("res://scripts/view/ant_model3d.gd")
const Props := preload("res://scripts/view/mesh_kit.gd")
const CLUMP := 24                  # eggs stick together in packets of about this many
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
var _ev_n := -1                    # last simulation life-cycle event seen
var _anims: Array = []             # life-cycle moments being acted out
var _fx_egg_mm: MultiMesh
var _fx_larva_mm: MultiMesh
var _fx_silk_mm: MultiMesh
var _fx_cocoon_mm: MultiMesh
var _carry_cocoon_mm: MultiMesh
var _carry_shell_mm: MultiMesh
var _fx_soil_mm: MultiMesh
var _fx_drop_mm: MultiMesh
var _bits_mm: MultiMesh            # pieces of prey laid on the larvae for them to feed on
var _queen_xf := Transform3D()
var _queen_turn := 0.0
var _queen_turn_t := 0.0
var _queen_act := -1
var _egg_spots: Array = []         # floor beside the queen (not under her) where the egg packets lie


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

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 38
	_cam.far = 3000
	_cam.environment = env           # each 3D view has its own lighting mood
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
	var larva_mesh: Mesh = Props.larva()
	var cocoon_mesh: Mesh = Props.cocoon()
	var larva_mat := _mat_vc(0.3)
	var cocoon_mat := _mat_vc(0.85)
	_larva_mm = _multimesh(larva_mesh, larva_mat, false)
	_pupa_mm = _multimesh(cocoon_mesh, cocoon_mat, true)
	_pellet_mm = _multimesh(_ellipsoid(0.42, 0.34), _mat_simple(Color(0.42, 0.3, 0.2), 0.95), false)
	_carry_larva_mm = _multimesh(larva_mesh, larva_mat, false)
	_carry_pellet_mm = _multimesh(_ellipsoid(0.8, 0.65), _mat_simple(Color(0.45, 0.32, 0.2), 0.95), false)
	_fx_egg_mm = _multimesh(_ellipsoid(0.32, 0.22), _mat_simple(Color(0.96, 0.94, 0.86), 0.25), false)
	_fx_larva_mm = _multimesh(larva_mesh, larva_mat, false)
	var silk := StandardMaterial3D.new()
	silk.albedo_color = Color(0.97, 0.95, 0.9)
	silk.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	silk.vertex_color_use_as_albedo = true
	silk.roughness = 0.9
	_fx_silk_mm = _multimesh(_ellipsoid(1.35, 0.62), silk, true)
	_fx_cocoon_mm = _multimesh(cocoon_mesh, cocoon_mat, true)
	_carry_cocoon_mm = _multimesh(cocoon_mesh, cocoon_mat, false)
	_carry_shell_mm = _multimesh(cocoon_mesh, cocoon_mat, false)
	_fx_soil_mm = _multimesh(_ellipsoid(0.42, 0.34), _mat_simple(Color(0.42, 0.3, 0.2), 0.95), false)
	var dew := _mat_simple(Color(0.85, 0.55, 0.15, 0.8), 0.1)
	dew.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fx_drop_mm = _multimesh(_ellipsoid(0.16, 0.14), dew, false)
	_bits_mm = _multimesh(_ellipsoid(0.38, 0.26), _mat_simple(Color(0.45, 0.3, 0.18), 0.7), false)
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

func _mat_vc(rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	return m


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
		_ev_n = sim.event_seq          # what happened while we were away is not replayed


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
	_poll_events()
	_step_anims(delta if speed > 0 else 0.0)
	var sig := [sim.eggs.size(), sim.larvae.size(), sim.pupae.size(), nest.excavated / 2, snappedf(_plane_w, 0.5),
		snappedf(_plane_n.x, 0.05), _spot_timer > 1.45, _moved, _larva_group, _pending("egg"), _pending("pupate"), int(sim.protein * 1.5), sim.tick / 600]
	if sig != _brood_sig:
		_brood_sig = sig
		_update_brood()
	_queen_pose()
	_update_ants(delta)
	_draw_anims()


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


func _hash(i: int, s: int) -> float:
	var x := sin(i * 12.9898 + s * 78.233) * 43758.5453
	return x - floor(x)


func _pile_xf(spots: Array, i: int, scale: float) -> Transform3D:
	var sp: Vector3 = spots[i % spots.size()]
	var layer := i / spots.size()
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
		col_fn := Callable()) -> void:
	var n := mini(items.size(), max_n)
	if spots.is_empty():
		n = 0
	var xs := []
	var cs := []
	for i in n:
		# items not yet carried over stay in the old pile
		var src: Array = spots if (i < moved or old_spots.is_empty()) else old_spots
		var xf := _pile_xf(src, i, scale_fn.call(items[i]))
		if _visible(xf.origin):
			xs.append(xf)
			cs.append(col_fn.call(items[i]) if col_fn.is_valid() else Color.WHITE)
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		if mm.use_colors:
			mm.set_instance_color(i, cs[i])


func _update_brood() -> void:
	var exs := []
	if not _spots.eggs.is_empty():
		for i in mini(400, maxi(0, sim.eggs.size() - _pending("egg"))):
			var xf := _egg_xf(i)
			if _visible(xf.origin):
				exs.append(xf)
	_fill(_egg_mm, exs)
	# young larvae are tiny; they grow about tenfold in mass before pupating
	_pile(_larva_mm, _spots.larvae, sim.larvae, 300, func(l): return 0.28 + l.p * 0.8, _spots.larvae_old, _moved)
	var bits := []
	if not sim.larvae.is_empty() and not _spots.larvae.is_empty():
		for k in mini(16, int(sim.protein * 1.5)):
			var base := _pile_xf(_spots.larvae, k * 3 + 1, 1.0).origin
			var xf := Transform3D(Basis(Vector3.UP, _hash(k, 9) * TAU), base + Vector3(_hash(k, 7) - 0.5, 0.1, _hash(k, 8) - 0.5))
			if _visible(xf.origin):
				bits.append(xf)
	_fill(_bits_mm, bits)
	_pile(_pupa_mm, _spots.pupae, sim.pupae.slice(0, maxi(0, sim.pupae.size() - _pending("pupate"))), 300, func(p): return p.get("s", 1.0),
		[], 1 << 20, func(p): return Color.WHITE.lerp(Color(0.72, 0.72, 0.72), smoothstep(0.75, 1.0, p.p)))
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
		_queen_xf = Transform3D(Basis(Vector3.UP, sin(_t * 0.15) * 0.3 + _queen_turn).scaled(Vector3.ONE * 2.3), qp)
		_queen_mm.set_instance_transform(0, _queen_xf)
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
	if m.has("deliver"):
		m.deliver.done = true                       # cocoon set down, or empty shell taken out
		m.erase("deliver")
		m.carry = false
		m.item = ""
		if m.goal == -1:
			m.goal = _brood_room(_larva_group)
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
	var callow := randf() < float(sim.callow) / maxf(1.0, inside)
	var born: int = sim.tick - int(randf() * sim.TPD * float(sim.sp["callow_days"])) if callow else -1000000000
	_mates.append({"cell": c, "prev": c, "from": Vector3(c), "to": Vector3(c), "t": 1.0, "rest": randi_range(0, 30),
		"up": _up_at(c), "born": born, "role": role, "goal": goal,
		"wander": 0, "carry": false, "item": "", "size": _sample_size(), "act": ACT_WALK, "act_left": 0.0, "cool": randf() * 4.0,
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
const ACT_EMERGE := 12          # a callow just out of its cocoon, legs still folded
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
			# nurses at the brood pile lick the larvae and regurgitate food to them
			m.act = ACT_FEED if fmod(m.anim + m.cool * 3.0, 11.0) < 4.0 and not sim.larvae.is_empty() else ACT_TEND
			m.face = _nearest_spot(m.to, _spots.larvae)
		elif m.role == "attend":
			m.act = ACT_TEND
			m.face = _spots.queen
			if fmod(m.anim, 16.0) > 9.0 and not sim.eggs.is_empty() and not _spots.eggs.is_empty():
				m.face = _egg_xf(0).origin            # licking the egg packet clean
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
	# a worker still climbing out of its cocoon is drawn by its eclosion, not as a nestmate yet
	var want := clampi(inside - nest.diggers.size() - _pending("eclose"), 0, 250)
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
		var drop: Dictionary = _mates.pop_back()
		if drop.has("deliver"):
			drop.deliver.done = true
	# while larvae are being moved between chambers, a few nurses do the carrying
	if _moved < sim.larvae.size():
		var carriers := 0
		for m in _mates:
			if m.role == "carry":
				carriers += 1
		for m in _mates:
			if carriers >= 4:
				break
			if m.has("script") or m.has("deliver"):
				continue
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
	var cocoon_loads := []
	var shell_loads := []
	var drops := []
	var pellet_loads := []
	for m in _mates:
		m.anim += adt
		var path: Vector3
		if m.has("script"):
			# hired for a life-cycle moment: walks where the animation needs it
			m.act = m.script.act
			m.face = m.script.face
			path = m.script.pos
		else:
			_update_activity(m, adt)
			if not m.act in STILL_ACTS:
				m.t += dt * (0.25 if sim.tick < int(m.get("weak_until", 0)) else 1.0)
				while m.t >= 1.0 and dt > 0.0:
					m.t -= 1.0
					_step_mate(m)
			path = (m.from as Vector3).lerp(m.to, clampf(m.t, 0.0, 1.0))
		var tr := _smooth(m, path, m.up, delta, m.size)
		m.xf = tr
		if m.act == ACT_FEED and _visible(tr.origin):
			drops.append(tr * Transform3D(Basis.from_scale(Vector3.ONE * (0.8 + 0.3 * sin(m.anim * 3.0))), MOUTH + Vector3(0.2, 0, 0)))
		if _visible(tr.origin):
			xs.append(tr)
			cols.append(_mate_color(m, body, young))
			cus.append(_custom(m, m.act))
			if m.carry:
				if m.get("item", "") == "cocoon":
					cocoon_loads.append(tr * CARRY_OFFSET)
				elif m.get("item", "") == "shell":
					shell_loads.append(tr * CARRY_OFFSET * Transform3D(Basis.from_scale(Vector3(0.85, 0.6, 1.1)), Vector3.ZERO))
				else:
					larva_loads.append(tr * CARRY_OFFSET)
	_emerging(xs, cols, cus, young)

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
	_fill(_carry_cocoon_mm, cocoon_loads)
	_fill(_carry_shell_mm, shell_loads)
	_fill(_fx_drop_mm, drops)
	_fill(_carry_pellet_mm, pellet_loads)

	# the queen: rests among her retinue, curls her gaster to lay whenever a new egg appears
	_queen_anim += adt
	if sim.eggs.size() > _last_eggs and running:
		_queen_lay = 2.5
	_last_eggs = sim.eggs.size()
	_queen_lay = maxf(0.0, _queen_lay - adt)
	if _queen_mm.instance_count > 0:
		var qa := _queen_act if _queen_act >= 0 else (ACT_LAY if _queen_lay > 0.0 else ACT_REST)
		_queen_mm.set_instance_custom_data(0, Color(0.0, qa, fmod(_queen_anim, 600.0), 0.0))


# ---------------------------------------------------------------- life-cycle moments
# The simulation reports each egg laid, larva pupating and worker eclosing (sim.events). At watchable
# speeds the nest view acts them out: the queen lays and an attendant (or, while founding, the queen
# herself) carries the egg to the pile; a nurse covers a spinning larva and carries the new cocoon
# up to the pupa chamber; nurses bite open a cocoon and a pale callow unfolds and stands up.

const MOUTH := Vector3(1.2, 0.32, 0.0)          # mandible tip in the ant model, before scaling
const GASTER_TIP := Vector3(-1.85, 0.25, 0.0)


func _anim_k() -> float:
	return 1.0 / clampf(sqrt(speed), 1.0, 2.3)


func _poll_events() -> void:
	if _ev_n < 0:
		_ev_n = sim.event_seq
	var watch := speed > 0.0 and speed <= 5.0
	for e in sim.events:
		if e.n <= _ev_n or not watch:
			continue
		var busy := 0
		for a in _anims:
			if a.k == e.k:
				busy += 1
		match e.k:
			"egg":
				if busy < 2:
					_start_egg()
			"pupate":
				if busy < 2:
					_start_pupate(e.s)
			"eclose":
				if busy < 3:
					_start_eclose(e.s)
	_ev_n = sim.event_seq


func _pending(kind: String) -> int:
	var n := 0
	for a in _anims:
		if a.k == kind and not a.get("done", false):
			n += 1
	return n


## Nearby nestmates free to help; they must be close, since they walk straight to the spot.
func _helpers(p: Vector3, n: int, max_d := 6.0) -> Array:
	var cands := []
	for m in _mates:
		if m.has("script") or m.has("deliver") or m.carry or m.role == "carry" or m.role == "traffic":
			continue
		var d := Vector3(m.cell).distance_to(p)
		if d < max_d:
			cands.append([d, m])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	for c in cands.slice(0, n):
		out.append(c[1])
	return out


## Take a nestmate off its usual routine and walk it to `goal` (a floor point).
func _hire(m: Dictionary, goal: Vector3, face: Vector3, act: int) -> void:
	var from: Vector3 = (m.vp as Vector3) + (m.vu as Vector3) * 0.4 if m.has("vp") else Vector3(m.to)
	m.script = {"pos": from, "goal": goal + Vector3(0, 0.45, 0), "face": face, "act": act}


func _release(m: Dictionary) -> void:
	if not m.has("script"):
		return
	var p: Vector3 = m.script.pos
	m.erase("script")
	var c := Vector3i(roundi(p.x), roundi(p.y), roundi(p.z))
	if nest.walkable(c):
		m.cell = c
		m.prev = c
		m.from = Vector3(c)
		m.to = Vector3(c)
		m.t = 1.0
		m.up = _up_at(c)
	m.rest = randi_range(20, 80)


func _beside(p: Vector3, m: Dictionary, dist := 1.6) -> Vector3:
	var d: Vector3 = Vector3(m.cell) - p
	d.y = 0.0
	if d.length_squared() < 0.01:
		d = Vector3(randf() - 0.5, 0, randf() - 0.5)
	return p + d.normalized() * dist


func _start_egg() -> void:
	if not sim.queen.alive or _spots.queen == Vector3.ZERO:
		return
	var idx := maxi(0, sim.eggs.size() - 1 - _pending("egg"))
	var pile: Vector3 = _egg_xf(idx).origin if not _spots.eggs.is_empty() else _spots.queen
	var a := {"k": "egg", "t": 0.0, "d": 5.0 * _anim_k(), "pile": pile, "helper": null}
	var hs := _helpers(_spots.queen, 1, 7.0)
	if not hs.is_empty():
		a.helper = hs[0]
		_hire(a.helper, _beside(_queen_xf * GASTER_TIP, a.helper, 1.2), _queen_xf * GASTER_TIP, ACT_TEND)
	_anims.append(a)


func _start_pupate(s: float) -> void:
	if _spots.larvae.is_empty():
		return
	var p: Vector3 = _pile_xf(_spots.larvae, sim.larvae.size() + _pending("pupate"), 1.0).origin
	var a := {"k": "pupate", "t": 0.0, "d": 7.0 * _anim_k(), "p": p, "s": s, "helper": null, "carried": false}
	var hs := _helpers(p, 1)
	if not hs.is_empty():
		a.helper = hs[0]
		_hire(a.helper, _beside(p, a.helper), p, ACT_TEND)
	_anims.append(a)


func _start_eclose(s: float) -> void:
	if _spots.pupae.is_empty():
		return
	var shown: int = sim.pupae.size() - _pending("pupate")
	var p: Vector3 = _pile_xf(_spots.pupae, maxi(0, shown + _pending("eclose")), s).origin
	var a := {"k": "eclose", "t": 0.0, "d": 13.0 * _anim_k(), "p": p, "s": s, "helpers": [], "yaw": randf() * TAU,
		"queen": false}
	for m in _helpers(p, 2):
		a.helpers.append(m)
		_hire(m, _beside(p, m, 1.6 + 0.3 * a.helpers.size()), p, ACT_TEND)
	if a.helpers.is_empty() and sim.queen.alive and _spots.queen != Vector3.ZERO and _spots.queen.distance_to(p) < 8.0:
		a.queen = true           # a founding queen opens her first cocoons herself
	_anims.append(a)


## Where the parts of an eclosion are at progress u: the cocoon's head end, how far the callow has
## been pulled out, and the callow's own transform.
func _eclose_parts(a: Dictionary, u: float) -> Dictionary:
	var s: float = a.s
	var b := Basis(Vector3.UP, a.yaw)
	var bx: Vector3 = b.x
	var head: Vector3 = a.p + Vector3(0, 0.3, 0) + bx * 1.3 * s
	var pull := clampf((u - 0.5) / 0.22, 0.0, 1.0)
	var roll := lerpf(1.3, 0.0, clampf((u - 0.85) / 0.13, 0.0, 1.0))
	var origin: Vector3 = a.p + Vector3(0, 0.15 + 0.25 * roll, 0) + bx * (pull * 2.5 * s - 0.4 * s)
	var callow := Transform3D((b * Basis(Vector3.RIGHT, roll)).scaled(Vector3.ONE * s), origin)
	return {"bx": bx, "head": head, "pull": pull, "callow": callow, "side": b.z}


func _step_anims(adt: float) -> void:
	_queen_act = -1
	_queen_turn_t = 0.0
	var walk := 3.5 / _anim_k()                   # voxels per second for hired helpers
	var fresh := []
	for m in _mates:
		if m.has("script"):
			m.script.pos = (m.script.pos as Vector3).move_toward(m.script.goal, walk * adt)
	for a in _anims:
		a.t += adt
		var u: float = a.t / a.d
		match a.k:
			"egg":
				var h = a.helper
				if h != null and not _mates.has(h):
					a.helper = null
					h = null
				if u < 0.3:
					_queen_act = ACT_LAY
				elif h == null:
					# a founding queen turns round and places the egg herself
					_queen_turn_t = 2.6 if u < 0.8 else 0.0
					_queen_act = ACT_TEND
				elif u < 0.4:
					h.script.act = ACT_TEND
				elif u < 0.85:
					h.script.goal = a.pile + Vector3(0, 0.45, 0) + (Vector3(h.cell) - a.pile).normalized() * 1.0
					h.script.face = a.pile
					h.script.act = ACT_CARRY
				else:
					h.script.act = ACT_TEND
				if u >= 1.0:
					a.done = true
					if h != null:
						_release(h)
			"pupate":
				var h = a.helper
				if h != null and not _mates.has(h):
					a.helper = null
					h = null
				if u >= 0.6 and not a.carried and h != null:
					# the nurse lifts the fresh cocoon and carries it up to the pupa chamber
					a.carried = true
					_release(h)
					h.deliver = a
					h.carry = true
					h.item = "cocoon"
					h.goal = _upper[0] if not _upper.is_empty() else _queen_room()
					h.rest = 0
					h.wander = 0
				if a.carried:
					if h == null or not h.has("deliver") or a.t > a.d + 25.0:
						a.done = true
						if h != null and h.has("deliver"):
							h.erase("deliver")
							h.carry = false
							h.item = ""
				elif u >= 1.0:
					a.done = true
					if h != null:
						_release(h)
			"eclose":
				var hs: Array = a.helpers.filter(func(m): return _mates.has(m))
				a.helpers = hs
				var ep := _eclose_parts(a, u)
				var callow_head: Vector3 = (ep.callow as Transform3D) * MOUTH
				for i in hs.size():
					var m: Dictionary = hs[i]
					var lift := Vector3(0, 0.45, 0)
					if i == 0:
						# at the head end: bites through the silk, then backs away pulling the callow out
						m.script.goal = (ep.head as Vector3) + (ep.bx as Vector3) * (1.3 * a.s + ep.pull * 2.5 * a.s) + lift - Vector3(0, 0.3, 0)
						m.script.face = ep.head if u < 0.5 else callow_head
					else:
						# alongside: helps with the silk, then peels the pupal skin off the callow's body
						var along: float = -0.2 + ep.pull * 1.6
						m.script.goal = a.p + (ep.side as Vector3) * (1.7 * a.s) + (ep.bx as Vector3) * along * a.s + lift
						m.script.face = (ep.callow as Transform3D).origin if u > 0.5 else ep.head
					if u < 0.18:
						m.script.act = ACT_TEND           # checking the cocoon
					elif u < 0.72:
						m.script.act = ACT_DIG            # biting the silk open / pulling
					elif u < 0.86 or i > 0:
						m.script.act = ACT_TEND           # peeling and licking the newcomer clean
					else:
						m.script.act = ACT_FEED           # the first meal, mouth to mouth
				if a.queen and sim.queen.alive:
					var d: Vector3 = ep.head - _spots.queen
					_queen_turn_t = atan2(-d.z, d.x)
					_queen_act = ACT_DIG if (u > 0.18 and u < 0.72) else ACT_TEND
				if u >= 1.0:
					a.done = true
					for m in hs:
						_release(m)
					var o: Vector3 = (ep.callow as Transform3D).origin
					_add_mate(Vector3i(roundi(o.x), roundi(a.p.y + 0.45), roundi(o.z)), "nurse", sim.tick, a.s)
					var newborn: Dictionary = _mates[-1]
					newborn.weak_until = sim.tick + int(sim.TPD * 0.25)   # unsteady for the first hours
					newborn.rest = randi_range(40, 90)
					if not hs.is_empty():
						# a helper carries the empty cocoon and the shed skin out to the refuse pile
						var h: Dictionary = hs[0]
						var shell := {"k": "shell", "t": 0.0, "d": 1e9, "helper": h}
						h.deliver = shell
						h.carry = true
						h.item = "shell"
						h.goal = -1
						h.rest = 0
						h.wander = 0
						fresh.append(shell)
			"shell":
				var h = a.helper
				if not _mates.has(h) or not h.has("deliver") or a.t > 45.0:
					a.done = true
					if _mates.has(h) and h.has("deliver"):
						h.erase("deliver")
						h.carry = false
						h.item = ""
	_anims = _anims.filter(func(a): return not a.get("done", false))
	_anims.append_array(fresh)
	_queen_turn = lerp_angle(_queen_turn, _queen_turn_t, minf(1.0, 3.0 * adt))


## Ants still being born are drawn here: pulled head first out of the cocoon still wrapped in the
## pupal skin, legs folded; once the skin is peeled off it rolls upright and unfolds, then joins _mates.
func _emerging(xs: Array, cols: Array, cus: Array, young: Color) -> void:
	for a in _anims:
		if a.k != "eclose":
			continue
		var u: float = a.t / a.d
		if u < 0.5:
			continue
		var tr: Transform3D = _eclose_parts(a, u).callow
		if _visible(tr.origin):
			xs.append(tr)
			cols.append(young.lightened(0.3))
			cus.append(Color(0.0, ACT_EMERGE, maxf(0.0, (u - 0.82) * a.d), 0.0))


func _draw_anims() -> void:
	var eggs := []
	var larvae := []
	var silk := []
	var cocoons := []
	var soil := []
	for a in _anims:
		var u: float = a.t / a.d
		match a.k:
			"egg":
				var tip: Vector3 = _queen_xf * GASTER_TIP
				var p := tip
				var h = a.helper
				var sc := clampf(0.25 + u / 0.3 * 0.75, 0.25, 1.0)
				if h == null:
					var mouth: Vector3 = _queen_xf * MOUTH
					if u > 0.45:
						p = tip.lerp(mouth, clampf((u - 0.45) / 0.1, 0.0, 1.0))
					if u > 0.55:
						p = mouth.lerp(a.pile, clampf((u - 0.55) / 0.25, 0.0, 1.0))
				elif u > 0.3 and h.has("xf"):
					var mouth: Vector3 = h.xf * MOUTH
					p = tip.lerp(mouth, clampf((u - 0.3) / 0.1, 0.0, 1.0))
					if u > 0.85:
						p = mouth.lerp(a.pile, clampf((u - 0.85) / 0.1, 0.0, 1.0))
				if _visible(p):
					eggs.append(Transform3D(Basis.from_scale(Vector3.ONE * sc), p))
			"pupate":
				if a.carried:
					continue                       # drawn in the nurse's mandibles
				var s: float = a.s
				if _visible(a.p):
					var lb := Basis(Vector3.UP, a.t * 0.3).scaled(Vector3.ONE * s)
					if u < 0.62:
						# Lasius larvae need a covering of soil particles to spin against
						var shown := int(clampf(u / 0.25, 0.0, 1.0) * 8.0)
						var gone := clampf((u - 0.52) / 0.1, 0.0, 1.0)
						for g in shown:
							var ga: float = g * 0.785
							var gp: Vector3 = a.p + Vector3(cos(ga) * 0.7 * s, 0.35 + 0.35 * float(g % 2), sin(ga) * 0.7 * s)
							soil.append(Transform3D(Basis.from_scale(Vector3.ONE * (1.0 - gone)), gp))
					if u < 0.6:
						larvae.append(Transform3D(lb.scaled(Vector3(1.0, 1.0 - 0.15 * sin(a.t * 6.0), 1.0)), a.p + Vector3(0, 0.3, 0)))
						var cover := clampf(u / 0.6, 0.0, 1.0)
						silk.append([Transform3D(lb.scaled(Vector3.ONE * (0.55 + 0.5 * cover)), a.p + Vector3(0, 0.3, 0)), 0.15 + 0.7 * cover])
					else:
						cocoons.append(Transform3D(lb, a.p + Vector3(0, 0.3, 0)))
			"eclose":
				if not _visible(a.p):
					continue
				var ep := _eclose_parts(a, u)
				var wig := sin(a.t * 9.0) * 0.16 * clampf((u - 0.06) / 0.1, 0.0, 1.0) if u < 0.55 else 0.0
				var b := Basis(Vector3.UP, a.yaw) * Basis(Vector3.RIGHT, wig)
				var open := clampf((u - 0.45) / 0.1, 0.0, 1.0)
				# once empty the shell slumps a little; the silk is torn at the head end
				var sc: Vector3 = Vector3(1.0 - 0.08 * open, 1.0 - 0.22 * clampf((u - 0.7) / 0.2, 0.0, 1.0), 1.0) * a.s
				var tone := lerpf(1.0, 0.72, clampf(u / 0.2, 0.0, 1.0)) if u < 0.6 else lerpf(0.72, 0.95, clampf((u - 0.6) / 0.15, 0.0, 1.0))
				cocoons.append([Transform3D(b.scaled(sc), a.p + Vector3(0, 0.3, 0)), Color(tone, tone, tone)])
				var peel := clampf((u - 0.72) / 0.13, 0.0, 1.0)
				if u > 0.5 and peel < 1.0:
					var skin := (ep.callow as Transform3D) * Transform3D(Basis.from_scale(Vector3(1.15, 0.75, 0.8)), Vector3(-0.15, 0.4, 0))
					silk.append([skin, 0.5 * (1.0 - peel)])
				if peel > 0.0:
					# the shed pupal skin, a crumpled pale scrap beside the cocoon
					silk.append([Transform3D(Basis.from_scale(Vector3(0.32, 0.18, 0.28) * a.s * peel), a.p + (ep.side as Vector3) * 0.9 * a.s + Vector3(0, 0.2, 0)), 0.85])
	_fill(_fx_egg_mm, eggs)
	_fill(_fx_larva_mm, larvae)
	_fx_cocoon_mm.instance_count = cocoons.size()
	for i in cocoons.size():
		var c = cocoons[i]
		_fx_cocoon_mm.set_instance_transform(i, c[0] if c is Array else c)
		_fx_cocoon_mm.set_instance_color(i, c[1] if c is Array else Color.WHITE)
	_fill(_fx_soil_mm, soil)
	_fx_silk_mm.instance_count = silk.size()
	for i in silk.size():
		_fx_silk_mm.set_instance_transform(i, silk[i][0])
		_fx_silk_mm.set_instance_color(i, Color(1, 1, 1, silk[i][1]))


func _add_mate(c: Vector3i, role: String, born: int, size: float) -> void:
	var goal := _random_room()
	match role:
		"nurse": goal = _brood_room(_larva_group)
		"attend": goal = _queen_room()
		"traffic": goal = -1
	_mates.append({"cell": c, "prev": c, "from": Vector3(c), "to": Vector3(c), "t": 1.0, "rest": randi_range(0, 30),
		"up": _up_at(c), "born": born, "role": role, "goal": goal,
		"wander": 0, "carry": false, "item": "", "size": size, "act": ACT_WALK, "act_left": 0.0, "cool": randf() * 4.0,
		"anim": randf() * 100.0, "fed": false})


## Callows are pale and darken over their first days as the cuticle hardens.
func _mate_color(m: Dictionary, body: Color, young: Color) -> Color:
	var days: float = float(sim.tick - int(m.get("born", -1000000000))) / sim.TPD
	return young.lerp(body, clampf(days / float(sim.sp["callow_days"]), 0.0, 1.0))


func debug_summary() -> String:
	var roles := {}
	var acts := {}
	var carrying := 0
	for m in _mates:
		roles[m.role] = roles.get(m.role, 0) + 1
		acts[m.act] = acts.get(m.act, 0) + 1
		if m.carry:
			carrying += 1
	return "cam %s d%.1f yaw%.2f cut%.1f | %s %s  roles %s  acts %s  carrying %d  larvae moved %d/%d (%s→%s)  rooms %d  fields %d" % [target, cam_dist, yaw, cut_offset, sim.clock_text(),
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
