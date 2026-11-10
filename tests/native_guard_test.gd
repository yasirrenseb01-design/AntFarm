extends SceneTree
## The C++ part (bin/ant_native, native/src/ant_native.cpp) given wrong sizes: it must answer "air" / no hits and go
## on - never read past its arrays (in C++ that could crash the game rather than stop with an error). v0.12.9.
## Also: a right-sized block gives the same density as reading the array by hand; chunk_sample the mesher's own values.
##   godot --headless --path . --script res://tests/native_guard_test.gd     -> "NATIVE GUARD TEST PASSED"

var ok := true


func _init() -> void:
	if not ClassDB.class_exists("AntNative"):
		print("no AntNative (no dll here): the game uses its GDScript")
		print("NATIVE GUARD TEST PASSED")
		quit(0)
		return
	var nat: Object = ClassDB.instantiate("AntNative")
	# a 2x2x2 block: sx = nx + 2 = 4, sy = ny + 2 = 4, sy0 = y_lo - 1 = -1 (as nest_scene.gd _soft_dims), ring of air
	var nx := 2
	var ny := 2
	var nz := 2
	var sx := nx + 2
	var sy := ny + 2
	var soft := PackedFloat32Array()
	soft.resize(sx * sy * (nz + 2))
	for i in soft.size():
		soft[i] = 1.0
	var dims := PackedInt32Array([sx, sy, -1, nx, ny, nz, 0])
	_check("inside: solid", is_equal_approx(nat.density_at(soft, dims, Vector3(0.5, 0.5, 0.5)), 1.0))
	_check("beyond the block: air", nat.density_at(soft, dims, Vector3(50, 0, 0)) == 0.0)
	# wrong inputs - each must come back without a crash
	var short := soft.slice(0, 5)
	_check("array too short: air", nat.density_at(short, dims, Vector3(0.5, 0.5, 0.5)) == 0.0)
	_check("empty array: air", nat.density_at(PackedFloat32Array(), dims, Vector3(1, 1, 1)) == 0.0)
	_check("dims too few: air", nat.density_at(soft, PackedInt32Array([4, 4]), Vector3(0.5, 0.5, 0.5)) == 0.0)
	_check("no dims: air", nat.density_at(soft, PackedInt32Array(), Vector3(0.5, 0.5, 0.5)) == 0.0)
	_check("row size 0: air", nat.density_at(soft, PackedInt32Array([0, 4, -1, 2, 2, 2, 0]), Vector3(0.5, 0.5, 0.5)) == 0.0)
	var huge := PackedInt32Array([1000000, 1000000, -1, 1000000, 1000000, 1000000, 0])
	_check("dims far bigger than the array: air", nat.density_at(soft, huge, Vector3(900, 900, 900)) == 0.0)
	_check("negative dims: air", nat.density_at(soft, PackedInt32Array([-4, -4, -1, 2, 2, 2, 0]), Vector3(0.5, 0.5, 0.5)) == 0.0)
	var pts := PackedVector3Array([Vector3(0.5, 0.5, 0.5), Vector3(0, 0, 0)])
	var r: Array = nat.soil_hits(PackedFloat32Array(), PackedInt32Array(), Transform3D(), pts, Vector3.UP, Vector3.RIGHT)
	_check("soil_hits with nothing: 3 answers, no hits", r.size() == 3 and int(r[2]) == 0)
	r = nat.soil_hits(short, huge, Transform3D(), pts, Vector3.UP, Vector3.RIGHT)
	_check("soil_hits with wrong sizes: no hits", r.size() == 3 and int(r[2]) == 0)
	r = nat.soil_hits(soft, dims, Transform3D(), pts, Vector3.UP, Vector3.RIGHT)
	_check("soil_hits in a solid block: answers", r.size() == 3)
	_chunks_same(nat)
	_bend_same(nat)
	_gap_same(nat)
	print("NATIVE GUARD TEST PASSED" if ok else "NATIVE GUARD TEST FAILED")
	quit(0 if ok else 1)


