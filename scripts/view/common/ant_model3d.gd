extends RefCounted
## Procedural 3D model of a Lasius niger worker (or queen), facing +x with feet at y = 0.
## One unit of the "design space" below ≈ 0.5 mm; the whole worker is scaled to ≈ 4.2 mm (2.8 voxels).
##
## Species traits modelled: heart-shaped head (concave rear margin) with black compound eyes,
## toothed reddish mandibles, elbowed 12-segment antennae (long scape + 11-bead funiculus),
## rounded mesosoma in three humps, a single upright scale-like petiole, a 4-tergite gaster with a
## dull pubescent sheen, and legs/antennae a shade lighter brown than the body.
##
## Vertex colours are multipliers on the per-ant instance colour: body 0.55 leaves headroom so the
## lighter limbs and the reddish mandibles can be brighter than the body.
## Vertex colour ALPHA carries a body-part id (id / 16) that shaders/ant.gdshader uses to animate
## each part around its joint: 0 trunk, 1 head, 2/3 left/right antenna, 4-9 legs (front-left,
## front-right, mid-left, mid-right, hind-left, hind-right), 10 gaster, 11 mandibles.

const K := 0.34          # design units -> voxels (worker length ≈ 8.2 units ≈ 2.8 voxels)
const BODY := Color(0.55, 0.55, 0.55)
const LIMB := Color(1.0, 0.92, 0.85)
const MANDIBLE := Color(1.0, 0.72, 0.45)
const EYE := Color(0.06, 0.06, 0.06)

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _part := 0
var _i := PackedInt32Array()
var _sphere_hi: Array
var _sphere_lo: Array
var _cyl: Array


func _init() -> void:
	_sphere_hi = _prim(12, 7)
	_sphere_lo = _prim(8, 4)
	var c := CylinderMesh.new()
	c.top_radius = 1.0
	c.bottom_radius = 1.0
	c.height = 1.0
	c.radial_segments = 6
	c.rings = 1
	_cyl = c.get_mesh_arrays()


func _prim(seg: int, rings: int) -> Array:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = seg
	s.rings = rings
	return s.get_mesh_arrays()


func _add(arr: Array, xf: Transform3D, col: Color) -> void:
	var base := _v.size()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var nb := xf.basis.inverse().transposed()
	for k in verts.size():
		_v.append(xf * verts[k])
		_n.append((nb * norms[k]).normalized())
		_c.append(Color(col.r, col.g, col.b, _part / 16.0))
	for idx in arr[Mesh.ARRAY_INDEX]:
		_i.append(base + idx)


func _blob(c: Vector3, r: Vector3, col := BODY, rot := Basis.IDENTITY, lo := false) -> void:
	_add(_sphere_lo if lo else _sphere_hi, Transform3D(rot * Basis.from_scale(r * K), c * K), col)


func _seg(a: Vector3, b: Vector3, r: float, col := LIMB) -> void:
	a *= K
	b *= K
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_add(_cyl, Transform3D(Basis(x * r * K, y * d.length(), z * r * K), (a + b) * 0.5), col)
	_add(_sphere_lo, Transform3D(Basis.from_scale(Vector3.ONE * r * K * 1.05), b), col)   # rounded joint


func _chain(pts: Array, r0: float, r1: float, col := LIMB) -> void:
	for k in pts.size() - 1:
		var t := float(k) / maxf(1.0, pts.size() - 2)
		_seg(pts[k], pts[k + 1], lerpf(r0, r1, t), col)


