extends SceneTree
# where the cut face's hole (raw voxels, trilinear, as soil.gdshader samples them) and the soil surface (the
# mesher's softened density) cross 0.5 along vertical lines through the founding chamber
func tri_raw(n, p: Vector3) -> float:
	var x := floori(p.x); var y := floori(p.y); var z := floori(p.z)
	var fx := p.x - x; var fy := p.y - y; var fz := p.z - z
	var f := func(a, b, c): return 1.0 if n.inside(Vector3i(a, b, c)) and not n.is_open(Vector3i(a, b, c)) else 0.0
	var d00: float = lerpf(f.call(x, y, z), f.call(x + 1, y, z), fx)
	var d10: float = lerpf(f.call(x, y + 1, z), f.call(x + 1, y + 1, z), fx)
	var d01: float = lerpf(f.call(x, y, z + 1), f.call(x + 1, y, z + 1), fx)
	var d11: float = lerpf(f.call(x, y + 1, z + 1), f.call(x + 1, y + 1, z + 1), fx)
	return lerpf(lerpf(d00, d10, fy), lerpf(d01, d11, fy), fz)
func tri_soft(n, p: Vector3) -> float:
	var x := floori(p.x); var y := floori(p.y); var z := floori(p.z)
	var fx := p.x - x; var fy := p.y - y; var fz := p.z - z
	var d00: float = lerpf(n.density(x, y, z), n.density(x + 1, y, z), fx)
	var d10: float = lerpf(n.density(x, y + 1, z), n.density(x + 1, y + 1, z), fx)
	var d01: float = lerpf(n.density(x, y, z + 1), n.density(x + 1, y, z + 1), fx)
	var d11: float = lerpf(n.density(x, y + 1, z + 1), n.density(x + 1, y + 1, z + 1), fx)
	return lerpf(lerpf(d00, d10, fy), lerpf(d01, d11, fy), fz)
func _init() -> void:
	var s = load("res://scripts/sim/simulation.gd").new()
	s.setup(3, 0, false, "wild")
	for d in 150:
		for i in s.TPD: s.step()
	var n = s.nest
	var c: Vector3 = n.chambers[0].c
	print("chamber at ", c, " goal ", n.chambers[0].goal)
	for dz in [-3.0, -1.5, 0.0, 1.5, 3.0]:
		var line := []
		for dx in range(-6, 7, 2):
			var p := Vector3(c.x + dx, c.y, c.z + dz)
			var a := -99.0
			var b := -99.0
			for k in 60:
				var q := p - Vector3(0, k * 0.05, 0)
				if a < -98 and tri_raw(n, q) >= 0.5: a = q.y
				if b < -98 and tri_soft(n, q) >= 0.5: b = q.y
			line.append("%.2f" % (b - a) if a > -98 and b > -98 else "-")
		print("dz %.1f  floor(soft) - floor(raw) along x: %s" % [dz, line])
	quit()
