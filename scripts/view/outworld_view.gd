extends Node3D
## The outworld box in 3D: the same simulation and the same scenery layout as the top-down view,
## seen through an orbit camera. Foragers use the same 3D Lasius niger model and body animation
## as the nest view. 1 unit = 1.5 mm (a nest voxel) = 3 px of the simulation's outworld.

const Ant := preload("res://scripts/sim/ant.gd")
const AntModel := preload("res://scripts/view/ant_model3d.gd")
const Props := preload("res://scripts/view/mesh_kit.gd")

const U := 1.0 / 3.0                 # simulation px -> units
const ANT_SCALE := 1.1
const WALL_H := 42.0
const CARRY_OFFSET := Transform3D(Basis(Vector3(0.55, 0, 0), Vector3(0, 0.55, 0), Vector3(0, 0, 0.55)), Vector3(1.35, 0.45, 0.0))
const SIDE_PANEL_PX := 364.0         # the HUD's side panel covers the right of the window

var sim
var world                            # the top-down view: shared textures, pheromone image, scenery and tool
var active := false
var speed := 1.0

var yaw := 0.0
var pitch := 0.95
var cam_dist := 420.0
var target := Vector3(200, 0, 125)
var yaw_t := 0.0
var pitch_t := 0.95
var dist_t := 420.0
var target_t := Vector3(200, 0, 125)

var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _ground_mat: ShaderMaterial
var _prop_mat: StandardMaterial3D
var _ant_meshes := {}
var _lod := ""
var _ant_mm: MultiMesh
var _corpse_mm: MultiMesh
var _prey_mm: MultiMesh
var _spider_mm: MultiMesh
var _spider_vis := {}
var _rain_mm: MultiMesh
var _rain: Array = []
var _ring: MeshInstance3D
var _rock_root: Node3D
var _rocks_n := -1
var _food_root: Node3D
var _foods := {}                     # food seed -> {"node", "sig"}
var _items_timer := 0.0
var _mound := -1.0
var _mound_r := 4.0
var _nest_xz := Vector2.ZERO
var _rot := false
var _pan := false
var _painting := false
var _last_paint := Vector2(-999, -999)
var hover := Vector3.INF
var _t := 0.0
var _wet := 0.0
var _plant_mat: ShaderMaterial      # host plants and fallen leaves move in the air
var _litter_mat: ShaderMaterial
var _grass_mat: ShaderMaterial
var _aphid_meshes: Array = []
var _aphid_wings: Mesh
var _dew_mm: MultiMesh              # honeydew droplets an aphid is handing to a milking ant
var _splash_mm: MultiMesh
var _splash: Array = []             # [position, age]


func setup(s, w) -> void:
	sim = s
	world = w
	_nest_xz = sim.nest_pos * U
	target = Vector3(sim.WORLD.x * U * 0.5, 0, sim.WORLD.y * U * 0.5)

	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.05, 0.04, 0.035)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.6, 0.55, 0.5)
	_env.ambient_light_energy = 0.55
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_intensity = 0.2

	_cam = Camera3D.new()
	_cam.fov = 38
	_cam.near = 0.5
	_cam.far = 4000
	_cam.environment = _env
	add_child(_cam)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.5
	_sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(28), 0)
	add_child(_sun)

	_prop_mat = StandardMaterial3D.new()
	_prop_mat.vertex_color_use_as_albedo = true
	_prop_mat.vertex_color_is_srgb = true
	_prop_mat.roughness = 0.8
	_prop_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_plant_mat = _sway_mat(true, Color(0.05, 0.07, 0.02), 0.7)
	_litter_mat = _sway_mat(true, Color(0.08, 0.05, 0.02), 0.8)
	_grass_mat = _sway_mat(false, Color(0.05, 0.07, 0.02), 0.65)
	_aphid_meshes = [Props.aphid(0), Props.aphid(1), Props.aphid(2)]
	_aphid_wings = Props.aphid_wings()
	_build_ground()
	_build_box()
	_build_scenery()
	_rock_root = Node3D.new()
	add_child(_rock_root)
	_food_root = Node3D.new()
	add_child(_food_root)

	var ant_mat := ShaderMaterial.new()
	ant_mat.shader = load("res://shaders/ant.gdshader")
	ant_mat.set_shader_parameter("limb_gain", AntModel.WORKER_LIMBS)
	_ant_meshes = {"hi": AntModel.make(), "lo": AntModel.make(0.0, false, false)}
	_ant_mm = _multimesh(_ant_meshes.lo, ant_mat, true, true)
	_corpse_mm = _multimesh(_ant_meshes.lo, ant_mat, true, true)
	_prey_mm = _multimesh(_blob_mesh(Vector3(0.75, 0.5, 0.6)), _mat(Color(0.5, 0.33, 0.18), 0.7), false)
	var sp_mat := ShaderMaterial.new()
	sp_mat.shader = load("res://shaders/spider.gdshader")
	_spider_mm = _multimesh(Props.spider(), sp_mat, false, true)

	var drop := BoxMesh.new()
	drop.size = Vector3(0.12, 3.2, 0.12)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.8, 0.86, 0.95, 0.35)
	_rain_mm = _multimesh(drop, rm, false)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.75
	ring.outer_radius = 1.0
	ring.rings = 16
	ring.ring_segments = 4
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(0.85, 0.9, 1.0)
	_splash_mm = _multimesh(ring, sm, true)
	_dew_mm = _multimesh(_blob_mesh(Vector3(0.15, 0.14, 0.15)), _honey_mat(), false)
	for i in 320:
		_rain.append(Vector3(randf() * 400.0, randf() * 60.0, randf() * 250.0))

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 48
	_ring.mesh = torus
	var ringm := StandardMaterial3D.new()
	ringm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ringm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ringm.albedo_color = Color(1, 0.95, 0.85, 0.7)
	ringm.no_depth_test = true
	_ring.material_override = ringm
	_ring.visible = false
	add_child(_ring)

	reset_view()
	snap_camera()
	visible = false


