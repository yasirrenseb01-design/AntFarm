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
		return 0.18 + absf(p.y) * absf(p.y) / maxf(0.1, width) * (0.35 + curl) + maxf(0.0, p.x / length) * 0.6,
		func(p: Vector2) -> float: return pow(clampf(p.x / length + 0.1, 0.0, 1.0), 2.0) * 0.15)
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
static func plant_stem(seed_value: int) -> Array:
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


static func aphid_plant(seed_value: int) -> ArrayMesh:
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
static func aphid_spots(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 99
	var pts := plant_stem(seed_value)
	var h: float = pts[-1].y
	var out := []
	for i in 34:
		# most of the colony packs the lower stem (where the ants tend it), the rest the growing tip
		var y := rng.randf_range(1.6, 9.0) if rng.randf() < 0.7 else h * rng.randf_range(0.6, 0.97)
		var a := rng.randf() * TAU
		var kind := 0 if rng.randf() < 0.55 else 1
		if rng.randf() < 0.06:
			kind = 2
		var s := rng.randf_range(0.9, 1.1) if kind != 1 else rng.randf_range(0.45, 0.75)
		var outward := Vector3(cos(a), 0, sin(a))
		var p := stem_at(pts, y) + outward * (STEM_R + 0.38 * s)
		var down := Vector3(0, -1, 0).rotated(outward.cross(Vector3.UP).normalized(), rng.randf_range(-0.35, 0.35))
		var x := down
		var yv := outward
		out.append([Transform3D(Basis(x, yv, x.cross(yv)).scaled(Vector3.ONE * s), p), kind])
	return out


## Black bean aphid (Aphis fabae): a soft, matt black-olive pear-shaped body, small head with long
## antennae swept back, pale legs, two black cornicles and a short cauda at the rear. Nymphs are
## smaller and greyer with waxy patches; the occasional winged adult has a shiny thorax and wings.
static func aphid(kind := 0) -> ArrayMesh:
	var k = _new()
	var body := Color(0.13, 0.13, 0.1) if kind != 1 else Color(0.36, 0.38, 0.3)
	var leg := Color(0.26, 0.24, 0.18)
	k.blob(Vector3(-0.15, 0.42, 0), Vector3(0.62, 0.42, 0.46), body)                  # abdomen
	if kind == 1:
		for x in [-0.4, -0.05, 0.25]:
			k.blob(Vector3(x, 0.78, 0), Vector3(0.14, 0.06, 0.25), Color(0.7, 0.72, 0.66), Basis.IDENTITY, true)   # wax
	k.blob(Vector3(0.48, 0.42, 0), Vector3(0.28, 0.26, 0.3), body.lightened(0.05), Basis.IDENTITY, true)        # thorax
	k.blob(Vector3(0.72, 0.38, 0), Vector3(0.17, 0.17, 0.2), body.lightened(0.1), Basis.IDENTITY, true)         # head
	for side in [-1.0, 1.0]:
		k.blob(Vector3(0.8, 0.45, 0.14 * side), Vector3(0.06, 0.06, 0.06), Color(0.35, 0.05, 0.03), Basis.IDENTITY, true)
		k.chain([Vector3(0.82, 0.5, 0.08 * side), Vector3(0.95, 0.75, 0.25 * side), Vector3(0.4, 0.95, 0.45 * side),
			Vector3(-0.3, 0.85, 0.55 * side)], 0.025, 0.018, leg.darkened(0.3))      # antennae swept back
		k.seg(Vector3(-0.55, 0.62, 0.18 * side), Vector3(-0.78, 0.82, 0.24 * side), 0.045, Color(0.04, 0.04, 0.04))  # cornicle
		for x in [0.55, 0.42, 0.25]:
			k.chain([Vector3(x, 0.25, 0.18 * side), Vector3(x + 0.1, 0.45, 0.55 * side), Vector3(x + 0.05, 0.0, 0.75 * side)],
				0.03, 0.025, leg)
	k.blob(Vector3(-0.8, 0.4, 0), Vector3(0.1, 0.06, 0.06), body, Basis.IDENTITY, true)                       # cauda
	if kind == 2:
		k.blob(Vector3(0.45, 0.6, 0), Vector3(0.3, 0.2, 0.28), Color(0.05, 0.05, 0.05))
	return k.commit()


static func aphid_wings() -> ArrayMesh:
	var k = _new()
	for side in [-1.0, 1.0]:
		var outline := PackedVector2Array()
		for j in 12:
			var a := TAU * j / 12.0
			outline.append(Vector2(cos(a) * 0.75 - 0.55, sin(a) * 0.26))
		k.sheet(outline, Transform3D(Basis(Vector3.UP, 0.18 * side), Vector3(0.35, 0.82, 0.12 * side)), Color(0.9, 0.93, 1.0))
	return k.commit()


## A dead field cricket lying on its side; `left` (0..1) is how much of it is still there. Where the
## ants have cut pieces away, pale muscle and dark body fluid show through the cuticle.
static func cricket(left: float, rotten: bool, seed_value := 1) -> ArrayMesh:
	var k = _new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
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
	# bite wounds: the more that has been carried off, the more open patches on the soft parts
	var wounds := int(round((1.0 - left) * 9.0))
	for i in wounds:
		var a := rng.randf_range(-PI, PI)
		var x := rng.randf_range(-4.2, 1.0) * abd
		var on := Vector3(x, 1.7 + sin(a) * 1.55 * abd, cos(a) * 1.65 * abd)
		var r := rng.randf_range(0.45, 0.9)
		k.blob(on, Vector3(r, r * 0.55, r), Color(0.78, 0.62, 0.45) if i % 3 != 2 else Color(0.32, 0.16, 0.08),
			Basis(Vector3.RIGHT, a))
	return k.commit()


## Lasius larva: a fat, curved ("crook-necked") grub, translucent cream with the gut showing darker
## through the skin, the slim neck and tiny head bent down toward the belly. Facing +x, ~2 units.
static func larva() -> ArrayMesh:
	var k = _new()
	var skin := Color(0.95, 0.9, 0.76)
	var n := 9
	for i in n:
		var t := float(i) / (n - 1)
		var th := lerpf(-1.9, 1.4, t)                 # from the rear end round to the neck
		var p := Vector3(sin(th) * 0.62, 0.55 - cos(th) * 0.5, 0)
		var r := lerpf(0.42, 0.55, sin(t * PI)) * (1.0 - 0.55 * smoothstep(0.75, 1.0, t))
		k.blob(p, Vector3(r * 0.9, r, r * 1.05), skin)
		if t > 0.2 and t < 0.7:
			k.blob(p + Vector3(0, 0.05, 0), Vector3(r * 0.5, r * 0.5, r * 0.55), Color(0.78, 0.66, 0.44), Basis.IDENTITY, true)
	k.blob(Vector3(0.95, 0.42, 0), Vector3(0.16, 0.16, 0.17), Color(0.85, 0.75, 0.55), Basis.IDENTITY, true)   # head
	return k.commit()


## Silk cocoon of a Lasius pupa, with the dark meconium (the larva's gut contents, voided just
## before pupation) showing through at the rear end. 2.7 × 1.24 units, like the brood piles.
static func cocoon() -> ArrayMesh:
	var s := SphereMesh.new()
	s.radius = 0.62
	s.height = 1.24
	s.radial_segments = 14
	s.rings = 8
	var arr := s.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	for i in v.size():
		var p := v[i]
		p.x *= 1.35 / 0.62
		v[i] = p
		var tan := Color(0.8, 0.65, 0.45).lerp(Color(0.86, 0.73, 0.54), 0.5 + 0.5 * sin(p.x * 5.0 + p.y * 9.0))
		var spot := smoothstep(-0.85, -1.2, p.x)
		cols.append(tan.lerp(Color(0.12, 0.08, 0.06), spot))
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = cols
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in nrm.size():
		nrm[i] = Vector3(nrm[i].x * 0.62 / 1.35, nrm[i].y, nrm[i].z).normalized()
	arr[Mesh.ARRAY_NORMAL] = nrm
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


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
