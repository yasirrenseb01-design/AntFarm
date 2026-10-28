extends Node3D
## The outworld box in 3D: the same simulation and the same scenery layout as the top-down view,
## seen through an orbit camera. Foragers use the same 3D Lasius niger model and body animation
## as the nest view. 1 unit = 1.5 mm (a nest voxel) = 3 px of the simulation's outworld.
## Outworld view, layer 1 of 5: state, the ground shape (matches shaders/terrain/outworld_ground),
## the box, scenery and shared materials.
## Layers: outworld_scene <- outworld_props <- outworld_crowd <- outworld_creatures <- outworld_camera <- outworld_view.
const Ant := preload("res://scripts/sim/ant.gd")
const Spec := preload("res://scripts/view/common/tank_spec.gd")
const NestCard := preload("res://scripts/game/nest_card.gd")
const AntModel := preload("res://scripts/view/common/ant_model3d.gd")
const Props := preload("res://scripts/view/common/mesh_kit.gd")
const PropHeights := preload("res://scripts/view/outworld/prop_heights.gd")
var sel_kind := ""                # the ant the keeper clicked ("worker"), and its id
var sel_id := -1
var _sel_mm: MultiMesh            # its white outline
var _sel_shader_mat: ShaderMaterial
const FoodKinds := preload("res://scripts/sim/food_kinds.gd")
const GroundData := preload("res://scripts/view/outworld/ground_data.gd")
const SceneryDraw := preload("res://scripts/view/outworld/scenery_draw.gd")
const KeeperRoom := preload("res://scripts/view/outworld/keeper_room.gd")

const U := 1.0 / 3.0                 # simulation px -> units
var ANT_SCALE := Spec.ANT_SCALE     # x the species' worker_scale (outworld_view.setup); 1.1 until v0.11.53
const GARDEN_MARGIN := 110.0          # how far (units) the garden ground is drawn past the plot outdoors
const M := 1.0 / Spec.VOXEL          # units a metre
const SOIL_BOTTOM := -Spec.SOIL * M  # the box's soil, as deep as the nest, seen through the glass down to its floor (units)
const FLUON_BAND := 12.0          # the slippery band painted under the rim (~1.8 cm): climbing ants turn back below it
const CARRY_OFFSET := Transform3D(Basis(Vector3(0.55, 0, 0), Vector3(0, 0.55, 0), Vector3(0, 0, 0.55)), Vector3(1.35, 0.6, 0.0))   # in the mandibles of a raised head (shader act 8)
const THROWN_S := 1.6                # seconds: thrown off an enemy, on its back, righted again
const SIDE_PANEL_PX := 364.0         # the HUD's side panel covers the right of the window
var side_px := SIDE_PANEL_PX         # ... unless it is folded away (0; the HUD sets it)

var sim
var wall_h := 42.0                   # the glass above the ground, to its rim (units; the box's own height in _build_box)
var room_info := {}                  # a keeper's box: where it stands in the Home (keeper_room.build; main.gd sets it)
var room                             # the Home's room round it (view/home/home_room.gd), or null (the wild mode)
var _room_rot := Basis()
var _stand_y := 0.0                  # the desk's or the shelf's top under the box (units)
var _soil_mat: ShaderMaterial        # the soil seen through the glass (and its nest)
var _card_at := 0
var ground                           # ground_data.gd: textures, pheromone image, scenery and the keeper's tool
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
var _fly_wings: StandardMaterial3D
var _ant_shader_mat: ShaderMaterial
var _frost := -1.0        # -1 until the first frame (then it starts at the right value)
var _env: Environment
var _ground_mat: ShaderMaterial
var _prop_mat: StandardMaterial3D
var _ant_meshes := {}
var _lod := ""
var _ant_mm: MultiMesh
var _corpse_mm: MultiMesh
var _prey_mm: MultiMesh
var _creature_views := {}          # enemy kind -> {"mm": MultiMesh, "mat": ShaderMaterial, "scale", "gait"}
var _creature_vis := {}            # creature id -> drawn position/heading smoothing
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
var _props_h = PropHeights.new()     # litter the ants walk up over (pebbles, moss, twigs, leaves)
var _rot := false
var _pan := false
var _painting := false
var _last_paint := Vector2(-999, -999)
var hover := Vector3.INF
var _t := 0.0
var _wet := 0.0
var _plant_mat: ShaderMaterial      # host plants and fallen leaves move in the air
var _litter_mat: ShaderMaterial
var _weed_mat: ShaderMaterial       # the garden's weeds (shaders/plants/weed_leaf)
var _grass_mat: ShaderMaterial
var _aphid_meshes: Array = []
var _aphid_wings: Mesh
var _dew_mm: MultiMesh              # honeydew droplets an aphid is handing to a milking ant
var _splash_mm: MultiMesh
var _soil_mm: MultiMesh             # soil grains in the mandibles of ants burying a carcass
var _spray_mm: MultiMesh            # formic acid mist from ants fighting an enemy
var _spider_mat: ShaderMaterial
var _splash: Array = []             # [position, age]