# ---------------------------------------------------------------- ground shape (matches the shader)

func ground_h(x: float, z: float) -> float:
	var h := 0.8 * sin(x * 0.021 + 1.3) * cos(z * 0.027 + 0.4) + 0.45 * sin(x * 0.057 + z * 0.043 + 2.0)
	var d := Vector2(x - _nest_xz.x, z - _nest_xz.y).length()
	var k := (d - _mound_r) / (_mound_r * 0.6)
	var mh := maxf(_mound, 0.0)
	h += mh * exp(-k * k) + mh * 0.5 * (1.0 - smoothstep(0.0, _mound_r, d))
	h -= 1.6 * (1.0 - smoothstep(0.6, 1.9, d))
	return h


func ground_n(x: float, z: float) -> Vector3:
	var e := 0.6
	return Vector3(ground_h(x - e, z) - ground_h(x + e, z), 2.0 * e, ground_h(x, z - e) - ground_h(x, z + e)).normalized()


func _on_ground(px: Vector2, lift := 0.0) -> Vector3:
	var p := px * U
	return Vector3(p.x, ground_h(p.x, p.y) + lift, p.y)


# ---------------------------------------------------------------- building

func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _blob_mesh(r: Vector3) -> Mesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 8
	s.rings = 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(s, 0, Transform3D(Basis.from_scale(r), Vector3.ZERO))
	return st.commit()


func _multimesh(mesh: Mesh, mat: Material, colors: bool, custom := false) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)
	return mm


func _build_ground() -> void:
	var w: float = sim.WORLD.x * U
	var d: float = sim.WORLD.y * U
	var nx := 200
	var nz := 125
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in nz + 1:
		for i in nx + 1:
			verts.append(Vector3(w * i / nx, 0, d * j / nz))
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			idx.append_array([a, a + 1, a + nx + 1, a + 1, a + nx + 2, a + nx + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(0, -4, 0), Vector3(w, 10, d))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var detail := NoiseTexture2D.new()
	detail.width = 256
	detail.height = 256
	detail.seamless = true
	var dn := FastNoiseLite.new()
	dn.noise_type = FastNoiseLite.TYPE_CELLULAR
	dn.frequency = 0.06
	detail.noise = dn
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = load("res://shaders/outworld_ground.gdshader")
	_ground_mat.set_shader_parameter("soil_tex", world._soil.texture)
	_ground_mat.set_shader_parameter("damp_tex", world._damp.texture)
	_ground_mat.set_shader_parameter("grain_tex", world._grain.texture)
	_ground_mat.set_shader_parameter("detail", detail)
	_ground_mat.set_shader_parameter("pher_tex", world._pher_tex)
	_ground_mat.set_shader_parameter("world_size", Vector2(w, d))
	_ground_mat.set_shader_parameter("nest_xz", _nest_xz)
	mi.material_override = _ground_mat
	add_child(mi)
	_update_mound()


## The crater of excavated pellets grows with the nest below.
func _update_mound() -> void:
	var m := clampf(sqrt(float(sim.nest.excavated)) / 22.0, 0.25, 2.2)
	if absf(m - _mound) < 0.05:
		return
	_mound = m
	_mound_r = 3.0 + m * 2.2
	_ground_mat.set_shader_parameter("mound_h", _mound)
	_ground_mat.set_shader_parameter("mound_r", _mound_r)


func _build_box() -> void:
	var w: float = sim.WORLD.x * U
	var d: float = sim.WORLD.y * U
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.85, 0.93, 1.0, 0.06)
	glass.roughness = 0.03
	glass.metallic_specular = 1.0
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wood := _mat(Color(0.3, 0.19, 0.11), 0.6)
	var trim := _mat(Color(0.12, 0.1, 0.09), 0.5)
	var yh := WALL_H * 0.5 - 2.0
	_box(Vector3(w, WALL_H, 0.5), Vector3(w * 0.5, yh, -0.25), glass)
	_box(Vector3(w, WALL_H, 0.5), Vector3(w * 0.5, yh, d + 0.25), glass)
	_box(Vector3(0.5, WALL_H, d), Vector3(-0.25, yh, d * 0.5), glass)
	_box(Vector3(0.5, WALL_H, d), Vector3(w + 0.25, yh, d * 0.5), glass)
	# soil layer seen through the glass, the base tray and a dark rim along the top edge
	_build_soil_edge(w, d)
	_box(Vector3(w + 6, 4.0, d + 6), Vector3(w * 0.5, -8.4, d * 0.5), wood)
	for e in [[Vector3(w + 3, 1.2, 1.5), Vector3(w * 0.5, WALL_H - 2.0, -0.6)], [Vector3(w + 3, 1.2, 1.5), Vector3(w * 0.5, WALL_H - 2.0, d + 0.6)],
			[Vector3(1.5, 1.2, d), Vector3(-0.6, WALL_H - 2.0, d * 0.5)], [Vector3(1.5, 1.2, d), Vector3(w + 0.6, WALL_H - 2.0, d * 0.5)]]:
		_box(e[0], e[1], trim)
	# the keeper's table
	var table := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	table.mesh = pm
	table.material_override = _mat(Color(0.16, 0.11, 0.075), 0.55)
	table.position = Vector3(w * 0.5, -10.4, d * 0.5)
	add_child(table)


