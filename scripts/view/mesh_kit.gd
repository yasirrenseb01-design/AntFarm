extends RefCounted
## Small procedural mesh builder for the outworld props (prey, plants, stones, the spider).
## Shapes are added as blobs (stretched spheres), segments (cylinders with a rounded joint) and flat
## sheets; vertex colour carries the colour, and its alpha an optional part id (id / 16) that a
## shader can animate (the spider's legs).

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
func sheet(outline: PackedVector2Array, xf: Transform3D, col: Color, lift := Callable()) -> void:
	var tris := Geometry2D.triangulate_polygon(outline)
	if tris.is_empty():
		return
	for side in [1.0, -1.0]:
		var base := _v.size()
		for p in outline:
			var h: float = lift.call(p) if lift.is_valid() else 0.0
			_v.append(xf * Vector3(p.x, h + (0.0 if side > 0.0 else -0.02), p.y))
			_n.append((xf.basis * Vector3(0, side, 0)).normalized())
			_c.append(Color(col.r, col.g, col.b, part / 16.0))
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
	return load("res://scripts/view/mesh_kit.gd").new()


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
	var outline := PackedVector2Array()
	for i in 11:
		var t := i / 10.0
		outline.append(Vector2((t - 0.5) * length, -sin(t * PI) * width * (1.0 - 0.25 * t)))
	for i in range(9, 0, -1):
		var t := i / 10.0
		outline.append(Vector2((t - 0.5) * length, sin(t * PI) * width * (1.0 - 0.25 * t)))
	# dry leaves curl up at the edges and lift at the tip
	k.sheet(outline, Transform3D.IDENTITY, col, func(p: Vector2) -> float:
		return 0.18 + absf(p.y) * absf(p.y) / maxf(0.1, width) * (0.35 + curl) + maxf(0.0, p.x / length) * 0.6)
	k.seg(Vector3(-length * 0.55, 0.2, 0), Vector3(length * 0.45, 0.22, 0), 0.12, col.darkened(0.3), false)
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


## Grass blade: a tapered, bent ribbon standing up from the ground.
static func blade() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 5
	var prev := []
	for i in segs + 1:
		var t := float(i) / segs
		var w := 0.35 * (1.0 - t)
		var p := Vector3(t * t * 0.45, t, 0)
		var row := [p + Vector3(0, 0, -w), p + Vector3(0, 0, w)]
		if not prev.is_empty():
			for v in [prev[0], row[0], prev[1], prev[1], row[0], row[1]]:
				st.set_normal(Vector3(-1, 0.3, 0).normalized())
				st.add_vertex(v)
		prev = row
	return st.commit()


## A sprig of a host plant with an aphid colony on the lower stem (the ants milk them from the ground).
static func aphid_plant(seed_value: int) -> ArrayMesh:
	var k = _new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var stem := Color(0.3, 0.45, 0.17)
	var top := Vector3(rng.randf_range(-1, 1), rng.randf_range(16, 22), rng.randf_range(-1, 1))
	var pts := [Vector3.ZERO]
	for i in 4:
		var t := (i + 1) / 4.0
		pts.append(Vector3(top.x * t + sin(t * 3.0) * 0.6, top.y * t, top.z * t))
	k.chain(pts, 0.75, 0.4, stem)
	for i in 7:
		var t := rng.randf_range(0.2, 1.0)
		var at: Vector3 = pts[0].lerp(top, t)
		var ang := rng.randf() * TAU
		var length := rng.randf_range(7, 11) * (1.2 - t * 0.4)
		var col := Color(0.26, 0.45, 0.16).lerp(Color(0.43, 0.6, 0.24), rng.randf())
		var b := Basis(Vector3.UP, ang) * Basis(Vector3.BACK, rng.randf_range(0.15, 0.5))
		var outline := PackedVector2Array()
		for j in 9:
			var s := j / 8.0
			outline.append(Vector2(s * length, -sin(s * PI) * length * 0.3))
		for j in range(7, 0, -1):
			var s := j / 8.0
			outline.append(Vector2(s * length, sin(s * PI) * length * 0.3))
		k.sheet(outline, Transform3D(b, at), col, func(p: Vector2) -> float:
			return -p.x * p.x * 0.012 + absf(p.y) * 0.25)
	return k.commit()