# ---------------------------------------------------------------- ground shape (matches the shader)

func ground_h(x: float, z: float) -> float:
	# (as in shaders/terrain/ground_h.gdshaderinc, v0.11.71: broad swells up to ~1 cm, smaller rises and dips between)
	var h := 3.6 * sin(x * 0.017 + 1.3) * cos(z * 0.023 + 0.4) + 1.6 * sin(x * 0.049 + z * 0.037 + 2.0)
	h += 0.6 * sin(x * 0.13 + 0.7) * sin(z * 0.11 + 1.9)
	var d := Vector2(x - _nest_xz.x, z - _nest_xz.y).length()
	var k := (d - _mound_r) / (_mound_r * 0.6)
	var mh := maxf(_mound, 0.0)
	h += mh * exp(-k * k) + mh * 0.5 * (1.0 - smoothstep(0.0, _mound_r, d))
	h -= 1.6 * (1.0 - smoothstep(0.6, 1.9, d))
	return h


func ground_n(x: float, z: float) -> Vector3:
	var e := 0.6
	return Vector3(ground_h(x - e, z) - ground_h(x + e, z), 2.0 * e, ground_h(x, z - e) - ground_h(x, z + e)).normalized()


## The surface an ant walks on: the ground, or the top of the litter lying on it.
func ground_top(x: float, z: float) -> float:
	return ground_h(x, z) + (_props_h.at(x, z) if _props_h.w > 0 else 0.0)


## Its up direction (an ant on the side of a pebble leans with it, up to a steep climb).
func ground_top_n(x: float, z: float) -> Vector3:
	var e := 0.35
	var n := Vector3(ground_top(x - e, z) - ground_top(x + e, z), 2.0 * e, ground_top(x, z - e) - ground_top(x, z + e)).normalized()
	if n.y < 0.35:
		n = (n * Vector3(1, 0, 1)).normalized() * 0.937 + Vector3(0, 0.35, 0)
	return n.normalized()


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
	# outdoors (no box) the ground runs on past the plot all round
	var m: float = GARDEN_MARGIN if sim.scenario == "wild" else 0.0
	var nx := 200 + int(m)
	var nz := 125 + int(m)
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in nz + 1:
		for i in nx + 1:
			verts.append(Vector3(-m + (w + 2.0 * m) * i / nx, 0, -m + (d + 2.0 * m) * j / nz))
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
	mesh.custom_aabb = AABB(Vector3(-m, -4, -m), Vector3(w + 2.0 * m, 10, d + 2.0 * m))
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
	_ground_mat.set_shader_parameter("soil_tex", ground.soil_tex)
	_ground_mat.set_shader_parameter("damp_tex", ground.damp_tex)
	_ground_mat.set_shader_parameter("grain_tex", ground.grain_tex)
	_ground_mat.set_shader_parameter("detail", detail)
	_ground_mat.set_shader_parameter("pher_tex", ground.pher_tex)
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
	var mats: Array = [_ground_mat] + _creature_views.values().map(func(cv): return cv.mat)
	if _ant_shader_mat != null:
		mats.append(_ant_shader_mat)
	for mat in mats:
		mat.set_shader_parameter("mound_h", _mound)
		mat.set_shader_parameter("mound_r", _mound_r)
		mat.set_shader_parameter("nest_xz", _nest_xz)