## The soil layer seen through the glass: a skirt from the uneven ground surface down to the tray.
func _build_soil_edge(w: float, d: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bottom := -6.4
	var edges := [[Vector3(0, 0, 0), Vector3(w, 0, 0)], [Vector3(w, 0, 0), Vector3(w, 0, d)],
		[Vector3(w, 0, d), Vector3(0, 0, d)], [Vector3(0, 0, d), Vector3(0, 0, 0)]]
	for e in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var n := 80
		for i in n:
			var p0 := a.lerp(b, float(i) / n)
			var p1 := a.lerp(b, float(i + 1) / n)
			var t0 := Vector3(p0.x, ground_h(p0.x, p0.z), p0.z)
			var t1 := Vector3(p1.x, ground_h(p1.x, p1.z), p1.z)
			var b0 := Vector3(p0.x, bottom, p0.z)
			var b1 := Vector3(p1.x, bottom, p1.z)
			for v in [t0, t1, b0, t1, b1, b0, t0, b0, t1, t1, b0, b1]:
				var depth := clampf((v.y - bottom) / 7.0, 0.0, 1.0)
				st.set_color(Color(0.17, 0.11, 0.07).lerp(Color(0.33, 0.23, 0.14), depth))
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vc_mat(0.95, true)
	add_child(mi)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


## Litter, pebbles, moss, grass and the crater/midden grains, from the top-down view's layout.
func _build_scenery() -> void:
	for l in world._litter:
		var mi := MeshInstance3D.new()
		var ang: float = l.a
		if l.twig:
			mi.mesh = Props.twig(l.l * 2.0 * U, int(l.p.x * 7 + l.p.y))
		else:
			mi.mesh = Props.leaf(l.l * U, l.w * U, l.c, l.curl)
		mi.material_override = _litter_mat if not l.twig else _prop_mat
		mi.position = _on_ground(l.p, 0.05)
		mi.basis = Basis(Vector3.UP, -ang)
		add_child(mi)
	var stone := _multimesh(_blob_mesh(Vector3.ONE), _vc_mat(0.9, false, false), true)
	stone.instance_count = world._pebbles.size()
	for i in world._pebbles.size():
		var p: Dictionary = world._pebbles[i]
		var r: Vector2 = p.r * U
		var b := Basis(Vector3.UP, -p.a).scaled(Vector3(r.x, minf(r.x, r.y) * 0.65, r.y))
		stone.set_instance_transform(i, Transform3D(b, _on_ground(p.p, 0.0)))
		stone.set_instance_color(i, (p.c as Color).darkened(0.3).srgb_to_linear())
	var moss := _multimesh(_blob_mesh(Vector3.ONE), _vc_mat(1.0, false, false), true)
	var blobs := []
	for m in world._moss:
		blobs.append_array(m)
	moss.instance_count = blobs.size()
	for i in blobs.size():
		var b: Array = blobs[i]
		var r: float = b[1] * U
		moss.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, r * 0.55, r)), _on_ground(b[0], 0.05)))
		moss.set_instance_color(i, Color(0.22, 0.33, 0.12).lerp(Color(0.36, 0.48, 0.18), b[2]).srgb_to_linear())
	var grass := _multimesh(Props.blade(), _grass_mat, true)
	var blades := []
	var gr := RandomNumberGenerator.new()
	gr.seed = 777
	for t in world._tufts:
		var n := gr.randi_range(9, 16)
		for k in n:
			var yaw := gr.randf() * TAU
			var h := gr.randf_range(6.0, 17.0) * (1.25 if k < 3 else 1.0)
			var lean := gr.randf_range(0.05, 0.5)
			var at: Vector2 = t.p + Vector2(gr.randfn(0.0, 2.2), gr.randfn(0.0, 2.2))
			var dry := gr.randf() < 0.14
			var col := Color(0.24, 0.42, 0.13).lerp(Color(0.5, 0.64, 0.26), gr.randf())
			if dry:
				col = Color(0.56, 0.5, 0.32).lerp(Color(0.68, 0.6, 0.4), gr.randf())
			blades.append([at, yaw, h, lean, col])
	grass.instance_count = blades.size()
	for i in blades.size():
		var b: Array = blades[i]
		var basis := (Basis(Vector3.UP, b[1]) * Basis(Vector3.BACK, -b[3])).scaled(Vector3(b[2] * 0.8, b[2], 3.2))
		grass.set_instance_transform(i, Transform3D(basis, _on_ground(b[0], -0.15)))
		grass.set_instance_color(i, (b[4] as Color).srgb_to_linear())
	var grains := _multimesh(_blob_mesh(Vector3.ONE), _vc_mat(0.95, false, false), true)
	var bits := []
	bits.append_array(world._crater)
	bits.append_array(world._midden_bits)
	grains.instance_count = bits.size()
	for i in bits.size():
		var g: Dictionary = bits[i]
		var r: float = g.r * U
		grains.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, r * 0.7, r)), _on_ground(g.p, 0.0)))
		grains.set_instance_color(i, (g.c as Color).darkened(0.2).srgb_to_linear())