## chunk_sample (v0.12.24) against nest_mesher.sample, every chunk of a nest with tunnels cut at random through it and
## the chunks round its sides; and wrong sizes answered with nothing.
func _chunks_same(nat: Object) -> void:
	var Mesher = load("res://scripts/view/nest/nest_mesher.gd")
	var s = load("res://scripts/sim/simulation.gd").new()
	s.setup(3, 14, false, "keeper", false, "lasius_niger")
	var nest = s.nest
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in 3000:                          # (open cells scattered, and runs of them: surfaces in many chunks)
		var c := Vector3i(r.randi_range(nest.x_lo, nest.nx - 1), r.randi_range(nest.y_lo, nest.ny - 1), r.randi_range(nest.z_lo, nest.nz - 1))
		for j in 6:
			var d := c + Vector3i(j, 0, 0)
			if d.x < nest.nx:
				nest.rho[((d.z - nest.z_lo) * (nest.ny - nest.y_lo) + d.y - nest.y_lo) * (nest.nx - nest.x_lo) + d.x - nest.x_lo] = 0
	var box := PackedInt32Array([nest.x_lo, nest.y_lo, nest.z_lo, nest.nx, nest.ny, nest.nz, nest.AIR])
	var n := 0
	var same := 0
	var CH: int = Mesher.CH
	for kz in range(floori(nest.z_lo / float(CH)) - 1, (nest.nz + CH - 1) / CH + 1):
		for ky in range(floori(nest.y_lo / float(CH)) - 1, (nest.ny + CH - 1) / CH + 1):
			for kx in range(floori(nest.x_lo / float(CH)) - 1, (nest.nx + CH - 1) / CH + 1):
				var k := Vector3i(kx, ky, kz)
				n += 1
				if Mesher.sample(nest, k) == nat.chunk_sample(nest.rho, box, k, CH):
					same += 1
	_check("chunk_sample = nest_mesher.sample in every chunk (%d of %d)" % [same, n], same == n and n > 20)
	_check("chunk_sample, rho too short: nothing", nat.chunk_sample(nest.rho.slice(0, 100), box, Vector3i.ZERO, CH).is_empty())
	_check("chunk_sample, box too few: nothing", nat.chunk_sample(nest.rho, PackedInt32Array([0, 0]), Vector3i.ZERO, CH).is_empty())
	_check("chunk_sample, chunk size 0: nothing", nat.chunk_sample(nest.rho, box, Vector3i.ZERO, 0).is_empty())
	_check("chunk_sample, far outside: nothing", nat.chunk_sample(nest.rho, box, Vector3i(100000, 5, -100000), CH).is_empty())


func _check(what: String, good: bool) -> void:
	if not good:
		ok = false
		print("FAIL: ", what)