func _build_box() -> void:
	if sim.scenario == "wild":
		return          # a plot of garden ground: no glass box, no tray, no table (the ground runs on)
	var w: float = sim.WORLD.x * U
	var d: float = sim.WORLD.y * U
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.85, 0.93, 1.0, 0.035)
	glass.roughness = 0.03
	glass.metallic_specular = 1.0
	# (each pane's outer face only, and its inner one from inside: drawn both ways, a side seen through four faces of
	# glass looked misty)
	var trim := _mat(Color(0.07, 0.065, 0.06), 0.45)
	# the box as the Home draws it (home_kit._tank), to the one set of sizes (tank_spec.gd): glass under it and round
	# it, its soil as deep as the nest (the keeper, 2026-10-27: "the box is tall but its soil is not - where would the
	# nest be?"), 20 cm tall from its floor (27 the bigger), a dark rim along its top and bottom edges
	var gu := Spec.GLASS * M
	var top := SOIL_BOTTOM + Spec.tall(sim.WORLD.x > sim.SMALL_WORLD.x) * M
	var bottom := SOIL_BOTTOM - gu
	wall_h = top + 2.0
	var ow := w + gu * 2.0
	var od := d + gu * 2.0
	var gh := top - bottom
	var yh := (top + bottom) * 0.5
	_box(Vector3(ow, gh, gu), Vector3(w * 0.5, yh, -gu * 0.5), glass)
	_box(Vector3(ow, gh, gu), Vector3(w * 0.5, yh, d + gu * 0.5), glass)
	_box(Vector3(gu, gh, d), Vector3(-gu * 0.5, yh, d * 0.5), glass)
	_box(Vector3(gu, gh, d), Vector3(w + gu * 0.5, yh, d * 0.5), glass)
	_box(Vector3(w, gu, d), Vector3(w * 0.5, bottom + gu * 0.5, d * 0.5), glass)      # (its floor)
	_build_soil_edge(w, d)
	var r := Spec.RIM * M
	for y in [bottom + r * 0.5, top - r * 0.5]:
		for e in [[Vector3(ow + r, r, r), Vector3(w * 0.5, y, d + gu)], [Vector3(ow + r, r, r), Vector3(w * 0.5, y, -gu)],
				[Vector3(r, r, od), Vector3(w + gu, y, d * 0.5)], [Vector3(r, r, od), Vector3(-gu, y, d * 0.5)]]:
			_box(e[0], e[1], trim)
	# where it stands in the Home: the Home's own room round it (keeper_room.gd)
	room_info["fridge"] = sim.fridge_on
	room = KeeperRoom.build(self, room_info, sim.WORLD.x > sim.SMALL_WORLD.x, bottom, _env)
	_stand_y = bottom
	_cam.far = 130000.0                  # (the window's view: mountains 150 m off)
	_room_rot = room.transform.basis.orthonormalized()


## The keeper put this colony in the fridge or took it out ("Hibernate in fridge"): the room built again, the box on the
## fridge's shelf or back on the desk (the keeper, 2026-10-28: in the fridge in the Home, on the desk in the game - the
## room was built once, when the colony was opened).
func _check_room_fridge() -> void:
	if room == null or room.get_meta("fridge", null) == null or bool(room.get_meta("fridge")) == sim.fridge_on:
		return
	for l in [room._sun, room._moon, room._lamp, room._spot, room.fridge_light]:
		l.queue_free()                         # (moved out from under the room: keeper_room.gd)
	room.queue_free()
	room_info["fridge"] = sim.fridge_on
	room = KeeperRoom.build(self, room_info, sim.WORLD.x > sim.SMALL_WORLD.x, _stand_y, _env)
	_room_rot = room.transform.basis.orthonormalized()


