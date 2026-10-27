extends Node3D
## 3D view of the underground nest: the soil block sliced open by a camera-facing cut plane,
## with diggers from the simulation, resting nestmates, brood piles and the queen.
## Nest view, layer 1 of 15: state and the building blocks of the scene (soil chunks, materials,
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
var follow_wid := -1            # a worker the camera keeps in view (the HUD's star ants panel; nest_view.refresh), -1 = none
var xray := false                 # "see through the soil": tunnels drawn as a translucent cast
var _ghost: MeshInstance3D        # faint outline of the soil block in x-ray view
var _ant_meshes := {}             # "hi"/"lo" -> [pose A, pose B]
var _lod := ""
var _chunks := {}
var _queue: Array = []
var _ant_mm: MultiMesh
var _queen_mm: MultiMesh
var _queen_anim := 0.0
var _queen_vact := Vector3(-1, 0, 0)    # easing between her poses (AntModel.act_step)
var _queen_lay := 0.0
var _queen_turn_v := 0.0            # how fast she is turning now (rad/s; eased, see nest_lifecycle)
var _queen_step_v := Vector3.ZERO   # and walking
var _queen_tshare := 0.0           # how much of her stepping is turning on the spot (signed; shader gait_w)
var _queen_dy := 0.0                # how far she has risen with the floor where she stepped to (see _queen_pose)
var _queen_pitch := 0.0             # her front tipped up (+) or down with the floor's slope
var _care_left := 8.0               # a founding queen alone: seconds until she next goes to tend her brood
var _last_eggs := 0
var _egg_mm: MultiMesh
var _larva_mm: MultiMesh
var _pupa_mm: MultiMesh
var _pellet_mm: MultiMesh
var _mates: Array = []
var _dig_vis := {}
var _spots := {"eggs": [], "larvae": [], "larvae_old": [], "pupae": [], "pupae_old": [], "all": [], "queen": Vector3.ZERO}
var _room_of := {}                 # chamber index -> index in _rooms (chambers with a floor)
var _pupa_group := ""              # "c<chamber>" the cocoons are kept in (sim_warmth), and the one before
var _pupa_prev := ""
var _moved_p := 1 << 20            # cocoons already carried to it
var _queen_room_ch := -1           # the chamber she is in (or walking to)
var _queen_path: Array = []        # floor positions still to walk on her way there
var _queen_roam_left := 30.0       # seconds until she next walks to another spot of her chamber (nest_lifecycle._queen_roam)
var _queen_rest_turn := 0.0        # which way she faces when nothing else turns her
var _queen_home_prev := Vector3.ZERO
var _queen_walk_fwd := Vector3.RIGHT   # the way she faces on her way (eased)
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
const CARRY_OFFSET := Transform3D(Basis(Vector3(0.55, 0, 0), Vector3(0, 0.55, 0), Vector3(0, 0, 0.55)), Vector3(1.35, 0.6, 0.0))   # in the mandibles of a raised head (shader act 8)
var _spot_timer := 0.0
var _rot := false
var _pan := false
var _plane_n := Vector3(0, 0, 1)
var _plane_w := 1e6
var _frustum: Array[Plane] = []   # the camera's view, refreshed with it: off-screen ants are not drawn
var _t := 0.0
signal cut_changed(value: float)
var _brood_sig: Array = []
var _mound_n := -1
var _vol: ImageTexture3D
var _vol_timer := 0.0
var _foot_vol: ImageTexture3D       # the soil with the brood in it, for the ants' feet (they stand on eggs, larvae, cocoons)
var _foot_rho := PackedByteArray()
var _foot_timer := 0.0
var _foot_climbs := 0                # nestmates climbing over others at the last foot-map upload (then it is renewed sooner)
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
var _brood_wide := {}            # cells too near the brood to stop on (a body width clear; _cell_free)
var _brood_cells := {}           # cells with brood on the floor: routes go round them (nest_brood _mark_brood_cells)
var _cut_mats: Array = []          # the ants' materials, cut at the cut plane (nest_view refresh)
var _ant_shader_mat: ShaderMaterial   # the workers' material (shadow_pose follows the level of detail)
var _egg_at := {}                # egg tag -> where it was laid (it stays there until it hatches)
var _freed := {"eggs": [], "larvae": []}   # where brood just hatched / pupated lay: the next stage starts there
var _anim_drops := []            # droplets drawn by life-cycle moments (trophallaxis), added to the nestmates' drops
var _soil_gen := 0              # bumped whenever the soil changes (cached brood checks are redone)
var _lift_cache := {}            # per walkable cell: how far a body standing there is raised (_cell_lift)
var _gfit_cache := {}            # per cell: the ground round it (_ground_ring)
var _gfit_budget := 0            # ground fits still to work out this frame
var _fit_cache := {}             # per walkable cell: whether a body can lie there clear of the walls (_cell_fits)
var _floor_cache := {}          # floor heights under brood spots (see _floor_cached)
var sel_kind := ""                # the ant the keeper clicked: "worker" | "digger" | "queen" ("" = none)
var sel_id := -1                  # its worker id (a digger: the digger's own id)
var _sel_mm: MultiMesh            # its white outline (shaders/ants/ant_outline.gdshader)
var _sel_mat: ShaderMaterial
var _feet_tex: ImageTexture       # where the workers' tripods were set down (nest_bodies._feet_rec, ant_core.gdshaderinc feet_tex)
var _feet_buf := PackedFloat32Array()     # (the same, kept for the dev checks: dev/foot_check.gd)
var _sel_queen_mm: MultiMesh
var _sel_brood_mm: MultiMesh       # the rim round a clicked egg, larva or cocoon
var fprof := {}                 # dev (--perf): microseconds per part of refresh(), summed
var _brood_occ := {}             # brood laid this layout, binned (see nest_brood _place_brood)
var _brood_gen := 0               # counts brood layouts (what is cached against the brood is worked out again)
# where each item of brood lies, kept from one layout to the next so a pile stays still when an egg is added
# or one hatches (items are told apart by a view tag "_v" written into the simulation's brood entries)
var _placed := {}                # tag -> {"base": floor point (or top of what it rests on), "b": Basis, "src": pile key, "top": bool}
var _egg_slot := {}              # egg tag -> its place in the packet (an index into _egg_xf)
var _slot_egg := {}              # the reverse: slot -> egg tag
var _vnext := 0
var _meshing := {}               # chunk -> {"task", "out"}: meshes being made on worker threads
var _mate_cells := {}           # cell -> the nestmate standing (or about to stand) there, this frame
var _queen_cells := {}           # voxel cells the queen's body fills: nestmates walk round them
# the queen's body as a capsule, in her model's units (scaled by her transform)
const QUEEN_HEAD := Vector3(1.25, 0.5, 0.0)
const QUEEN_TAIL := Vector3(-1.45, 0.5, 0.0)
const QUEEN_R := 1.05
const QUEEN_LIFT := 0.38      # her model reaches 0.24 below her feet (gaster) x queen_scale
var queen_scale := 1.75       # her model's scale: the species' look (Lasius niger: ~9 mm long; set in nest_view.setup)
var _queen_turn := 0.0
var _queen_turn_t := 0.0
var _queen_step := Vector3.ZERO      # a few steps away from her spot (carrying an egg to the packet), drawn only
var _queen_step_t := Vector3.ZERO
var _queen_step_prev := Vector3.ZERO
var _queen_mode := 1               # what she is doing between lifecycle moments: ACT_REST/GROOM/ANTENNATE/WALK
var _queen_mode_left := 0.0
var _queen_gait := 0.0
var _queen_mv := 0.0
var _queen_prev_turn := 0.0
var _queen_act := -1
var _egg_spots: Array = []         # floor beside the queen (not under her) where the egg packets lie


