extends SceneTree
## The C++ part (bin/ant_native, native/src/ant_native.cpp) given wrong sizes: it must answer "air" / no hits and go
## on - never read past its arrays (in C++ that could crash the game rather than stop with an error). v0.12.9.
## Also: a right-sized block gives the same density as reading the array by hand.
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
	print("NATIVE GUARD TEST PASSED" if ok else "NATIVE GUARD TEST FAILED")
	quit(0 if ok else 1)


func _check(what: String, good: bool) -> void:
	if not good:
		ok = false
		print("FAIL: ", what)
