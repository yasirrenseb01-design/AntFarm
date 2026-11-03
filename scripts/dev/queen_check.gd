extends RefCounted
## Dev (--queen-soil, with --seq, nest): the queen's gaster in the soil (the keeper, 2026-10-28: resting in her winter
## rest, her gaster went through the chamber's floor). Points along the underside and tip of her gaster as the model
## has them (her local units, x forward; the gaster hangs 0.24 below her feet - nest_scene.QUEEN_LIFT), through her
## drawn transform: frames with any in the soil, and how deep the deepest went (units, 1 = 1.5 mm).

const GASTER := [Vector3(-0.7, -0.12, 0.0), Vector3(-1.2, -0.24, 0.0), Vector3(-1.7, -0.18, 0.0), Vector3(-2.15, 0.05, 0.0),
	Vector3(-1.2, -0.12, 0.45), Vector3(-1.2, -0.12, -0.45), Vector3(-2.35, 0.3, 0.0)]


static func measure(nv, t: Dictionary) -> void:
	if nv._queen_mm.instance_count == 0:
		return
	var xf: Transform3D = nv._queen_xf
	var deep := 0.0
	for p in GASTER:
		var w: Vector3 = xf * p
		if nv._density_at(w) > 0.5:
			deep = maxf(deep, nv._floor_cached(w) - w.y)
	t.n = int(t.get("n", 0)) + 1
	t.in_soil = int(t.get("in_soil", 0)) + (1 if deep > 0.0 else 0)
	t.deep = maxf(float(t.get("deep", 0.0)), deep)
	if deep > 0.05 and OS.has_environment("QUEENDBG") and int(t.in_soil) % 40 == 1:
		print("  queen gaster %.2f deep: act %d mode %d step %s dy %.2f pitch %.2f at %s" % [deep, nv._queen_act, nv._queen_mode,
			str(nv._queen_step), nv._queen_dy, nv._queen_pitch, str(xf.origin)])


static func report(t: Dictionary) -> String:
	var n := maxi(1, int(t.get("n", 0)))
	return "queen soil: %d frames, gaster in the soil %.1f%%, deepest %.2f units" % [int(t.get("n", 0)),
		100.0 * int(t.get("in_soil", 0)) / n, float(t.get("deep", 0.0))]


## (--queen-walk, with --queen-to and --seq: the keeper, 2026-11-03 - "walking to another chamber her body leaves the
## tunnel") Her whole body while she walks: points round her head, thorax and gaster (sides, top), frames with any of
## them in the soil, and the share of points in it.
const BODY := [Vector3(1.25, 0.15, 0.0), Vector3(0.9, 0.3, 0.3), Vector3(0.9, 0.3, -0.3), Vector3(0.3, 0.2, 0.35),
	Vector3(0.3, 0.2, -0.35), Vector3(0.3, 0.6, 0.0), Vector3(-0.7, 0.1, 0.5), Vector3(-0.7, 0.1, -0.5),
	Vector3(-1.3, 0.05, 0.6), Vector3(-1.3, 0.05, -0.6), Vector3(-1.3, 0.65, 0.0), Vector3(-2.2, 0.15, 0.0)]


static func measure_walk(nv, t: Dictionary) -> void:
	if nv._queen_mm.instance_count == 0 or nv._queen_path.is_empty():
		return
	var xf: Transform3D = nv._queen_xf
	var inside := 0
	for p in BODY:
		if nv._density_at(xf * p) > 0.5:
			inside += 1
	t.n = int(t.get("n", 0)) + 1
	t.frames = int(t.get("frames", 0)) + (1 if inside > 0 else 0)
	t.pts = int(t.get("pts", 0)) + inside
	t.bad = int(t.get("bad", 0)) + (1 if inside >= 3 else 0)


static func report_walk(t: Dictionary) -> String:
	var n := maxi(1, int(t.get("n", 0)))
	return "queen walk: %d frames walking, any point in the soil %.1f%%, 3+ points %.1f%%, points in the soil %.1f%%" % [
		int(t.get("n", 0)), 100.0 * int(t.get("frames", 0)) / n, 100.0 * int(t.get("bad", 0)) / n,
		100.0 * int(t.get("pts", 0)) / (n * BODY.size())]