## bend_probe (v0.12.25) against nest_soil._soil_bend's own passes (_bent and _density_at, as GDScript sums them), over
## a block of random density, random bodies (turned every way, bent, some stood in the soil) and shifted block origins.
func _bend_same(nat: Object) -> void:
	var Soil = load("res://scripts/view/nest/parts/nest_soil.gd")
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var nx := 14
	var ny := 10
	var nz := 14
	var sx := nx + 2
	var sy := ny + 2
	var soft := PackedFloat32Array()
	soft.resize(sx * sy * (nz + 2))
	for i in soft.size():
		soft[i] = 1.0 if r.randf() < 0.45 else r.randf() * 0.3
	var dims := PackedInt32Array([sx, sy, 0, nx, ny, nz, 0])
	var off := Vector3(37, 0, 211)               # (the block starts at a column and a slice that are not 0: nest_scene._soft_off)
	var head := PackedVector3Array(Soil._HEAD_PTS)
	var gaster := PackedVector3Array(Soil._GASTER_PTS)
	var n := 0
	var same := 0
	var hit := 0
	for k in 20000:
		var up := Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)).normalized()
		var fwd := up.cross(Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1))).normalized()
		var sz := r.randf_range(0.8, 1.3)
		var tr := Transform3D(Basis(fwd * sz, up * sz, fwd.cross(up) * sz), off + Vector3(r.randf_range(-1, nx + 1), r.randf_range(-1, ny + 1), r.randf_range(-1, nz + 1)))
		var b := Vector2(r.randf_range(-0.6, 0.6), r.randf_range(-0.6, 0.6))
		var sb := Vector2(r.randf_range(-0.2, 0.6), r.randf_range(-0.2, 0.6))
		var lowered := (b - Vector2(0.12, 0.12)).clamp(Vector2(-0.6, -0.6), Vector2(0.6, 0.6))
		var want := 0
		var head_in := false
		var gaster_in := false
		for q in Soil._HEAD_PTS:
			if _dens(soft, dims, off, tr * Soil._bent(q, b, 0.0)) >= 0.5:
				head_in = true
				break
		for q in Soil._GASTER_PTS:
			if _dens(soft, dims, off, tr * Soil._bent(q, b, 0.0)) >= 0.5:
				gaster_in = true
				break
		want = (1 if head_in else 0) | (2 if gaster_in else 0)
		if not head_in and sb.y > 0.0:
			for q in Soil._HEAD_PTS:
				if _dens(soft, dims, off, tr * Soil._bent(q, Vector2(b.x, lowered.y), 0.0)) >= 0.5:
					want |= 4
					break
		if not gaster_in and sb.x > 0.0:
			for q in Soil._GASTER_PTS:
				if _dens(soft, dims, off, tr * Soil._bent(q, Vector2(lowered.x, b.y), 0.0)) >= 0.5:
					want |= 8
					break
		n += 1
		if want != 0:
			hit += 1
		if nat.bend_probe(soft, dims, tr, off, b, lowered, sb, head, gaster) == want:
			same += 1
	print("bend_probe: %d of %d same, %d with something in the soil" % [same, n, hit])
	_check("bend_probe = the GDScript passes in %d of %d bodies (%d with something in the soil)" % [same, n, hit], same == n and hit > 2000)
	_check("bend_probe, no dims: nothing in the soil", nat.bend_probe(soft, PackedInt32Array(), Transform3D(), off, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, head, gaster) == 0)
	_check("bend_probe, array too short: nothing in the soil", nat.bend_probe(soft.slice(0, 50), dims, Transform3D(Basis(), off + Vector3(5, 5, 5)), off, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, head, gaster) == 0)


## nest_scene._density_at over a block counted from `off` (the same lines).
func _dens(soft: PackedFloat32Array, dims: PackedInt32Array, off: Vector3, p0: Vector3) -> float:
	var p := p0
	var x := floori(p.x - off.x)
	var y := floori(p.y)
	var z := floori(p.z - off.z)
	if x < -1 or y < dims[6] - 1 or z < -1 or x >= dims[3] or y >= dims[4] or z >= dims[5]:
		return 0.0
	var fx := p.x - off.x - x
	var fy := p.y - y
	var fz := p.z - off.z - z
	var sx := dims[0]
	var sy := dims[1]
	var i := ((z + 1) * sy + (y - dims[2] + 1)) * sx + (x + 1)
	var d00 := lerpf(soft[i], soft[i + 1], fx)
	var d10 := lerpf(soft[i + sx], soft[i + sx + 1], fx)
	var j := i + sx * sy
	var d01 := lerpf(soft[j], soft[j + 1], fx)
	var d11 := lerpf(soft[j + sx], soft[j + sx + 1], fx)
	return lerpf(lerpf(d00, d10, fy), lerpf(d01, d11, fy), fz)