## swing: leg tripod phase (-1..1). detailed=false gives a light model for far views.
func build(swing := 0.0, queen := false, detailed := true) -> ArrayMesh:
	var lo := not detailed
	# --- gaster: four overlapping tergites, the queen's swollen with ovaries
	_part = 10
	var gs := 1.35 if queen else 1.0
	var gx := -2.75 if queen else -2.5
	_blob(Vector3(gx, 1.05, 0), Vector3(1.9, 1.32, 1.42) * gs, BODY, Basis.IDENTITY, lo)
	if detailed:
		for t in 4:
			var x := gx + (1.1 - t * 0.75) * gs
			var r := (1.05 - absf(t - 1.2) * 0.18) * gs
			_blob(Vector3(x, 1.08 + 0.04 * t, 0), Vector3(0.42, r * 1.27, r * 1.36), BODY * 1.04)
	_part = 0
	# --- petiole: one upright scale
	_blob(Vector3(-0.72, 1.18, 0), Vector3(0.2, 0.7, 0.5), BODY, Basis(Vector3.BACK, -0.25), lo)
	# --- mesosoma: pronotum, mesonotum, propodeum (the queen's thorax is deeper: flight muscles)
	var ms := 1.3 if queen else 1.0
	_blob(Vector3(0.75, 1.2, 0), Vector3(0.78, 0.62 * ms, 0.64), BODY, Basis.IDENTITY, lo)
	_blob(Vector3(0.05, 1.28, 0), Vector3(0.6, 0.55 * ms, 0.52), BODY, Basis.IDENTITY, lo)
	_blob(Vector3(-0.38, 1.0, 0), Vector3(0.45, 0.48 * ms, 0.5), BODY, Basis.IDENTITY, lo)
	_part = 1
	# --- head: heart-shaped from above (two rear lobes), eyes, mandibles, clypeus
	_blob(Vector3(2.15, 1.15, 0), Vector3(0.95, 0.75, 0.88), BODY, Basis.IDENTITY, lo)
	if detailed:
		for side in [-1.0, 1.0]:
			_blob(Vector3(1.55, 1.15, 0.42 * side), Vector3(0.55, 0.66, 0.5))
			_blob(Vector3(2.35, 1.32, 0.8 * side), Vector3(0.24, 0.3, 0.14), EYE)
			# mandible: a flat blade angled inward, toothed edge suggested by two small bumps
			var mb := Basis(Vector3.UP, -0.55 * side)
			_part = 11
			_blob(Vector3(3.05, 0.9, 0.38 * side), Vector3(0.62, 0.12, 0.22), MANDIBLE, mb)
			_blob(Vector3(3.35, 0.9, 0.18 * side), Vector3(0.12, 0.1, 0.1), MANDIBLE)
			_part = 1
		_blob(Vector3(2.85, 1.05, 0), Vector3(0.35, 0.3, 0.45))       # clypeus
	# --- antennae: long scape, elbow, 11-bead funiculus curving forward
	for side in [-1.0, 1.0]:
		_part = 2 if side < 0.0 else 3
		var root := Vector3(2.7, 1.45, 0.38 * side)
		var elbow := Vector3(3.45, 2.45, 1.25 * side)
		_seg(root, elbow, 0.11)
		var fun := [elbow]
		var n := 11 if detailed else 3
		for b in n:
			var t := float(b + 1) / n
			fun.append(elbow + Vector3(1.55 * t, -0.95 * t + 0.35 * sin(t * PI), (0.45 * t) * side))
		_chain(fun, 0.1, 0.12)
	# --- legs: coxa, femur, tibia, tarsus in two tripods
	var legs := [[0.85, 0.75, 1.8], [0.2, 0.1, -0.1], [-0.4, -0.65, -2.2]]
	for li in legs.size():
		var L: Array = legs[li]
		for side in [-1.0, 1.0]:
			_part = 4 + li * 2 + (0 if side < 0.0 else 1)
			var sw: float = swing if ((li % 2 == 0) == (side < 0.0)) else -swing
			var hip := Vector3(L[0], 0.85, 0.42 * side)
			var coxa := Vector3(L[0] + 0.1, 0.55, 0.85 * side)
			var knee := Vector3(L[0] + L[1] + sw * 0.35, 1.75 + absf(sw) * 0.25, 2.05 * side)
			var ankle := Vector3(L[0] + L[2] * 0.85 + sw * 0.7, 0.35, 2.9 * side)
			var foot := Vector3(L[0] + L[2] + sw * 0.85, 0.0, 3.15 * side)
			if detailed:
				_seg(hip, coxa, 0.2)
				_seg(coxa, knee, 0.17)           # femur
				_seg(knee, ankle, 0.12)          # tibia
				_chain([ankle, ankle.lerp(foot, 0.5) + Vector3(0, 0.05, 0), foot], 0.08, 0.07)   # tarsus
			else:
				_seg(hip, knee, 0.17)
				_seg(knee, foot, 0.12)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_INDEX] = _i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static var _cache := {}
# appendage colour relative to the body tint (see limb_gain in shaders/ant.gdshader)
const WORKER_LIMBS := Vector3(1.7, 1.45, 1.25)
const QUEEN_LIMBS := Vector3(5.6, 3.6, 1.8)     # (on her near-black body: dark amber legs, as in reference/ photos)