# ---------------------------------------------------------------- meshes

## The soil density at a point (trilinear between voxels, as the soil mesh is built from it).
func _density_at(p: Vector3) -> float:
	if _soft.is_empty():
		_soft_build(Vector3i(-1, nest.y_lo - 1, -1), Vector3i(nest.nx, nest.ny, nest.nz))
	var x := floori(p.x)
	var y := floori(p.y)
	var z := floori(p.z)
	if x < -1 or y < nest.y_lo - 1 or z < -1 or x >= nest.nx or y >= nest.ny or z >= nest.nz:
		return 0.0                                 # (beyond the block and its first ring of air)
	var fx := p.x - x
	var fy := p.y - y
	var fz := p.z - z
	var i := ((z + 1) * _sy + (y - _sy0 + 1)) * _sx + (x + 1)
	var d00 := lerpf(_soft[i], _soft[i + 1], fx)
	var d10 := lerpf(_soft[i + _sx], _soft[i + _sx + 1], fx)
	var j := i + _sx * _sy
	var d01 := lerpf(_soft[j], _soft[j + 1], fx)
	var d11 := lerpf(_soft[j + _sx], _soft[j + _sx + 1], fx)
	return lerpf(lerpf(d00, d10, fy), lerpf(d01, d11, fy), fz)