## The soil seen through the glass: a skirt from the uneven ground surface down to the box's floor, facing out (grainy:
## a noise texture laid on it, darker and damper lower down).
func _build_soil_edge(w: float, d: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bottom := SOIL_BOTTOM
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
			var out := Vector3.UP.cross(b - a).normalized()
			for v in [t0, b0, t1, t1, b0, b1]:
				var depth := clampf((v.y - bottom) / (-bottom), 0.0, 1.0)
				st.set_color(Color(0.3, 0.2, 0.13).lerp(Color(0.62, 0.45, 0.3), depth))
				st.set_normal(out)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	# the Home's tank soil (shaders/common/tank_soil.gdshader): layered, the colony's nest on the long faces where it lies
	_soil_mat = ShaderMaterial.new()
	_soil_mat.shader = load("res://shaders/common/tank_soil.gdshader")
	_soil_mat.set_shader_parameter("mpu", Spec.VOXEL)
	_soil_mat.set_shader_parameter("soil_top", 0.0)
	_soil_mat.set_shader_parameter("nest_x0", _nest_xz.x - float(sim.nest.entrance.x))
	_soil_mat.set_shader_parameter("nest_w", float(sim.nest.nx))
	_soil_mat.set_shader_parameter("nest_h", float(sim.nest.hy()))
	_soil_mat.set_shader_parameter("seed", float(sim.WORLD.x))
	mi.material_override = _soil_mat
	add_child(mi)
	_refresh_nest_card(true)


## The nest on the soil's faces: its side view again every few seconds (as the ants dig).
func _refresh_nest_card(now := false) -> void:
	var t := Time.get_ticks_msec()
	if _soil_mat == null or (not now and t - _card_at < 5000):
		return
	_card_at = t
	_soil_mat.set_shader_parameter("nest_tex", ImageTexture.create_from_image(NestCard.image(sim.nest)))
	_soil_mat.set_shader_parameter("nest_h", float(sim.nest.hy()))
	_soil_mat.set_shader_parameter("has_tex", true)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


## Litter, pebbles, moss, grass, weeds, the garden's big stones and the crater/midden grains (scenery_draw.gd).
func _build_scenery() -> void:
	SceneryDraw.build(self)


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


## A fly's wings: clear membrane with a faint rainbow sheen where the light catches it.
func _fly_wing_mat() -> StandardMaterial3D:
	if _fly_wings == null:
		_fly_wings = StandardMaterial3D.new()
		_fly_wings.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fly_wings.albedo_color = Color(0.78, 0.8, 0.85, 0.12)
		_fly_wings.roughness = 0.05
		_fly_wings.metallic_specular = 0.9
		_fly_wings.rim_enabled = true
		_fly_wings.rim = 0.4
		_fly_wings.rim_tint = 0.2
		_fly_wings.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _fly_wings


## Aphid honeydew: a clear, glistening droplet (sugary water; the keeper's honey drops are _honey_mat).
func _dew_mat() -> StandardMaterial3D:
	if _dew == null:
		_dew = StandardMaterial3D.new()
		_dew.albedo_color = Color(0.92, 0.9, 0.78, 0.45)
		_dew.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dew.roughness = 0.03
		_dew.metallic_specular = 1.0
		_dew.rim_enabled = true
		_dew.rim = 0.6
	return _dew


var _dew: StandardMaterial3D


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


## Outdoors the plants wither in the cold months and the ground whitens with frost on freezing nights.
func _seasons(delta: float) -> void:
	var wild: bool = sim.scenario == "wild"
	var wither: float = 1.0 - sim.season_life() if wild else 0.0
	var frost_to: float = clampf((0.5 - sim.climate.air) / 3.0, 0.0, 1.0) if wild else 0.0
	_frost = frost_to if _frost < 0.0 else move_toward(_frost, frost_to, delta * 0.2 * maxf(speed, 0.5))
	for m in [_grass_mat, _plant_mat, _weed_mat]:
		m.set_shader_parameter("wither", wither)
		m.set_shader_parameter("frost", _frost)
	_ground_mat.set_shader_parameter("frost", _frost)