## The model sculpted in Blender (tools/blender/build_ant.py -> assets/models/ants/*.antmesh) when present,
## otherwise the procedural one below.
static func make(swing := 0.0, queen := false, detailed := true) -> ArrayMesh:
	var key := "%s_%s" % ["queen" if queen else "worker", "hi" if detailed else "lo"]
	if not _cache.has(key):
		var m := load_antmesh("res://assets/models/ants/%s.antmesh" % key)
		if m == null:
			var b = load("res://scripts/view/common/ant_model3d.gd").new()
			m = b.build(swing, queen, detailed)
		_cache[key] = m
	return _cache[key]


## File layout: "ANTM", vertex count, index count (u32), then per vertex 10 floats
## (position, normal, colour RGBA), then u32 indices. "ANT2" (the ants) adds an 11th float per vertex:
## the leg segment (1 coxa, 2 femur, 3 tibia, 4 tarsus), passed to the shader in UV.x.
static func load_antmesh(path: String) -> ArrayMesh:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var magic := f.get_buffer(4).get_string_from_ascii()
	if magic != "ANTM" and magic != "ANT2":
		return null
	var stride := 11 if magic == "ANT2" else 10
	var nv := f.get_32()
	var ni := f.get_32()
	var data := f.get_buffer(nv * stride * 4).to_float32_array()
	var idx := f.get_buffer(ni * 4).to_int32_array()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	v.resize(nv)
	n.resize(nv)
	c.resize(nv)
	var uv := PackedVector2Array()
	if stride == 11:
		uv.resize(nv)
	for i in nv:
		var o := i * stride
		v[i] = Vector3(data[o], data[o + 1], data[o + 2])
		n[i] = Vector3(data[o + 3], data[o + 4], data[o + 5])
		c[i] = Color(data[o + 6], data[o + 7], data[o + 8], data[o + 9])
		if stride == 11:
			uv[i] = Vector2(data[o + 10], 0.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	if stride == 11:
		arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ---------------------------------------------------------------- gait (kept in step with shaders/ants/ant.gdshader)
# Ants speed up by taking both longer and quicker strides: stride length ~ speed^0.45 (Zollikofer 1994,
# Reinhardt & Blickhan 2014); a laden ant takes shorter steps; a running ant spends less of each step on
# the ground (duty factor below 0.5: a moment with no tripod down).
const STRIDE_A := 1.3          # design units: half the backward sweep of a planted foot at full walking pace (stride ≈ 0.6 body length)


## How long the strides are for a pace (1 = the species' normal walk) and whether the ant is laden.
static func stride_scale(pace: float, laden: bool) -> float:
	return clampf(pow(maxf(pace, 0.05), 0.45), 0.4, 1.5) * (0.75 if laden else 1.0)


## Fraction of each step a foot spends on the ground.
static func duty(s: float) -> float:
	return lerpf(0.55, 0.42, clampf((s - 1.0) / 0.5, 0.0, 1.0))


## Body travel per full step cycle, in mesh units: while planted a foot sweeps back 2A as the body moves 2A.
## The shader's INSTANCE_CUSTOM.x: the gait phase (radians, below 512) + 512 x a code for how the body is bent
## at its joints to lie on the ground (ant_core.gdshaderinc): 0 none, else 1 + gaster + 21 x head, each in
## 21 steps of 0.04 radians from -0.4 (gaster: tip raised +; head: raised +).
static func gait_x(gait: float, bend: Vector2) -> float:
	if bend == Vector2.ZERO:
		return gait
	var g := clampi(roundi(bend.x / 0.06) + 10, 0, 20)   # (steps of 0.06 rad: -0.6 .. 0.6)
	var h := clampi(roundi(bend.y / 0.06) + 10, 0, 20)
	return gait + 512.0 * float(1 + g + 21 * h)


## How far (pixels) a click at sp is from the body of an ant drawn at xf: the distance to the line from its head
## to its gaster tip on screen, less half the body's width there (with a finger's breadth to spare: small on screen
## it still takes a near miss) - 0 or less is on the ant. `a`, `b`: its head and tail end (model units).
static func screen_gap(cam: Camera3D, xf: Transform3D, sp: Vector2, a := Vector3(1.0, 0.35, 0), b := Vector3(-1.05, 0.35, 0), width := 0.25) -> float:
	var pa := xf * a
	var pb := xf * b
	if cam.is_position_behind(pa) or cam.is_position_behind(pb):
		return INF
	var sa := cam.unproject_position(pa)
	var ab := cam.unproject_position(pb) - sa
	var t := clampf((sp - sa).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return sp.distance_to(sa + ab * t) - maxf(ab.length() * width, 12.0)


## The shader's INSTANCE_CUSTOM.z: the animation clock (seconds, kept below 600) + 600 x a code for how the body
## is bent sideways round a turn: 0 none, else 11 + steps of 0.04 radians (head turned in, gaster swung out).
static func clock_z(clock: float, lat: float) -> float:
	var z := fmod(clock, 600.0)
	if absf(lat) < 0.02:
		return z
	return z + 600.0 * float(clampi(roundi(lat / 0.04) + 11, 1, 21))


static func stride_len(s: float) -> float:
	return 2.0 * STRIDE_A * s * K / duty(s)


## The shader's INSTANCE_CUSTOM.w: whole part = stride scale x 100, fraction = how much it is walking.
## turn: the share of the motion that is turning on the spot, signed (+ = anticlockwise seen from above).
static func gait_w(mv: float, s: float, turn := 0.0) -> float:
	var tc := roundi(clampf(absf(turn), 0.0, 1.0) * 8.0) + (9 if turn < 0.0 else 0)
	return float(tc) * 1000.0 + floorf(s * 100.0) + clampf(mv, 0.0, 0.999)


## Instance colour for a body colour (vertex colours carry the 0.55 body multiplier).
static func tint(body: Color) -> Color:
	return Color(minf(1.0, body.r / 0.55), minf(1.0, body.g / 0.55), minf(1.0, body.b / 0.55), 1.0)


const BODY_LIFT := 1.35          # (v0.11.1, the player: outdoors a touch too black, in the nest too brown - the same now)

## An ant's colour for the instance colour of the 3D views, the same in the nest and the outworld: linear (the
## shaders take COLOR as it is; in daylight the sRGB value bleached them grey, and the nest, which used it, drew
## them brown), lifted a little.
static func body_linear(body: Color) -> Color:
	var l := tint(body).srgb_to_linear()
	return Color(minf(1.0, l.r * BODY_LIFT), minf(1.0, l.g * BODY_LIFT), minf(1.0, l.b * BODY_LIFT), 1.0)


# ---------------------------------------------------------------- easing from one activity's pose to the next
# The shader picks a pose per activity id; switching ids outright snaps the body (head, gaster, legs) to the
# new pose in one frame. INSTANCE_CUSTOM.y therefore carries the pose being left too:
#   whole part = activity code (act + 100 if full, < 128) + 128 x the previous code,
#   fraction   = how much of the previous pose is still showing (eased 1 -> 0 over ACT_BLEND seconds).
# A plain integer (no previous, fraction 0) is the old encoding and still works.
const ACT_BLEND := 0.45          # seconds (animation clock) to ease from one pose into the next
const QUEEN_BLEND := 1.1         # the queen: a heavy body, her big gaster swung slowly from one pose to the next


## Updates the easing state `st` (x = current code, y = previous code, z = clock when it changed) for
## this frame's code; returns the new state. Start from Vector3(-1, 0, 0).
static func act_step(st: Vector3, code: int, clock: float, blend := ACT_BLEND) -> Vector3:
	if st.x < 0.0:
		return Vector3(code, code, clock - blend)
	if int(st.x) == code:
		return st
	# changed again while still easing: carry on from whichever pose is showing more
	var from := st.x if act_left(st, clock, blend) < 0.5 else st.y
	return Vector3(code, from, clock)


## How much of the previous pose still shows (1 -> 0).
static func act_left(st: Vector3, clock: float, blend := ACT_BLEND) -> float:
	if clock < st.z:
		return 0.0                   # the clock was reset (the ant was placed anew)
	var u := clampf((clock - st.z) / blend, 0.0, 1.0)
	return 1.0 - u * u * (3.0 - 2.0 * u)


## The shader's INSTANCE_CUSTOM.y for an easing state.
static func act_y(st: Vector3, clock: float, blend := ACT_BLEND) -> float:
	var left := act_left(st, clock, blend)
	if left <= 0.001 or int(st.y) == int(st.x):
		return st.x
	return st.x + 128.0 * st.y + minf(left, 0.99)