## The mesher's softened density (nest_voxels.gd density()) for every voxel from a to b (inclusive), kept in
## _soft with a ring of one voxel round the block: read by _density_at, which every check of bodies against the
## soil uses (it computed the softening from the voxels each time - most of the cost of those checks). Redone
## where the ants dig (nest_view refresh).
var _soft := PackedFloat32Array()
var _sx := 0
var _sy := 0
var _sy0 := 0                       # (the layer _soft starts at: nest.y_lo when it was laid out)
func _soft_build(a: Vector3i, b: Vector3i) -> void:
	if _soft.is_empty() or _sy0 != nest.y_lo:
		_sx = nest.nx + 2
		_sy = nest.hy() + 2
		_sy0 = nest.y_lo
		_soft = PackedFloat32Array()
		_soft.resize(_sx * _sy * (nest.nz + 2))
		a = Vector3i(-1, nest.y_lo - 1, -1)        # (laid out again whole: the soil was taken in deeper)
		b = Vector3i(nest.nx, nest.ny, nest.nz)
	a = a.clamp(Vector3i(-1, nest.y_lo - 1, -1), Vector3i(nest.nx, nest.ny, nest.nz))
	b = b.clamp(Vector3i(-1, nest.y_lo - 1, -1), Vector3i(nest.nx, nest.ny, nest.nz))
	for z in range(a.z, b.z + 1):
		for y in range(a.y, b.y + 1):
			var row := ((z + 1) * _sy + (y - _sy0 + 1)) * _sx + 1
			for x in range(a.x, b.x + 1):
				_soft[row + x] = nest.density(x, y, z)


## _floor_y() remembered per spot (a quarter-voxel grid), forgotten whenever the soil changes.
func _floor_cached(p: Vector3) -> float:
	var key := Vector3i(roundi(p.x * 4.0), roundi(p.y * 2.0), roundi(p.z * 4.0))
	var v = _floor_cache.get(key)
	if v == null:
		v = _floor_y(p)
		_floor_cache[key] = v
	return v


## Height of the soil surface (the floor) under a point near it, from the same density the soil mesh shows;
## p.y if no floor is found within reach.
func _floor_y(p: Vector3) -> float:
	var y := p.y + 0.8
	var dprev := _density_at(Vector3(p.x, y, p.z))
	for i in 10:
		var y2 := y - 0.2
		var d := _density_at(Vector3(p.x, y2, p.z))
		if d >= 0.5 and dprev < 0.5:
			return lerpf(y, y2, (0.5 - dprev) / maxf(d - dprev, 0.001))
		y = y2
		dprev = d
	return p.y


