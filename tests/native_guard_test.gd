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