func _sway_mat(srgb: bool, back: Color, rough: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sway.gdshader")
	m.set_shader_parameter("srgb_colors", srgb)
	m.set_shader_parameter("backlight", Vector3(back.r, back.g, back.b))
	m.set_shader_parameter("roughness_v", rough)
	return m


func _vc_mat(rough: float, two_sided := false, srgb := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = srgb
	m.roughness = rough
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _sync_rocks() -> void:
	if sim.rocks.size() == _rocks_n:
		return
	_rocks_n = sim.rocks.size()
	for c in _rock_root.get_children():
		c.queue_free()
	for rk in sim.rocks:
		var outline := PackedVector2Array()
		for p in rk.poly:
			outline.append((p - rk.pos) * U)
		var mi := MeshInstance3D.new()
		mi.mesh = Props.rock(outline, rk.r * U, rk.tone, int(rk.pos.x * 13 + rk.pos.y))
		mi.material_override = _vc_mat(0.85)
		mi.position = _on_ground(rk.pos, 0.0)
		_rock_root.add_child(mi)


func _sync_foods() -> void:
	var seen := {}
	for f in sim.foods:
		var key: int = f.seed
		seen[key] = true
		var left: float = clampf(f.amt / f.cap, 0.0, 1.0)
		var sig := "%s:%d:%s" % [f.kind, int(left * 10.0), f.rotten]
		var e: Dictionary = _foods.get(key, {})
		if not e.is_empty() and e.sig == sig:
			continue
		if not e.is_empty():
			e.node.queue_free()
		var node := _make_food(f, left)
		_food_root.add_child(node)
		var low := []
		if f.kind == "aphids":
			for s in Props.aphid_spots(f.seed):
				if s[1] != 2 and (s[0] as Transform3D).origin.y < 10.0:
					low.append(s[0])
		_foods[key] = {"node": node, "sig": sig, "low": low}
	for key in _foods.keys():
		if not seen.has(key):
			_foods[key].node.queue_free()
			_foods.erase(key)


func _make_food(f: Dictionary, left: float) -> Node3D:
	var root := Node3D.new()
	root.position = _on_ground(f.pos, 0.0)
	root.rotation.y = -f.ang
	match f.kind:
		"aphids":
			var plant := MeshInstance3D.new()
			plant.mesh = Props.aphid_plant(f.seed)
			plant.material_override = _plant_mat
			root.add_child(plant)
			var spots: Array = Props.aphid_spots(f.seed)
			for kind in 3:
				var xs := []
				for s in spots:
					if s[1] == kind:
						xs.append(s[0])
				if xs.is_empty():
					continue
				for layer in ([_aphid_meshes[kind], _aphid_wings] if kind == 2 else [_aphid_meshes[kind]]):
					var mm := MultiMesh.new()
					mm.transform_format = MultiMesh.TRANSFORM_3D
					mm.mesh = layer
					mm.instance_count = xs.size()
					for i in xs.size():
						mm.set_instance_transform(i, xs[i])
					var mi := MultiMeshInstance3D.new()
					mi.multimesh = mm
					mi.material_override = _prop_mat if layer != _aphid_wings else _wing_mat()
					root.add_child(mi)
			# honeydew waiting on the aphids: as many drops as the colony has to give right now
			var rng := RandomNumberGenerator.new()
			rng.seed = f.seed
			for i in int(round(left * 8.0)):
				var s: Array = spots[rng.randi() % spots.size()]
				var drop := MeshInstance3D.new()
				drop.mesh = _blob_mesh(Vector3(0.24, 0.22, 0.24))
				drop.material_override = _honey_mat()
				drop.position = (s[0] as Transform3D) * Vector3(-0.95, 0.4, 0)
				root.add_child(drop)
		"honey":
			var r := (3.0 + 7.0 * sqrt(left)) * U
			var drop := MeshInstance3D.new()
			drop.mesh = _blob_mesh(Vector3(r * 1.1, r * 0.42, r))
			drop.material_override = _honey_mat()
			root.add_child(drop)
		"cricket":
			var body := Node3D.new()
			body.rotation.x = 0.12        # lying a little on one side
			root.add_child(body)
			if Props.asset("cricket_head") != null:
				# the Blender carcass comes in pieces: the abdomen shrinks and legs go as the ants cut it up
				var mat: StandardMaterial3D = _prop_mat
				if f.rotten:
					mat = _prop_mat.duplicate()
					mat.albedo_color = Color(0.72, 0.78, 0.66)
				var abd := maxf(0.35, left)
				var pieces := [["cricket_head", true], ["cricket_abdomen", true], ["cricket_hindlegs", left > 0.3], ["cricket_legs", left > 0.6]]
				for pc in pieces:
					if not pc[1]:
						continue
					var mi := MeshInstance3D.new()
					mi.mesh = Props.asset(pc[0])
					mi.material_override = mat
					if pc[0] == "cricket_abdomen":
						var pivot := Vector3(0.4, 1.6, 0)
						mi.scale = Vector3.ONE * abd
						mi.position = pivot * (1.0 - abd)
					body.add_child(mi)
				if int(round((1.0 - left) * 9.0)) > 0:
					var w := MeshInstance3D.new()
					w.mesh = Props.cricket_wounds(left, f.seed)
					w.material_override = _prop_mat
					body.add_child(w)
			else:
				var c := MeshInstance3D.new()
				c.mesh = Props.cricket(left, f.rotten, f.seed)
				c.material_override = _prop_mat
				body.add_child(c)
		"fly":
			var b := MeshInstance3D.new()
			b.mesh = Props.fly(left)
			b.material_override = _prop_mat
			root.add_child(b)
			var wings := MeshInstance3D.new()
			wings.mesh = Props.fly_wings()
			wings.material_override = _wing_mat()
			wings.scale = Vector3.ONE * (0.6 + 0.4 * left)
			root.add_child(wings)
	return root


var _honey: StandardMaterial3D
var _wings: StandardMaterial3D


func _wing_mat() -> StandardMaterial3D:
	if _wings == null:
		_wings = StandardMaterial3D.new()
		_wings.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wings.albedo_color = Color(0.85, 0.9, 1.0, 0.3)
		_wings.roughness = 0.1
		_wings.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _wings


func _honey_mat() -> StandardMaterial3D:
	if _honey == null:
		_honey = StandardMaterial3D.new()
		_honey.albedo_color = Color(0.85, 0.5, 0.1, 0.82)
		_honey.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_honey.roughness = 0.08
		_honey.metallic_specular = 0.9
		_honey.rim_enabled = true
		_honey.rim = 0.4
	return _honey


# ---------------------------------------------------------------- per frame

func set_active(on: bool) -> void:
	active = on
	visible = on
	_cam.current = on
	if on:
		_rocks_n = -1


func refresh(delta: float) -> void:
	if not active:
		return
	_t += delta
	_ease_camera(delta)
	_update_camera()
	_items_timer -= delta
	if _items_timer <= 0.0:
		_items_timer = 0.4
		_sync_rocks()
		_sync_foods()
		_update_mound()
	_ground_mat.set_shader_parameter("pher_on", 1.0 if world.show_pheromones else 0.0)
	var raining: bool = sim.climate.raining()
	_wet = move_toward(_wet, 1.0 if raining else 0.0, delta * 0.3 * maxf(speed, 0.5))
	_ground_mat.set_shader_parameter("wet", _wet)
	_grass_mat.set_shader_parameter("wind", 1.3 + 1.8 * _wet)
	_plant_mat.set_shader_parameter("wind", 0.45 + 0.7 * _wet)
	_litter_mat.set_shader_parameter("wind", 0.35 + 0.6 * _wet)
	_light()
	var lod := "hi" if cam_dist < 80.0 else "lo"
	if lod != _lod:
		_lod = lod
		_ant_mm.mesh = _ant_meshes[lod]
	_update_ants(delta)
	_update_corpses()
	_update_spider(delta)
	_update_rain(delta, raining)
	_update_ring()


func _light() -> void:
	var sky: Color = world._sky_color()
	var day: float = sim.daylight()
	_sun.light_color = sky
	_sun.light_energy = 0.25 + 0.72 * day       # a little moonlight at night
	_env.ambient_light_color = sky
	_env.ambient_light_energy = 0.5 + 0.1 * day
	_sun.directional_shadow_max_distance = maxf(150.0, cam_dist * 2.5)


func _update_ants(delta: float) -> void:
	var kp := 1.0 - exp(-20.0 * delta)
	var ka := 1.0 - exp(-10.0 * delta)
	var adt := delta if speed > 0 else 0.0
	# in daylight the ants need their true (linear) colour or the sun bleaches them grey
	var body: Color = AntModel.tint(sim.sp["body_color"]).srgb_to_linear()
	var young: Color = AntModel.tint(sim.sp["callow_color"]).srgb_to_linear()
	var xs := []
	var cols := []
	var cus := []
	var loads := []
	var carried := []
	var dews := []
	for a in sim.outside:
		if a.state == Ant.IN_NEST or a.dead:
			continue
		if a.vpos.x == INF or a.vpos.distance_squared_to(a.pos) > 400.0:
			a.vpos = a.pos
			a.vang = a.ang
			a.anim = randf() * 50.0
		var step: Vector2 = a.pos - a.vpos
		a.vpos += step * kp
		var moving := step.length_squared() > 0.01
		if moving:
			a.vang = lerp_angle(a.vang, step.angle(), ka)
		elif a.busy > 0:
			a.vang = lerp_angle(a.vang, a.ang, ka)
		a.vmv = lerpf(a.vmv, 1.0 if moving else 0.0, minf(1.0, 10.0 * delta))
		a.anim += adt
		var p: Vector2 = a.vpos * U
		var up := ground_n(p.x, p.y)
		var f := Vector3(cos(a.vang), 0, sin(a.vang))
		f = (f - up * f.dot(up)).normalized()
		var s: float = ANT_SCALE * a.size
		var tr := Transform3D(Basis(f, up, f.cross(up)).scaled(Vector3.ONE * s), Vector3(p.x, ground_h(p.x, p.y), p.y))
		var act: int = a.act if a.busy > 0 else 0
		var pose := _feeding_pose(a, act, s) if act in [2, 9, 10] else {}
		a.vfeed = move_toward(a.vfeed, 1.0 if not pose.is_empty() else 0.0, delta * 2.5)
		if not pose.is_empty():
			a.vpose = pose
		if a.vfeed > 0.0 and a.vpose is Dictionary and not (a.vpose as Dictionary).is_empty():
			tr = _blend_pose(tr, a.vpose, a.vfeed, s)
			if a.vfeed > 0.95 and act == 9:
				dews.append(a.vpose.dew)
		if a.carry == Ant.SUGAR:
			act += 100                      # a crop full of honeydew swells the gaster
		xs.append(tr)
		cols.append(body.lerp(young, clampf(1.0 - a.age / 6.0, 0.0, 1.0)))
		cus.append(Color(fmod(a.phase, TAU * 64.0), act, fmod(a.anim, 600.0), a.vmv))
		if a.carry == Ant.PROTEIN:
			loads.append(tr * CARRY_OFFSET)
		elif a.carry == Ant.CORPSE:
			carried.append(tr * Transform3D(Basis(Vector3.RIGHT, PI).scaled(Vector3.ONE * 0.9), Vector3(2.3, 0.95, 0)))
	_ant_mm.instance_count = xs.size()
	for i in xs.size():
		_ant_mm.set_instance_transform(i, xs[i])
		_ant_mm.set_instance_color(i, cols[i])
		_ant_mm.set_instance_custom_data(i, cus[i])
	_dew_mm.instance_count = dews.size()
	for i in dews.size():
		var pulse := 0.6 + 0.4 * sin(_t * 3.0 + i)
		_dew_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * pulse), dews[i]))
	_prey_mm.instance_count = loads.size()
	for i in loads.size():
		_prey_mm.set_instance_transform(i, loads[i])
	_carried = carried


