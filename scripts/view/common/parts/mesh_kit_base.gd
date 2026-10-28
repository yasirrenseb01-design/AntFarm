extends RefCounted
## Small procedural mesh builder for the outworld props (prey, plants, stones, the spider).
## Shapes are added as blobs (stretched spheres), segments (cylinders with a rounded joint) and flat
## sheets; vertex colour carries the colour, and its alpha an optional part id (id / 16) that a
## shader can animate (the spider's legs).
## Mesh kit, layer 1 of 2 (split from scripts/view/common/mesh_kit.gd in v0.8.5): the builder (blobs,
## segments, sheets), Blender assets, and the scenery: stones, leaves, twigs, grass, the bean plant.
## Layers: parts/mesh_kit_base <- mesh_kit.
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _i := PackedInt32Array()
var part := 0
var _sphere: Array
var _sphere_lo: Array
var _cyl: Array


func _init() -> void:
	_sphere = _prim(12, 7)
	_sphere_lo = _prim(7, 4)
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
		_c.append(Color(col.r, col.g, col.b, part / 16.0))
	for idx in arr[Mesh.ARRAY_INDEX]:
		_i.append(base + idx)


func blob(c: Vector3, r: Vector3, col: Color, rot := Basis.IDENTITY, lo := false) -> void:
	_add(_sphere_lo if lo else _sphere, Transform3D(rot * Basis.from_scale(r), c), col)


## A tube along a curve lying in the x-y plane: radii[i] = (half height, half width) of the cross-section at
## spine[i], cols[i] its colour; `sides` vertices round each ring, the ends closed to a point. Much lighter
## than a row of blobs (a larva: ~250 vertices instead of ~1800).
func tube(spine: Array, radii: Array, cols: Array, sides := 10) -> void:
	var n := spine.size()
	var base := _v.size()
	for i in n:
		var p: Vector3 = spine[i]
		var tng: Vector3 = (spine[mini(i + 1, n - 1)] - spine[maxi(i - 1, 0)]).normalized()
		var up := Vector3(-tng.y, tng.x, 0.0)          # in the curve's plane, square to it
		var r: Vector2 = radii[i]
		var col: Color = cols[i]
		for k in sides:
			var a := TAU * k / sides
			var o := up * cos(a) * r.x + Vector3.BACK * sin(a) * r.y
			_v.append(p + o)
			_n.append((up * cos(a) / maxf(r.x, 0.01) + Vector3.BACK * sin(a) / maxf(r.y, 0.01)).normalized())
			_c.append(Color(col.r, col.g, col.b, part / 16.0))
	for i in n - 1:
		for k in sides:
			var a0 := base + i * sides + k
			var a1 := base + i * sides + (k + 1) % sides
			var b0 := a0 + sides
			var b1 := a1 + sides
			_i.append_array([a0, b0, a1, a1, b0, b1])
	# the two ends, closed to a point just beyond the last ring
	for e in [0, n - 1]:
		var p: Vector3 = spine[e]
		var out: Vector3 = (spine[e] - spine[1 if e == 0 else n - 2]).normalized()
		var tip := _v.size()
		_v.append(p + out * (radii[e] as Vector2).x * 0.8)
		_n.append(out)
		var col: Color = cols[e]
		_c.append(Color(col.r, col.g, col.b, part / 16.0))
		for k in sides:
			var a0: int = base + e * sides + k
			var a1: int = base + e * sides + (k + 1) % sides
			if e == 0:
				_i.append_array([tip, a0, a1])
			else:
				_i.append_array([tip, a1, a0])


func seg(a: Vector3, b: Vector3, r: float, col: Color, joint := true) -> void:
	var d := b - a
	if d.length_squared() < 1e-6:
		return
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_add(_cyl, Transform3D(Basis(x * r, y * d.length(), z * r), (a + b) * 0.5), col)
	if joint:
		_add(_sphere_lo, Transform3D(Basis.from_scale(Vector3.ONE * r * 1.05), b), col)


func chain(pts: Array, r0: float, r1: float, col: Color) -> void:
	for k in pts.size() - 1:
		var t := float(k) / maxf(1.0, pts.size() - 2)
		seg(pts[k], pts[k + 1], lerpf(r0, r1, t), col)