## gap_scan (v0.12.26) against the pass over the bodies near its head in nest_contact._gap_ahead (the same lines here), over
## dictionaries like the nestmates': random bodies in bins, some up on another's back, some on a wall, some with no body yet.
func _gap_same(nat: Object) -> void:
	var Contact = load("res://scripts/view/nest/parts/nest_contact.gd")
	var parts: Array = Contact.CLIMB_PARTS
	var pts := PackedVector3Array(parts)
	var rad := PackedFloat64Array([parts[0].z, parts[1].z, parts[2].z, parts[3].z, parts[4].z])
	var near_offs := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
		Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(-1, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var n := 0
	var same := 0
	var held := 0
	for round in 300:
		var bodies := []
		var near := {}
		for i in 40:
			var up := Vector3(r.randf_range(-0.3, 0.3), 1, r.randf_range(-0.3, 0.3)).normalized() if r.randf() < 0.9 else Vector3.RIGHT
			var f := up.cross(Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1))).normalized()
			var sz := r.randf_range(0.9, 1.2)
			var o := Vector3(r.randf_range(0, 8), r.randf_range(0, 3), r.randf_range(0, 8))
			var d := {"size": sz}
			if r.randf() < 0.95:
				d["xf"] = Transform3D(Basis(f * sz, up * sz, f.cross(up) * sz), o)
			if r.randf() < 0.2:
				d["over"] = r.randf_range(0, 0.5) if r.randf() < 0.5 else 1
			bodies.append(d)
		for d in bodies:
			if d.has("xf"):
				var oo: Vector3 = d.xf.origin
				var key := Vector3i(floori(oo.x / 3.0), floori(oo.y / 3.0), floori(oo.z / 3.0))
				if not near.has(key):
					near[key] = []
				near[key].append(d)
		for t in 12:
			var m: Dictionary = bodies[r.randi() % 40]
			if not m.has("xf"):
				continue
			if r.randf() < 0.3:
				m["over_on"] = bodies[r.randi() % 40]
			var other: Dictionary = bodies[r.randi() % 40]
			if r.randf() < 0.3:
				other["over_on"] = m
			var x: Transform3D = m.xf
			var up := x.basis.y.normalized()
			var f := x.basis.x.normalized()
			var s := float(m.size)
			var head := x * Vector3(pts[0].x, pts[0].y, 0.0)
			var lag := r.randf_range(0, 0.8) if r.randf() < 0.7 else 0.0
			var on = m.get("over_on")
			var hr: float = parts[0].z * s
			var key := Vector3i(floori(head.x / 3.0), floori(head.y / 3.0), floori(head.z / 3.0))
			var k := 1.0
			var by = null
			for off in near_offs:
				var bin = near.get(key + off)
				if bin == null:
					continue
				for o in bin:
					if is_same(o, m) or not o.has("xf") or is_same(o, on) or is_same(o.get("over_on"), m) or float(o.get("over", 0.0)) > 0.1:
						continue
					var ox: Transform3D = o.xf
					if ox.origin.distance_squared_to(head) > 9.0 or ox.basis.y.normalized().dot(up) < 0.5:
						continue
					var os := ox.basis.x.length()
					for q in parts:
						var to: Vector3 = ox * Vector3(q.x, q.y, 0.0) - head
						to -= up * to.dot(up)
						var ahead := to.dot(f)
						if ahead < 0.0:
							continue
						var reach: float = hr + q.z * os + 0.06
						var lat := (to - f * ahead).length()
						if lat >= reach:
							continue
						var gap := ahead - sqrt(reach * reach - lat * lat) - lag
						var kk := clampf(gap / (0.7 * s), 0.0, 1.0)
						if kk < k:
							k = kk
							by = o
			var got: Array = nat.gap_scan(m, near, head, up, f, s, lag, on, near_offs, pts, rad)
			n += 1
			if k < 1.0:
				held += 1
			if got[0] == k and is_same(got[1], by):
				same += 1
	print("gap_scan: %d of %d same, %d held up by something" % [same, n, held])
	_check("gap_scan = the GDScript pass in %d of %d bodies (%d held up)" % [same, n, held], same == n and held > 200)