var _carried: Array = []


## Where an ant handling food really stands: the simulation only knows it is within reach of the
## food's centre, so the view places it on the food itself. {} if no food is close.
func _feeding_pose(a, act: int, s: float) -> Dictionary:
	var best = null
	var bd := 1e9
	for f in sim.foods:
		var d: float = f.pos.distance_squared_to(a.pos)
		if d < bd:
			bd = d
			best = f
	if best == null or bd > pow(best.r + 14.0, 2.0):
		return {}
	var f: Dictionary = best
	var c := _on_ground(f.pos)
	var away := Vector3(a.pos.x - f.pos.x, 0, a.pos.y - f.pos.y)
	if away.length_squared() < 0.01:
		away = Vector3(1, 0, 0)
	away = away.normalized()
	var left: float = clampf(f.amt / f.cap, 0.0, 1.0)
	match f.kind:
		"aphids":
			if act != 9:
				return {}
			# climb the stem to one of the low aphids and stroke its abdomen for the drop
			var e: Dictionary = _foods.get(f.seed, {})
			if e.is_empty() or e.low.is_empty():
				return {}
			var root: Transform3D = e.node.transform
			var ax: Transform3D = root * (e.low[a.id % e.low.size()] as Transform3D)
			var out_dir: Vector3 = ax.basis.y.normalized()
			var stem: Vector3 = ax.origin - out_dir * (Props.STEM_R + 0.35)
			var on := stem + out_dir * (Props.STEM_R + 0.1) - Vector3(0, 1.9 * s, 0)
			var base := Vector3(on.x, ground_h(on.x, on.z), on.z) + out_dir * 0.4
			return {"climb": true, "base": base, "pos": on, "fwd": Vector3.UP, "up": out_dir,
				"dew": ax * Vector3(-0.95, 0.4, 0)}
		"honey":
			if act != 10:
				return {}
			var r := (3.0 + 7.0 * sqrt(left)) * U * 1.1
			var p := c + away * (r + 0.85 * s)
			return {"pos": Vector3(p.x, ground_h(p.x, p.z), p.z), "fwd": -away, "up": Vector3.UP}
		"cricket", "fly":
			if act != 2:
				return {}
			# around the carcass outline (an ellipse along its body), head in, cutting
			var ang: float = f.ang
			var rot := Basis(Vector3.UP, -ang)
			var dl: Vector3 = rot.inverse() * away
			var ea := 6.4 if f.kind == "cricket" else 2.2
			var eb := 2.4 if f.kind == "cricket" else 1.3
			var th := atan2(dl.z / eb, dl.x / ea)
			var n := rot * Vector3(cos(th) / ea, 0, sin(th) / eb).normalized()
			var p := c + rot * Vector3(ea * cos(th), 0, eb * sin(th)) + n * 1.1 * s
			return {"pos": Vector3(p.x, ground_h(p.x, p.z), p.z), "fwd": -n, "up": Vector3.UP}
	return {}