## Dev (--perf): adds the time since t0 to fprof[key]; returns now.
func _nprof(key: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	fprof[key] = fprof.get(key, 0) + now - t0
	return now


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


## The soil voxels as a 3D texture: the cut face (which parts of it are solid soil) and the ants' feet (the floor
## under them) read it.
func _upload_volume() -> void:
	_vol_dirty = false
	_vol_timer = 0.5
	var layers: Array[Image] = []
	var h: int = nest.hy()
	var slice: int = nest.nx * h
	for z in nest.nz:
		layers.append(Image.create_from_data(nest.nx, h, false, Image.FORMAT_R8, nest.rho.slice(z * slice, (z + 1) * slice)))
	if _vol == null or _vol.get_height() != h:
		_vol = ImageTexture3D.new()           # (new, or the soil taken in deeper: a volume of the new size)
		_vol.create(Image.FORMAT_R8, nest.nx, h, nest.nz, false, layers)
		_mat.set_shader_parameter("vol", _vol)
	else:
		_vol.update(layers)
	_set_vol_shape()
	_upload_foot_volume()


## Where the soil volumes sit (the layers held: nest.y_lo up), for every shader that reads them.
func _set_vol_shape() -> void:
	var size := Vector3(nest.nx, nest.hy(), nest.nz)
	var org := Vector3(0.0, nest.y_lo, 0.0)
	for m in [_mat] + _vol_mats:
		if m != null:
			m.set_shader_parameter("vol_size", size)
			m.set_shader_parameter("vol_org", org)
	if _xray_mat != null:
		_xray_mat.set_shader_parameter("box_min_y", float(nest.y_lo))
	if _ghost != null:
		(_ghost.mesh as BoxMesh).size = size
		_ghost.position = Vector3(nest.nx / 2.0 - 0.5, nest.y_lo + nest.hy() / 2.0 - 0.5, nest.nz / 2.0 - 0.5)


var _resized_seen := 0             # nest.resized when the volumes were last laid out
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
	var h: int = ny - y_lo
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
				for z in range(maxi(0, floori(c.z - e)), mini(nz, ceili(c.z + e) + 1)):
					for y in range(maxi(y_lo, floori(c.y - e)), mini(ny, ceili(c.y + e) + 1)):
						for x in range(maxi(0, floori(c.x - e)), mini(nx, ceili(c.x + e) + 1)):
							var v := int(clampf(0.6 + (r - Vector3(x, y, z).distance_to(c)), 0.0, 1.0) * 255.0)     # (0.6: its surface a touch outside the body - the feet on it, not in it)
							var ix := (z * h + y - y_lo) * nx + x
							if v > _foot_rho[ix]:
								_foot_rho[ix] = v
	var layers: Array[Image] = []
	var slice: int = nx * h
	for z in nz:
		layers.append(Image.create_from_data(nx, h, false, Image.FORMAT_R8, _foot_rho.slice(z * slice, (z + 1) * slice)))
	if _foot_vol == null or _foot_vol.get_height() != h:
		_foot_vol = ImageTexture3D.new()
		_foot_vol.create(Image.FORMAT_R8, nx, h, nz, false, layers)
		for m in _vol_mats:
			m.set_shader_parameter("vol", _foot_vol)
	else:
		_foot_vol.update(layers)


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


## Whether a nestmate can stand at cell c: open, with soil next to it - or the block's sides and bottom (the
## glass of a formicarium), but not the sky above it (ants walking the open top layer of the entrance crater hung
## upside down from the air, floating above the block).
func _walkable(c: Vector3i) -> bool:
	if not nest.is_open(c):
		return false
	var rho: PackedByteArray = nest.rho
	var nx: int = nest.nx
	var ny: int = nest.ny
	var nz: int = nest.nz
	var y_lo: int = nest.y_lo
	for d in DIRS:
		var n: Vector3i = c + d
		if n.y >= ny:
			continue                     # (the sky)
		if n.x < 0 or n.y < y_lo or n.z < 0 or n.x >= nx or n.z >= nz:
			return true                  # (the block's sides and bottom)
		if rho[(n.z * (ny - y_lo) + n.y - y_lo) * nx + n.x] >= nest.AIR:
			return true
	return false


func _holds(n: Vector3i) -> bool:
	if nest.inside(n):
		return not nest.is_open(n)
	return n.y < nest.ny                  # (outside: the sides and the bottom hold, the sky does not)


func _up_at(c: Vector3i) -> Vector3:
	var u := Vector3.ZERO
	var first := Vector3.ZERO
	for d in DIRS:
		var n := c + d
		if _holds(n):
			u -= Vector3(d)
			if first == Vector3.ZERO:
				first = -Vector3(d)
	if u.length_squared() > 0.01:
		return u.normalized()
	# soil on opposite sides (a narrow shaft or a slot) cancels out: it stands on one of them, not upright in the
	# air between them (an ant in a narrow shaft hung in its middle, feet reaching for nothing)
	return first if first != Vector3.ZERO else Vector3.UP


# ---------------------------------------------------------------- activities

const ACT_WALK := 0
const ACT_REST := 1
const ACT_DIG := 2
const ACT_ANTENNATE := 3
const ACT_GROOM := 4
const ACT_LAY := 5
const ACT_FEED := 6
const ACT_TAKE := 21            # taking a droplet from a nestmate (trophallaxis, the receiving side; shader 21)
const ACT_TEND := 7
const ACT_CARRY := 8
const ACT_TAKE_EGG := 17        # a founding queen curls her gaster under and takes the new egg (shader 17)
const ACT_EMERGE := 12          # a callow just out of its cocoon, legs still folded
const STILL_ACTS := [ACT_ANTENNATE, ACT_GROOM, ACT_FEED, ACT_TAKE]    # the ant stops walking while doing these


# ---------------------------------------------------------------- life-cycle moments
# The simulation reports each egg laid, larva pupating and worker eclosing (sim.events). At watchable
# speeds the nest view acts them out: the queen lays and an attendant (or, while founding, the queen
# herself) carries the egg to the pile; a nurse covers a spinning larva and carries the new cocoon
# up to the pupa chamber; nurses bite open a cocoon and a pale callow unfolds and stands up.

const MOUTH := Vector3(1.2, 0.32, 0.0)          # mandible tip in the ant model, before scaling
const GASTER_TIP := Vector3(-1.85, 0.25, 0.0)
const TIP_CURLED := Vector3(0.45, 0.12, 0.0)       # the gaster tip brought forward under the thorax (ACT_TAKE_EGG)
const MOUTH_LOW := Vector3(1.05, 0.12, 0.0)        # mandibles with the head bowed
# where her mandible tips are (worked out from the shader's head pose): bowed to take the egg (act 17: nod -0.55,
# body pitched -0.1 and raised 0.65 design units) and head up carrying it (act 8: nod +0.2)
const MOUTH_TAKE := Vector3(0.94, 0.10, 0.0)
const MOUTH_CARRY := Vector3(1.15, 0.33, 0.0)
const TIP_LICK := Vector3(1.185, 0.122, 0.0)       # her mandible tips with the head bowed to lick (ACT_TEND; from the mesh: tip 1.231, 0.333 at rest)


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
