extends RefCounted
## Dev (--stacks, with --seq, nest): how high the brood is heaped (the keeper, 2026-10-28: "4-5 cocoons stacked straight
## up like a column"). For each cocoon (and larva) drawn: how many others of its kind lie under it - their middles within
## one body width of its own across, and lower. A heap's second layer is 1 under; a column of five is 4.
## Per frame, pooled: items, share with 2+ under them, the most under any one; and the highest any one lies off the
## floor (in cocoon thicknesses).


static func measure(nv, t: Dictionary) -> void:
	for kind in ["pupae", "larvae"]:
		var drawn: Array = nv._brood_drawn.get(kind, [])
		var ps := []
		for e in drawn:
			ps.append((e[0] as Transform3D).origin)
		var w := 1.1 if kind == "pupae" else 0.7         # (a cocoon is ~1.24 units thick, a larva ~0.76)
		if OS.has_environment("STACKDUMP") and kind == "pupae" and int(t.get("dumped", 0)) < 2 and ps.size() > 0:
			t.dumped = int(t.get("dumped", 0)) + 1
			for e in drawn:
				var o: Vector3 = (e[0] as Transform3D).origin
				print("  pupa at %s floor %.2f x-axis %s" % [str(o), nv._floor_cached(o), str((e[0] as Transform3D).basis.x.normalized())])
		for i in ps.size():
			var p: Vector3 = ps[i]
			var under := 0
			for j in ps.size():
				var q: Vector3 = ps[j]
				if j != i and q.y < p.y - 0.35 * w and Vector2(q.x - p.x, q.z - p.z).length() < w:
					under += 1
			var k: String = kind + "_"
			t[k + "n"] = int(t.get(k + "n", 0)) + 1
			t[k + "2"] = int(t.get(k + "2", 0)) + (1 if under >= 2 else 0)
			if under > int(t.get(k + "max", 0)) and kind == "pupae" and OS.has_environment("STACKFOLLOW"):
				nv.target_t = p                              # (the camera on the highest stack yet)
				nv.target = p
				print("  stack of %d at %s, its floor %.2f, lifted %.2f" % [under + 1, str(p), nv._floor_cached(p), p.y - nv._floor_cached(p)])
			t[k + "max"] = maxi(int(t.get(k + "max", 0)), under)
			var lift: float = (p.y - nv._floor_cached(p)) / (w * 1.1)
			t[k + "lift"] = maxf(float(t.get(k + "lift", 0.0)), lift)


static func report(t: Dictionary) -> String:
	var out := []
	for kind in ["pupae", "larvae"]:
		var k: String = kind + "_"
		var n := maxi(1, int(t.get(k + "n", 0)))
		out.append("%s: %d item-frames, 2+ under it %.1f%%, most under one %d, highest %.1f thick off the floor" % [kind,
			int(t.get(k + "n", 0)), 100.0 * int(t.get(k + "2", 0)) / n, int(t.get(k + "max", 0)), float(t.get(k + "lift", 0.0))])
	return "stacks: " + "; ".join(out)