func _pose_xf(fwd: Vector3, up: Vector3, pos: Vector3, s: float) -> Transform3D:
	var f := fwd - up * fwd.dot(up)
	if f.length_squared() < 1e-4:
		f = up.cross(Vector3.RIGHT) if absf(up.x) < 0.9 else up.cross(Vector3.BACK)
	f = f.normalized()
	return Transform3D(Basis(f, up, f.cross(up)).scaled(Vector3.ONE * s), pos)


## Blend from the walking pose toward the feeding pose; climbing goes to the stem foot first.
func _blend_pose(ground: Transform3D, pose: Dictionary, k: float, s: float) -> Transform3D:
	var fe := _pose_xf(pose.fwd, pose.up, pose.pos, s)
	if not pose.get("climb", false):
		var b: Basis = ground.basis.orthonormalized().slerp(fe.basis.orthonormalized(), k)
		return Transform3D(b.scaled(Vector3.ONE * s), ground.origin.lerp(fe.origin, k))
	var foot := _pose_xf(pose.base - ground.origin if k < 0.5 else pose.pos - pose.base, Vector3.UP, pose.base, s)
	if k < 0.5:
		var u := k * 2.0
		var b: Basis = ground.basis.orthonormalized().slerp(foot.basis.orthonormalized(), minf(1.0, u * 2.0))
		return Transform3D(b.scaled(Vector3.ONE * s), ground.origin.lerp(pose.base, u))
	var u2 := (k - 0.5) * 2.0
	var b2: Basis = foot.basis.orthonormalized().slerp(fe.basis.orthonormalized(), minf(1.0, u2 * 3.0))
	return Transform3D(b2.scaled(Vector3.ONE * s), (pose.base as Vector3).lerp(pose.pos, u2))