## A flat outline (in its own x/y plane) placed with xf, drawn from both sides; `lift(p)` bends it.
func sheet(outline: PackedVector2Array, xf: Transform3D, col: Color, lift := Callable(), flex := Callable()) -> void:
	var tris := Geometry2D.triangulate_polygon(outline)
	if tris.is_empty():
		return
	for side in [1.0, -1.0]:
		var base := _v.size()
		for p in outline:
			var h: float = lift.call(p) if lift.is_valid() else 0.0
			_v.append(xf * Vector3(p.x, h + (0.0 if side > 0.0 else -0.02), p.y))
			_n.append((xf.basis * Vector3(0, side, 0)).normalized())
			_c.append(Color(col.r, col.g, col.b, flex.call(p) if flex.is_valid() else part / 16.0))
		for k in range(0, tris.size(), 3):
			if side > 0.0:
				_i.append_array([base + tris[k], base + tris[k + 2], base + tris[k + 1]])
			else:
				_i.append_array([base + tris[k], base + tris[k + 1], base + tris[k + 2]])


func commit(smooth_normals := false) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_INDEX] = _i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if smooth_normals:
		var st := SurfaceTool.new()
		st.create_from(mesh, 0)
		st.generate_normals()
		return st.commit()
	return mesh


# ---------------------------------------------------------------- props (1 unit = 1.5 mm)

static func _new():
	return load("res://scripts/view/common/mesh_kit.gd").new()


static var _assets := {}


## A model built in Blender (tools/blender/build_props.py -> assets/models/<folder>/<name>.antmesh), or null.
## `name` includes the folder, e.g. "prey/aphid_adult".
static func asset(name: String) -> Mesh:
	if not _assets.has(name):
		_assets[name] = load("res://scripts/view/common/ant_model3d.gd").load_antmesh("res://assets/models/%s.antmesh" % name)
	return _assets[name]


const PLANT_VARIANTS := 3
const PLANT_STAGE_DAYS := [10.0, 25.0, 45.0]   # a plant's age (game days) at growth stages 1, 2, 3 (in flower)


## The growth stage (0 a young shoot ... 3 grown, in flower: tools/blender/props/plant.py) of a plant this many days
## old. [Inference: a broad bean flowers some weeks after it comes up - no study found for how many; v0.11.69]
static func plant_stage(age_days: float) -> int:
	var g := 0
	for d in PLANT_STAGE_DAYS:
		if age_days >= d:
			g += 1
	return g