## The aphids themselves: soft green pear-shaped bugs with cornicles and long legs.
static func aphid() -> ArrayMesh:
	var k = _new()
	var green := Color(0.55, 0.72, 0.3)
	k.blob(Vector3(0, 0.45, 0), Vector3(0.9, 0.55, 0.55), green)
	k.blob(Vector3(0.75, 0.42, 0), Vector3(0.3, 0.28, 0.3), green.darkened(0.15), Basis.IDENTITY, true)
	for side in [-1.0, 1.0]:
		k.seg(Vector3(-0.6, 0.7, 0.25 * side), Vector3(-0.95, 0.95, 0.3 * side), 0.07, green.darkened(0.4), false)
		for x in [0.4, 0.0, -0.4]:
			k.seg(Vector3(x, 0.3, 0.3 * side), Vector3(x + 0.1, 0.0, 0.85 * side), 0.05, green.darkened(0.35), false)
	return k.commit()


## A dead field cricket lying on its side; `left` (0..1) is how much of it is still there.
static func cricket(left: float, rotten: bool) -> ArrayMesh:
	var k = _new()
	var body := Color(0.2, 0.13, 0.07)
	var dark := Color(0.09, 0.06, 0.04)
	if rotten:
		body = body.lerp(Color(0.33, 0.35, 0.25), 0.5)
		dark = dark.lerp(Color(0.22, 0.24, 0.18), 0.5)
	var abd := maxf(0.35, left)
	k.blob(Vector3(-1.6, 1.7, 0), Vector3(3.6 * abd, 1.6 * abd, 1.7 * abd), body)     # abdomen
	k.blob(Vector3(2.0, 1.9, 0), Vector3(1.5, 1.4, 1.6), body.lightened(0.05))        # pronotum
	k.blob(Vector3(3.8, 1.8, 0), Vector3(1.2, 1.3, 1.3), dark)                          # head
	for side in [-1.0, 1.0]:
		k.blob(Vector3(4.3, 2.3, 0.75 * side), Vector3(0.35, 0.35, 0.3), Color(0.03, 0.02, 0.02))
		k.chain([Vector3(4.6, 2.4, 0.4 * side), Vector3(7.0, 2.6, 1.6 * side), Vector3(11.0, 1.4, 3.0 * side)], 0.1, 0.06, dark)
		k.seg(Vector3(-4.6 * abd, 1.8, 0.3 * side), Vector3(-6.8 * abd, 1.6, 1.2 * side), 0.12, dark)   # cerci
		if left > 0.3:
			# big jumping hind legs: thick femur, thin tibia
			k.blob(Vector3(-1.0, 2.2, 1.7 * side), Vector3(2.6, 0.75, 0.55), dark, Basis(Vector3.BACK, 0.35))
			k.chain([Vector3(-3.3, 1.4, 1.9 * side), Vector3(-5.6, 0.25, 2.3 * side), Vector3(-6.3, 0.1, 2.6 * side)], 0.22, 0.14, dark)
		if left > 0.6:
			for x in [2.6, 1.0]:
				k.chain([Vector3(x, 1.0, 0.9 * side), Vector3(x + 0.6, 0.7, 2.0 * side), Vector3(x + 1.0, 0.05, 2.6 * side)], 0.16, 0.1, dark)
	k.blob(Vector3(-1.0, 2.9, 0), Vector3(3.0 * abd, 0.4, 1.4 * abd), Color(0.32, 0.23, 0.13))   # folded wings
	return k.commit()


