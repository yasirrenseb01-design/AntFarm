extends Node3D
## 3D view of the underground nest: the soil block sliced open by a camera-facing cut plane,
## with diggers from the simulation, resting nestmates, brood piles and the queen.
## Nest view, layer 1 of 7: state and the building blocks of the scene (soil chunks, materials,
## meshes, the glass case). Layers: nest_scene <- nest_camera <- nest_brood <- nest_lifecycle <- nest_bodies <- nest_mates <- nest_view.
const Ant := preload("res://scripts/sim/ant.gd")
const Mesher := preload("res://scripts/view/nest/nest_mesher.gd")
const AntModel := preload("res://scripts/view/common/ant_model3d.gd")
const Props := preload("res://scripts/view/common/mesh_kit.gd")
const EventFeed := preload("res://scripts/view/common/event_feed.gd")
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
var _feed                          # EventFeed: life-cycle moments from the simulation (set up in setup())
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
var _mate_frame := 0
var _brood_occ := {}             # brood laid this layout, binned (see nest_brood _place_brood)
var _meshing := {}               # chunk -> {"task", "out"}: meshes being made on worker threads
var _queen_cells := {}           # voxel cells the queen's body fills: nestmates walk round them
# the queen's body as a capsule, in her model's units (scaled by her transform)
const QUEEN_HEAD := Vector3(1.25, 0.5, 0.0)
const QUEEN_TAIL := Vector3(-1.45, 0.5, 0.0)
const QUEEN_R := 1.05
const QUEEN_LIFT := 0.38      # her model reaches 0.24 below her feet (gaster) x QUEEN_SCALE
const QUEEN_SCALE := 1.75     # her model at this scale is ~9 mm long (a Lasius niger queen: 8-9 mm; workers 3.5-5)
var _queen_turn := 0.0
var _queen_turn_t := 0.0
var _queen_mode := 1               # what she is doing between lifecycle moments: ACT_REST/GROOM/ANTENNATE/WALK
var _queen_mode_left := 0.0
var _queen_gait := 0.0
var _queen_mv := 0.0
var _queen_prev_turn := 0.0
var _queen_act := -1
var _egg_spots: Array = []         # floor beside the queen (not under her) where the egg packets lie


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


func _multimesh(mesh: Mesh, mat: Material, colors: bool, shadows := true) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_set_chunk(k, Mesher.build(nest, k))


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
		var dens := Mesher.sample(nest, k)
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


func _hash(i: int, s: int) -> float:
	var x := sin(i * 12.9898 + s * 78.233) * 43758.5453
	return x - floor(x)


func _up_at(c: Vector3i) -> Vector3:
	var u := Vector3.ZERO
	for d in DIRS:
		var n := c + d
		if not nest.inside(n) or not nest.is_open(n):
			u -= Vector3(d)
	return u.normalized() if u.length_squared() > 0.01 else Vector3.UP


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


# ---------------------------------------------------------------- life-cycle moments
# The simulation reports each egg laid, larva pupating and worker eclosing (sim.events). At watchable
# speeds the nest view acts them out: the queen lays and an attendant (or, while founding, the queen
# herself) carries the egg to the pile; a nurse covers a spinning larva and carries the new cocoon
# up to the pupa chamber; nurses bite open a cocoon and a pale callow unfolds and stands up.

const MOUTH := Vector3(1.2, 0.32, 0.0)          # mandible tip in the ant model, before scaling
const GASTER_TIP := Vector3(-1.85, 0.25, 0.0)


func _pending(kind: String) -> int:
	var n := 0
	for a in _anims:
		if a.k == kind and not a.get("done", false):
			n += 1
	return n


func _fill(mm: MultiMesh, xs: Array) -> void:
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
