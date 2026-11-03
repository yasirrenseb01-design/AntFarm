extends RefCounted
## Dev (--flips, with --seq, nest): nestmates drawn upside down (the keeper, 2026-11-03: "an ant on its back, still
## walking, for a moment" - by the queen, among the eggs). Each frame each nestmate shown: its up pointing down (on a
## ceiling) - in a chamber (a floor two cells under it) or in a tunnel - and what it was doing (vd: its duty, script:
## a lifecycle moment, rest).

static func measure(nv, t: Dictionary) -> void:
	for m in nv._mates:
		if not m.has("xf") or not nv._shown(m.xf):
			continue
		var xf: Transform3D = m.xf
		t.n = int(t.get("n", 0)) + 1
		var up := xf.basis.y.normalized()
		if up.y > -0.5:
			continue
		var c := Vector3i(roundi(xf.origin.x), roundi(xf.origin.y), roundi(xf.origin.z))
		var room: bool = nv.nest.is_open(c + Vector3i(0, -1, 0)) and nv.nest.is_open(c + Vector3i(0, -2, 0))
		var what := "script" if m.has("script") else ("rest" if int(m.get("rest", 0)) > 0 else "duty%d" % int(m.get("vd", -1)))
		var k := ("room " if room else "tunnel ") + what
		t.flip = int(t.get("flip", 0)) + 1
		var by: Dictionary = t.get("by", {})
		by[k] = int(by.get(k, 0)) + 1
		t.by = by
		if room and OS.has_environment("FLIPDBG") and int(t.flip) % 30 == 1:
			print("  upside down in a room: %s at %s up %s" % [k, str(xf.origin), str(up)])


static func report(t: Dictionary) -> String:
	var n := maxi(1, int(t.get("n", 0)))
	var parts := []
	var by: Dictionary = t.get("by", {})
	for k in by:
		parts.append("%s %.2f%%" % [k, 100.0 * int(by[k]) / n])
	return "flips: %d ant-frames, upside down %.2f%% (%s)" % [int(t.get("n", 0)), 100.0 * int(t.get("flip", 0)) / n, ", ".join(parts)]