## Dead workers on the refuse pile (and wherever the spider dropped them), plus those being carried.
func _update_corpses() -> void:
	var n: int = mini(sim.corpses.size(), 300)
	_corpse_mm.instance_count = n + _carried.size()
	var dead := Color(0.2, 0.16, 0.13)
	for i in n:
		var c: Dictionary = sim.corpses[sim.corpses.size() - n + i]
		var f := Vector3(cos(c.ang), 0, sin(c.ang))
		var b := Basis(f, Vector3.DOWN, f.cross(Vector3.DOWN)).scaled(Vector3.ONE * ANT_SCALE * 0.95)
		_corpse_mm.set_instance_transform(i, Transform3D(b, _on_ground(c.pos, 0.75)))
		_corpse_mm.set_instance_color(i, AntModel.tint(dead.lerp(Color(0.32, 0.27, 0.22), clampf(c.age / 30.0, 0.0, 1.0))).srgb_to_linear())
		_corpse_mm.set_instance_custom_data(i, Color(0, 11, 0, 0))
	for i in _carried.size():
		_corpse_mm.set_instance_transform(n + i, _carried[i])
		_corpse_mm.set_instance_color(n + i, AntModel.tint(dead).srgb_to_linear())
		_corpse_mm.set_instance_custom_data(n + i, Color(0, 11, 0, 0))


func _update_spider(delta: float) -> void:
	if sim.spider.is_empty():
		_spider_mm.instance_count = 0
		_spider_vis = {}
		return
	var s: Dictionary = sim.spider
	if _spider_vis.is_empty():
		_spider_vis = {"p": s.pos, "a": s.ang, "mv": 0.0}
	var step: Vector2 = s.pos - _spider_vis.p
	_spider_vis.p += step * (1.0 - exp(-15.0 * delta))
	_spider_vis.a = lerp_angle(_spider_vis.a, s.ang, 1.0 - exp(-8.0 * delta))
	_spider_vis.mv = lerpf(_spider_vis.mv, 1.0 if step.length_squared() > 0.0004 else 0.0, minf(1.0, 6.0 * delta))
	var p: Vector2 = _spider_vis.p * U
	var up := ground_n(p.x, p.y)
	var f := Vector3(cos(_spider_vis.a), 0, sin(_spider_vis.a))
	f = (f - up * f.dot(up)).normalized()
	_spider_mm.instance_count = 1
	_spider_mm.set_instance_transform(0, Transform3D(Basis(f, up, f.cross(up)).scaled(Vector3.ONE * 0.85), Vector3(p.x, ground_h(p.x, p.y), p.y)))
	_spider_mm.set_instance_custom_data(0, Color(fmod(s.phase * 0.5, TAU * 64.0), 0, _t, _spider_vis.mv))


func _update_rain(delta: float, raining: bool) -> void:
	var sdt := delta if speed > 0 else 0.0
	for s in _splash:
		s[1] += sdt
	_splash = _splash.filter(func(s): return s[1] < 0.35)
	_splash_mm.instance_count = _splash.size()
	for i in _splash.size():
		var k: float = _splash[i][1] / 0.35
		var r := 0.25 + 0.9 * k
		_splash_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, 0.4, r)), _splash[i][0]))
		_splash_mm.set_instance_color(i, Color(1, 1, 1, 0.55 * (1.0 - k)))
	if not raining:
		_rain_mm.instance_count = 0
		return
	_rain_mm.instance_count = _rain.size()
	var dt := delta if speed > 0 else 0.0
	for i in _rain.size():
		var d: Vector3 = _rain[i]
		d.y -= 150.0 * dt
		d.x -= 30.0 * dt
		if d.y < ground_h(d.x, d.z):
			if _splash.size() < 160 and randf() < 0.7:
				_splash.append([Vector3(d.x, ground_h(d.x, d.z) + 0.1, d.z), 0.0])
			d = Vector3(randf() * 400.0, 60.0, randf() * 250.0)
		_rain[i] = d
		_rain_mm.set_instance_transform(i, Transform3D(Basis(Vector3.BACK, 0.2), d))


func _update_ring() -> void:
	var t: String = world.tool
	_ring.visible = hover != Vector3.INF and t in ["rock", "erase"]
	if _ring.visible:
		var r := (10.0 if t == "rock" else 24.0) * U
		_ring.position = hover + Vector3(0, 0.3, 0)
		_ring.scale = Vector3(r, 1.0, r)


# ---------------------------------------------------------------- camera

func snap_camera() -> void:
	yaw = yaw_t
	pitch = pitch_t
	cam_dist = dist_t
	target = target_t
	_update_camera()


func _fit_dist() -> float:
	var vp := get_viewport().get_visible_rect().size
	var area_w := maxf(200.0, vp.x - SIDE_PANEL_PX)
	var tanh := tan(deg_to_rad(_cam.fov * 0.5))
	var by_w: float = sim.WORLD.x * U * 1.06 / area_w * vp.y / (2.0 * tanh)
	var by_h: float = sim.WORLD.y * U * 1.1 * sin(pitch_t) / (2.0 * tanh) + 40.0
	return maxf(by_w, by_h)


