extends Node3D
## The outworld box in 3D: the same simulation and the same scenery layout as the top-down view,
## seen through an orbit camera. Foragers use the same 3D Lasius niger model and body animation
## as the nest view. 1 unit = 1.5 mm (a nest voxel) = 3 px of the simulation's outworld.
## Outworld view, layer 1 of 5: state, the ground shape (matches shaders/terrain/outworld_ground),
## the box, scenery and shared materials.
## Layers: outworld_scene <- outworld_props <- outworld_creatures <- outworld_camera <- outworld_view.
const Ant := preload("res://scripts/sim/ant.gd")
const AntModel := preload("res://scripts/view/common/ant_model3d.gd")
const Props := preload("res://scripts/view/common/mesh_kit.gd")
const FoodKinds := preload("res://scripts/sim/food_kinds.gd")

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
var _spider_vis: Array = []        # smoothing state per wolf spider, in sim.creatures order
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
var _soil_mm: MultiMesh             # soil grains in the mandibles of ants burying a carcass
var _splash: Array = []             # [position, age]


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
	_ground_mat.shader = load("res://shaders/terrain/outworld_ground.gdshader")
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
	m.shader = load("res://shaders/plants/sway.gdshader")
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


var _husks: Array = []
var _husk_mat: StandardMaterial3D


var _honey: StandardMaterial3D
var _flesh: StandardMaterial3D
var _grain_mesh: Mesh
var _grain_mat: StandardMaterial3D


func _flesh_mat() -> StandardMaterial3D:
	if _flesh == null:
		_flesh = _mat(Color(0.78, 0.62, 0.46), 0.5)
	return _flesh


## How far the ants have buried a carcass: Lasius niger carry soil grains onto large food they are
## exploiting, starting from the ground around it and working up its sides.
func _cover(f: Dictionary) -> float:
	return clampf((f.age - 0.15) / 4.0, 0.0, 0.85) if f.found else 0.0
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


var _carried: Array = []
