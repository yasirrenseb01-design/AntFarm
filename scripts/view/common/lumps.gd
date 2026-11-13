extends RefCounted
## Small lumps on the ground, each in a few shapes so that a heap of them does not look like copies of one ball
## (the keeper, 2026-11-09: "the soil pellets look like one model - three kinds of pellet, mixed; moss in two").
## Every shape is about the unit sphere (radius ~1, centred), the instances scale it as before; made once, here, from
## fixed seeds - the same every run (no draw from the simulation).
##   pellet 0: a clod with cut faces (rounded and lumpy until v0.13.15: "make the round ones angular, with cut
##   corners" - the keeper) · 1: a flat crumb with blunt facets · 2: two lobes stuck together · 3: a broken chip, a few
##   flat faces and sharp edges · 4: a long crumb, a little bent (3 and 4: v0.13.15, "two more shapes")
##   moss 0: a cushion of small tufts · 1: a low mat spreading out in lobes
## [Lasius pellets are moist soil worked into crumbs by the mandibles - irregular, a few tenths of a mm to ~1 mm:
## general; the shapes are drawn to read as such at the camera's distance.]

const PELLETS := 5
const MOSSES := 2


static func pellet(kind: int) -> Mesh:
	match kind:
		0:
			return _lump(7, 4, 0.2, 2.2, 11, Vector3(1.0, 0.88, 0.95), true)
		1:
			return _lump(9, 5, 0.18, 1.3, 23, Vector3(1.15, 0.62, 0.9))
		3:
			return _lump(5, 3, 0.28, 3.0, 29, Vector3(1.1, 0.7, 0.85), true)
		4:
			var st := _begin()
			var noise := _noise(31, 2.5)
			for v in _sphere(6, 4):
				var w: Vector3 = v * (1.0 + 0.18 * noise.get_noise_3dv(v))
				w = Vector3(w.x * 1.4, w.y * 0.58, w.z * 0.66)
				w.y += 0.18 * (w.x * w.x) / 2.0 - 0.1          # (bent a little along its length)
				st.add_vertex(w)
			return _end(st, true)
		_:
			var st := _begin()
			_add(st, _sphere(12, 6), 0.16, 2.0, 37, Basis.from_scale(Vector3(0.75, 0.72, 0.7)), Vector3(-0.32, -0.08, 0.05))
			_add(st, _sphere(12, 6), 0.16, 2.0, 41, Basis.from_scale(Vector3(0.62, 0.6, 0.6)), Vector3(0.4, -0.15, -0.08))
			return _end(st)


static func moss(kind: int) -> Mesh:
	match kind:
		0:
			return _lump(24, 10, 0.16, 5.5, 53, Vector3(1.0, 1.0, 1.0))
		_:
			# a mat: low, its outline in uneven lobes, finer tufts over it
			var st := _begin()
			var s := _sphere(28, 8)
			var noise := _noise(67, 4.0)
			for i in s.size():
				var v: Vector3 = s[i]
				var ang := atan2(v.z, v.x)
				# (lobes of uneven size, not a star: three waves out of step)
				var lobe := 1.0 + 0.13 * sin(ang * 5.0 + 0.7) + 0.12 * sin(ang * 3.0 + 2.1) + 0.07 * sin(ang * 7.0 + 4.0)
				var r := 1.0 + 0.12 * noise.get_noise_3dv(v)
				st.add_vertex(Vector3(v.x * lobe, v.y * 0.55, v.z * lobe) * r)
			return _end(st)


## A unit sphere's surface, bumped by noise (amp at freq), scaled.
static func _lump(segs: int, rings: int, amp: float, freq: float, seed_value: int, scale: Vector3, cut := false) -> Mesh:
	var st := _begin()
	_add(st, _sphere(segs, rings), amp, freq, seed_value, Basis.from_scale(scale), Vector3.ZERO)
	return _end(st, cut)


static func _add(st: SurfaceTool, tris: PackedVector3Array, amp: float, freq: float, seed_value: int, b: Basis, at: Vector3) -> void:
	var noise := _noise(seed_value, freq)
	for v in tris:
		st.add_vertex(b * (v * (1.0 + amp * noise.get_noise_3dv(v))) + at)


static func _noise(seed_value: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = freq * 0.1
	n.fractal_octaves = 2
	return n


## The triangles of a unit sphere (no UVs: the seam's vertices merge, so the bumps meet there).
static func _sphere(segs: int, rings: int) -> PackedVector3Array:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = segs
	s.rings = rings
	var a := s.get_mesh_arrays()
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var out := PackedVector3Array()
	for i in (a[Mesh.ARRAY_INDEX] as PackedInt32Array):
		out.append(verts[i])
	return out


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## cut: each face lit flat (sharp edges between them), not smoothed over.
static func _end(st: SurfaceTool, cut := false) -> Mesh:
	if not cut:
		st.index()
	st.generate_normals()
	return st.commit()


## The pellet a digger carries in the nest view (its size there).
static func carried() -> Mesh:
	return sized(pellet(0), Vector3(0.8, 0.65, 0.68))


## The mesh scaled (s) - for an instance drawn without its own scale.
static func sized(m: Mesh, s: Vector3) -> Mesh:
	var st := _begin()
	st.append_from(m, 0, Transform3D(Basis.from_scale(s), Vector3.ZERO))
	return st.commit()


## Which of n shapes an instance takes: mixed evenly and the same every run (from where it lies).
static func kind_at(p: Vector2, n: int) -> int:
	return int(absf(sin(p.x * 12.9898 + p.y * 78.233)) * 43758.5453) % n


## Fills the MultiMeshes (one a shape) with the transforms (and colours, if given), each by kind_at of its own place,
## turned about the up axis by the same draw - the same shape never lies the same way twice.
static func fill(mms: Array, xfs: Array, cols: Array = []) -> void:
	var per: Array = []
	for k in mms.size():
		per.append([])
	for j in xfs.size():
		var xf: Transform3D = xfs[j]
		var at := Vector2(xf.origin.x, xf.origin.z)
		var turn := Basis(Vector3.UP, float(kind_at(at * 1.7 + Vector2(3.1, 0.0), 360)) * TAU / 360.0)
		per[kind_at(at, mms.size())].append([Transform3D(xf.basis * turn, xf.origin), cols[j] if j < cols.size() else null])
	for k in mms.size():
		var mm: MultiMesh = mms[k]
		mm.instance_count = per[k].size()
		for i in per[k].size():
			mm.set_instance_transform(i, per[k][i][0])
			if per[k][i][1] != null:
				mm.set_instance_color(i, per[k][i][1])