func reset_view() -> void:
	yaw_t = 0.0
	pitch_t = 0.95
	target_t = Vector3(sim.WORLD.x * U * 0.5, 0, sim.WORLD.y * U * 0.5 + 6.0)
	dist_t = _fit_dist()


func top_down() -> void:
	yaw_t = 0.0
	pitch_t = 1.5
	target_t = Vector3(sim.WORLD.x * U * 0.5, 0, sim.WORLD.y * U * 0.5)
	dist_t = _fit_dist()


func focus_nest() -> void:
	target_t = _on_ground(sim.nest_pos)
	dist_t = 60.0
	pitch_t = clampf(pitch_t, 0.6, 1.1)


func zoom_by(f: float) -> void:
	dist_t = clampf(dist_t * f, 8.0, 900.0)


func turn_by(a: float) -> void:
	yaw_t += a


func _ease_camera(delta: float) -> void:
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
		target_t += (_right() * mv.x + _forward() * mv.y) * dist_t * 0.9 * delta
	if Input.is_key_pressed(KEY_Q):
		yaw_t += 1.4 * delta
	if Input.is_key_pressed(KEY_E):
		yaw_t -= 1.4 * delta
	if Input.is_key_pressed(KEY_R):
		pitch_t = clampf(pitch_t + 0.9 * delta, 0.12, 1.54)
	if Input.is_key_pressed(KEY_F):
		pitch_t = clampf(pitch_t - 0.9 * delta, 0.12, 1.54)
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		zoom_by(1.0 - 1.6 * delta)
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		zoom_by(1.0 + 1.6 * delta)
	var hi := Vector3(sim.WORLD.x * U + 30.0, 0, sim.WORLD.y * U + 30.0)
	target_t = target_t.clamp(Vector3(-30, 0, -30), hi)
	target_t.y = clampf(ground_h(target_t.x, target_t.z), -2.0, 3.0)
	var k := 1.0 - exp(-10.0 * delta)
	yaw = lerp_angle(yaw, yaw_t, k)
	pitch = lerpf(pitch, pitch_t, k)
	cam_dist = lerpf(cam_dist, dist_t, k)
	target = target.lerp(target_t, k)


func _right() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


func _forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func _update_camera() -> void:
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	_cam.position = target + dir * cam_dist
	_cam.look_at(target, Vector3.UP if pitch < 1.55 else _forward())
	# keep the point of interest in the middle of the area left of the side panel
	var vp := get_viewport().get_visible_rect().size
	_cam.h_offset = SIDE_PANEL_PX * 0.5 * 2.0 * cam_dist * tan(deg_to_rad(_cam.fov * 0.5)) / vp.y


## Point on the ground under a screen position (INF if the ray misses).
func pick(sp: Vector2) -> Vector3:
	var o := _cam.project_ray_origin(sp)
	var d := _cam.project_ray_normal(sp)
	if d.y > -0.01:
		return Vector3.INF
	var h := 0.0
	var p := Vector3.INF
	for i in 3:
		var t := (h - o.y) / d.y
		p = o + d * t
		h = ground_h(p.x, p.z)
	return p


func _px(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) / U


# ---------------------------------------------------------------- input

func _unhandled_input(e: InputEvent) -> void:
	if not active:
		return
	var tool: String = world.tool
	if e is InputEventMouseButton:
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and e.pressed:
			var f := 1.0 / 1.18 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.18
			var at := pick(e.position)
			var before := dist_t
			zoom_by(f)
			if at != Vector3.INF:
				# zoom toward the point under the mouse
				target_t = at + (target_t - at) * (dist_t / before)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if tool == "pan":
				if e.pressed and e.double_click:
					var at := pick(e.position)
					if at != Vector3.INF:
						target_t = at
						dist_t = minf(dist_t * 0.5, 90.0)
				_pan = e.pressed and e.shift_pressed
				_rot = e.pressed and not e.shift_pressed
			elif e.pressed:
				_use_tool(tool, pick(e.position))
				_painting = tool in ["rock", "erase"]
			else:
				_painting = false
		elif e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE:
			_pan = e.pressed
			_rot = false
	elif e is InputEventMouseMotion:
		hover = pick(e.position)
		if _rot:
			yaw_t -= e.relative.x * 0.007
			pitch_t = clampf(pitch_t + e.relative.y * 0.006, 0.12, 1.54)
		elif _pan:
			var vp := get_viewport().get_visible_rect().size
			var upp := 2.0 * cam_dist * tan(deg_to_rad(_cam.fov * 0.5)) / vp.y
			target_t += (-_right() * e.relative.x + _forward() * e.relative.y / maxf(0.35, sin(pitch))) * upp
		elif _painting and hover != Vector3.INF:
			_use_tool(tool, hover)
	elif e is InputEventKey and e.pressed and e.keycode == KEY_HOME:
		reset_view()


func _use_tool(tool: String, at: Vector3) -> void:
	if at == Vector3.INF:
		return
	var p := _px(at)
	match tool:
		"honey", "cricket":
			sim.place_food(tool, p)
			_items_timer = 0.0
		"rock":
			if p.distance_to(_last_paint) > 9.0 and sim.can_place(p) and sim.add_rock(p, 10.0):
				_last_paint = p
				world.redraw_scenery()
				_items_timer = 0.0
		"erase":
			sim.erase_pheromones(p, 24.0)