static func fly(left: float) -> ArrayMesh:
	var k = _new()
	var body := Color(0.16, 0.16, 0.15)
	var s := 0.6 + 0.4 * left
	k.blob(Vector3(-0.8, 0.9, 0) * s, Vector3(1.4, 0.8, 0.9) * s, body)
	k.blob(Vector3(0.6, 1.0, 0) * s, Vector3(0.8, 0.75, 0.75) * s, body.lightened(0.08))
	k.blob(Vector3(1.5, 0.95, 0) * s, Vector3(0.55, 0.65, 0.75) * s, body)
	for side in [-1.0, 1.0]:
		k.blob(Vector3(1.65, 1.15, 0.45 * side) * s, Vector3(0.3, 0.35, 0.3) * s, Color(0.5, 0.1, 0.06))
		for x in [-0.2, 0.4, 0.9]:
			k.chain([Vector3(x, 0.6, 0.3 * side) * s, Vector3(x + 0.3, 0.7, 1.2 * side) * s, Vector3(x + 0.2, 0.0, 1.6 * side) * s], 0.06, 0.05, body)
	return k.commit()


static func fly_wings() -> ArrayMesh:
	var k = _new()
	for side in [-1.0, 1.0]:
		var outline := PackedVector2Array()
		for j in 12:
			var a := TAU * j / 12.0
			outline.append(Vector2(cos(a) * 1.8 - 1.2, sin(a) * 0.75))
		k.sheet(outline, Transform3D(Basis(Vector3.UP, 0.45 * side), Vector3(0.2, 1.75, 0.4 * side)), Color(0.85, 0.9, 1.0))
	return k.commit()


## Wolf spider (Lycosidae): hairy brown body with a pale median stripe, eight long legs.
## Part ids for shaders/spider.gdshader: 0 body, 1-4 left legs front to back, 5-8 right legs.
static func spider() -> ArrayMesh:
	var k = _new()
	var body := Color(0.27, 0.19, 0.12)
	var pale := Color(0.55, 0.45, 0.32)
	var leg := Color(0.22, 0.16, 0.11)
	k.part = 0
	k.blob(Vector3(-3.4, 2.1, 0), Vector3(3.3, 2.3, 2.5), body)                 # abdomen
	k.blob(Vector3(-2.6, 3.2, 0), Vector3(2.3, 1.2, 0.6), pale.darkened(0.2))  # dorsal pattern
	for x in [-2.2, -3.4, -4.6]:
		for side in [-1.0, 1.0]:
			k.blob(Vector3(x, 3.0, 1.2 * side), Vector3(0.45, 0.4, 0.35), pale, Basis.IDENTITY, true)
	k.blob(Vector3(1.6, 2.2, 0), Vector3(2.5, 1.5, 2.0), body.darkened(0.1))   # cephalothorax
	k.blob(Vector3(1.6, 3.0, 0), Vector3(2.0, 0.7, 0.45), pale)                # median stripe
	for e in [Vector3(3.7, 3.0, 0.45), Vector3(3.7, 3.0, -0.45), Vector3(3.2, 3.5, 0.75), Vector3(3.2, 3.5, -0.75)]:
		k.blob(e, Vector3(0.32, 0.32, 0.32), Color(0.02, 0.02, 0.02), Basis.IDENTITY, true)
	for side in [-1.0, 1.0]:
		k.chain([Vector3(3.6, 2.0, 0.6 * side), Vector3(4.6, 1.8, 1.1 * side), Vector3(5.0, 0.9, 0.9 * side)], 0.3, 0.25, leg)  # pedipalps
		k.blob(Vector3(4.0, 1.4, 0.35 * side), Vector3(0.45, 0.6, 0.35), Color(0.12, 0.08, 0.05))                          # chelicerae
	var spread := [0.55, 1.15, 1.9, 2.5]
	var lens := [9.0, 8.0, 8.5, 10.5]
	for li in 4:
		for side in [-1.0, 1.0]:
			k.part = 1 + li + (0 if side < 0.0 else 4)
			var a: float = spread[li]
			var dir := Vector3(cos(a), 0, sin(a) * side)
			var hip := Vector3(2.4 - li * 0.75, 1.9, 0.9 * side)
			var knee: Vector3 = hip + dir * lens[li] * 0.45 + Vector3(0, 3.0, 0)
			var foot: Vector3 = hip + dir * lens[li] + Vector3(0, -1.9, 0)
			k.chain([hip, knee, knee.lerp(foot, 0.6) + Vector3(0, 0.4, 0), foot], 0.42, 0.22, leg)
	return k.commit()