## A field stone: a lumpy dome whose footprint follows the simulation's outline (in units, around 0).
static func rock(outline: PackedVector2Array, r: float, tone: float, seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := outline.size()
	var rings := 6
	var h := r * rng.randf_range(0.45, 0.7)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(0.27, 0.25, 0.23).lerp(Color(0.38, 0.34, 0.29), tone)
	var bumps := []
	for k in 6:
		bumps.append([rng.randf() * TAU, rng.randf_range(0.0, 1.0), rng.randf_range(-0.12, 0.12)])
	var pts := []
	for ring in rings + 1:
		var t := float(ring) / rings
		var phi := t * PI * 0.5
		var row := []
		for k in n:
			var o: Vector2 = outline[k]
			var a := o.angle()
			var rr := o.length() * pow(cos(phi), 0.65)
			var y := sin(phi) * h - 0.6
			for b in bumps:
				y += b[2] * r * sin(phi * 2.0) * maxf(0.0, cos(a - b[0]))
			row.append(Vector3(cos(a) * rr, y, sin(a) * rr))
		pts.append(row)
	for ring in rings:
		for k in n:
			var k2 := (k + 1) % n
			var a: Vector3 = pts[ring][k]
			var b: Vector3 = pts[ring][k2]
			var c: Vector3 = pts[ring + 1][k]
			var d: Vector3 = pts[ring + 1][k2]
			for p in [a, b, c, b, d, c]:
				var shade := 0.82 + 0.3 * clampf(p.y / h, 0.0, 1.0) + rng.randf_range(-0.05, 0.05)
				st.set_color(Color(base.r * shade, base.g * shade, base.b * shade))
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()


static func leaf(length: float, width: float, col: Color, curl: float) -> ArrayMesh:
	var k = _new()
	# a birch leaf (v0.11.71): broadest near its foot, drawn out to a point, the edge toothed (double-serrate)
	var outline := PackedVector2Array()
	var half := func(t: float) -> float:
		return pow(sin(t * PI), 0.75) * (1.2 - 0.85 * t) * (1.0 + 0.07 * sin(t * 46.0) * sin(t * PI))
	for i in 31:
		var t := i / 30.0
		outline.append(Vector2((t - 0.5) * length, -float(half.call(t)) * width))
	for i in range(29, 0, -1):
		var t := i / 30.0
		outline.append(Vector2((t - 0.5) * length, float(half.call(t)) * width))
	# dry leaves curl up a little at the edges and lift at the tip (the keeper, 2026-10-27: they stood up in a tall
	# hump, one half lit and the other dark, and the straight midrib stuck out under the lifted tip - now gentler, and
	# the midrib follows the leaf's own middle, the stalk a little past its foot)
	var lift := func(p: Vector2) -> float:
		return 0.18 + absf(p.y) * absf(p.y) / maxf(0.1, width) * (0.12 + curl * 0.3) + maxf(0.0, p.x / length) * 0.35
	k.sheet(outline, Transform3D.IDENTITY, col, lift,
		func(p: Vector2) -> float: return pow(clampf(p.x / length + 0.1, 0.0, 1.0), 2.0) * 0.08)
	var rib := []
	for i in 7:
		var x := lerpf(-length * 0.58, length * 0.42, i / 6.0)
		rib.append(Vector3(x, float(lift.call(Vector2(maxf(x, -length * 0.5), 0.0))) + 0.03, 0))
	k.chain(rib, 0.1, 0.05, col.darkened(0.3))
	return k.commit()


static func twig(length: float, seed_value: int) -> ArrayMesh:
	var k = _new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := Color(0.29, 0.2, 0.13)
	var a := Vector3(-length * 0.5, 0.5, 0)
	var pts := [a]
	for i in 4:
		pts.append(a + Vector3(length * (i + 1) / 4.0, 0.5 + rng.randf_range(-0.15, 0.15), rng.randf_range(-0.6, 0.6)))
	k.chain(pts, 0.85, 0.55, bark)
	var mid: Vector3 = pts[2]
	k.seg(mid, mid + Vector3(2.2, 0.3, 2.4), 0.4, bark)
	return k.commit()


## Grass blade: a long, tapering leaf folded along its midrib (V cross-section), curving over toward
## its tip. Vertex colour darkens toward the base; alpha carries how far the wind can bend each
## point (0 at the root, 1 at the tip) for shaders/sway.gdshader.
static func blade() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 8
	var rows := []
	for i in segs + 1:
		var t := float(i) / segs
		var w := 0.09 * (1.0 - t * 0.85) * (1.0 if t < 0.97 else 0.2)
		var p := Vector3(t * t * 0.55, t * (1.0 - 0.25 * t * t), 0)
		var fold := w * 0.45                      # the midrib stands proud of the leaf edges
		var shade := lerpf(0.55, 1.1, sqrt(t))
		rows.append([p + Vector3(-fold * 0.5, 0, -w), p + Vector3(fold, 0, 0), p + Vector3(-fold * 0.5, 0, w), shade, t])
	for i in segs:
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		for side in [[0, 1], [1, 2]]:
			var quad := [[a, side[0]], [b, side[0]], [a, side[1]], [a, side[1]], [b, side[0]], [b, side[1]]]
			for q in quad:
				var r: Array = q[0]
				var s: float = r[3] * (0.92 if q[1] == 1 else 1.0)     # midrib a shade darker
				st.set_color(Color(s, s, s, r[4] * r[4]))
				st.add_vertex(r[q[1]])
	st.generate_normals()
	return st.commit()


## Broad bean shoot (Vicia faba), a favourite host of the black bean aphid. Returns the stem line
## (local points, base at the origin) shared by the mesh, the aphids and the ants that climb it.
static func plant_stem(seed_value: int, stage := 3) -> Array:
	# the Blender shoots carry their own stem line, one per growth stage
	var path := "res://assets/models/plants/plant%d_%d.json" % [absi(seed_value) % PLANT_VARIANTS, clampi(stage, 0, 3)]
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			var pts := []
			for p in d.stem:
				pts.append(Vector3(p[0], p[1], p[2]))
			return pts
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var h := rng.randf_range(22.0, 28.0)
	var lean := Vector3(rng.randf_range(-1.6, 1.6), 0, rng.randf_range(-1.6, 1.6))
	var pts := []
	for i in 7:
		var t := i / 6.0
		pts.append(Vector3(0, h * t, 0) + lean * t * t)
	return pts


static func stem_at(pts: Array, y: float) -> Vector3:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		if y <= b.y or i == pts.size() - 2:
			return a.lerp(b, clampf((y - a.y) / maxf(0.001, b.y - a.y), 0.0, 1.0))
	return pts[-1]


const STEM_R := 0.55


static func aphid_plant(seed_value: int, stage := 3) -> Mesh:
	var m := asset("plants/plant%d_%d" % [absi(seed_value) % PLANT_VARIANTS, clampi(stage, 0, 3)])
	if m != null:
		return m
	var k = _new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 17
	var pts := plant_stem(seed_value)
	var h: float = pts[-1].y
	var stem := Color(0.3, 0.42, 0.2)
	k.part = 0
	k.chain(pts, STEM_R, STEM_R * 0.7, stem)
	# alternate compound leaves: a short petiole with two or three pairs of oval leaflets
	var nodes := 5
	for n in nodes:
		var y := h * (0.18 + 0.72 * n / float(nodes - 1))
		var at := stem_at(pts, y)
		var ang := n * 2.4 + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var size := lerpf(1.0, 0.55, float(n) / nodes)
		k.blob(at, Vector3.ONE * STEM_R * 1.35, stem.darkened(0.1), Basis.IDENTITY, true)   # node
		var tip := at + dir * 3.2 * size + Vector3(0, 1.6 * size, 0)
		k.seg(at, tip, 0.2, stem)
		var col := Color(0.19, 0.33, 0.13).lerp(Color(0.29, 0.44, 0.18), rng.randf())
		for pair in 2 + (1 if n < 2 else 0):
			var base := at.lerp(tip, 0.45 + 0.3 * pair) + Vector3(0, 0.1, 0)
			for side in [-1.0, 1.0]:
				var la: float = ang + side * 1.1 + rng.randf_range(-0.15, 0.15)
				var length := rng.randf_range(4.5, 6.0) * size
				var outline := PackedVector2Array()
				for j in 12:
					var s := TAU * j / 12.0
					outline.append(Vector2((cos(s) + 1.0) * 0.5 * length, sin(s) * length * 0.32))
				var b := Basis(Vector3.UP, -la) * Basis(Vector3.BACK, rng.randf_range(0.1, 0.4))
				k.sheet(outline, Transform3D(b, base), col, func(p: Vector2) -> float:
					return -p.x * p.x * 0.02 + absf(p.y) * 0.3,
					func(p: Vector2) -> float: return clampf(p.x / length, 0.0, 1.0) * 0.35)
	# the growing tip: young leaves still folded around the shoot
	var top: Vector3 = pts[-1]
	for i in 3:
		var a := i * 2.1
		k.blob(top + Vector3(cos(a) * 0.5, 0.6 + i * 0.3, sin(a) * 0.5), Vector3(0.5, 1.3, 0.35), Color(0.42, 0.6, 0.27),
			Basis(Vector3.UP, a) * Basis(Vector3.BACK, 0.35))
	return k.commit()


## Where the colony sits: black bean aphids pack the stem, head down
## with their mouthparts in the stem. Each entry: [local transform, kind (0 adult, 1 nymph, 2 winged)].
static func aphid_spots(seed_value: int, stage := 3) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 99
	var pts := plant_stem(seed_value, stage)
	var h: float = pts[-1].y
	var stem_r: float = STEM_R * [0.62, 0.78, 0.92, 1.0][clampi(stage, 0, 3)]    # (plant.py PL_STAGE_R)
	var out := []
	var placed := []                  # [centre, size]: side by side on the stem, never one inside another
	for i in 140:
		if out.size() >= 34:
			break
		# most of the colony packs the lower stem (where the ants tend it), the rest the growing tip
		var y := rng.randf_range(1.6, minf(9.0, h * 0.55)) if rng.randf() < 0.7 else h * rng.randf_range(0.6, 0.97)
		var a := rng.randf() * TAU
		var kind := 0 if rng.randf() < 0.55 else 1
		if rng.randf() < 0.06:
			kind = 2
		var s := rng.randf_range(0.9, 1.1) if kind != 1 else rng.randf_range(0.45, 0.75)
		var outward := Vector3(cos(a), 0, sin(a))
		var p := stem_at(pts, y) + outward * (stem_r * (1.0 - 0.3 * y / maxf(h, 1.0)) * 0.95 + 0.03 * s)   # (feet on the tapering stem)
		var clear := true
		for q in placed:
			# (an adult is ~1.35 long and ~0.75 wide, lying head down along the stem)
			var d: Vector3 = p - q[0]
			var k: float = (s + float(q[1])) * 0.5
			if pow(d.y / (1.25 * k), 2.0) + (d.x * d.x + d.z * d.z) / pow(0.72 * k, 2.0) < 1.0:
				clear = false
				break
		if not clear:
			continue
		placed.append([p, s])
		var down := Vector3(0, -1, 0).rotated(outward.cross(Vector3.UP).normalized(), rng.randf_range(-0.35, 0.35))
		var x := down
		var yv := outward
		out.append([Transform3D(Basis(x, yv, x.cross(yv)).scaled(Vector3.ONE * s), p), kind])
	return out
