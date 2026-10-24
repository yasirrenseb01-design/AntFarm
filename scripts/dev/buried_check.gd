extends RefCounted
## Dev (--buried, with --seq, nest view): nestmates drawn with their whole body inside the soil (head, thorax and
## gaster all in solid soil) - the keeper's "an ant goes through into the soil and stays there a long while"
## (2026-10-24). Each frame: how many are buried; for each one buried a second or more, everything it carries is
## printed once (what it is doing, where it is going, how it is pushed and lifted), and how long it stayed.

const FootCheck := preload("res://scripts/dev/foot_check.gd")
const K := 0.34
const PARTS := [Vector3(2.5, 1.1, 0.0), Vector3(0.5, 1.1, 0.0), Vector3(-2.5, 1.05, 0.0)]    # head, thorax, gaster (model units)


static func _buried(nest, xf: Transform3D) -> bool:
	for p in PARTS:
		if FootCheck._vol(nest, xf * ((p as Vector3) * K)) < 0.9:
			return false
	return true


static func _dump(m: Dictionary) -> String:
	var out := []
	for k in m:
		var v = m[k]
		if v is Array or v is PackedVector3Array or v is PackedFloat32Array or v is PackedInt32Array:
			out.append("%s[%d]" % [k, v.size()])
		elif v is Dictionary:
			out.append("%s{%d}" % [k, v.size()])
		elif v is Transform3D:
			out.append("%s@%s up %s" % [k, (v as Transform3D).origin, (v as Transform3D).basis.y.normalized()])
		elif v is float:
			out.append("%s=%.3f" % [k, v])
		else:
			out.append("%s=%s" % [k, v])
	return ", ".join(out)


static func measure(nv, tally: Dictionary) -> void:
	var nest = nv.nest
	FootCheck.rho = nest.rho
	tally.frames = int(tally.get("frames", 0)) + 1
	var since: Dictionary = tally.get("since", {})
	var now := {}
	for m in nv._mates:
		if not m.has("xf"):
			continue
		tally.ant_frames = int(tally.get("ant_frames", 0)) + 1
		var key := "w%d" % int(m.get("wid", -1))
		# (the last 150 frames of each: where it is drawn, its point on the path, its cell, what it does)
		var hist: Dictionary = tally.get("hist", {})
		var h: Array = hist.get(key, [])
		h.append("f%d xf %s vp %s from %s to %s t %.2f cell %s act %d rest %d role %s%s%s" % [int(tally.frames), (m.xf as Transform3D).origin.snapped(Vector3.ONE * 0.01),
			(m.get("vp", Vector3.ZERO) as Vector3).snapped(Vector3.ONE * 0.01), m.get("from"), m.get("to"), float(m.get("t", 0.0)), m.get("cell"), int(m.get("act", -1)),
			int(m.get("rest", 0)), m.get("role", "?"), " script" if m.has("script") else "", " buried" if _buried(nest, m.xf) else ""])
		if h.size() > 150:
			h.pop_front()
		hist[key] = h
		tally.hist = hist
		if not _buried(nest, m.xf):
			if since.has(key):
				var n := int(tally.frames) - int(since[key])
				if n >= 60:
					print("  BURIED %s for %d frames, out now at %s" % [key, n, (m.xf as Transform3D).origin])
			continue
		tally.buried = int(tally.get("buried", 0)) + 1
		now[key] = since.get(key, tally.frames)
		var n := int(tally.frames) - int(now[key])
		if n == 60:
			tally.episodes = int(tally.get("episodes", 0)) + 1
			var c: Vector3i = m.get("cell", Vector3i.ZERO)
			print("  BURIED %s a second now, cell %s soil there %.2f walkable %s:\n    %s" % [key, c, FootCheck._vol(nest, Vector3(c)), nv._walkable(c), _dump(m)])
			for line in (tally.hist as Dictionary).get(key, []):
				print("    H ", line)
	for key in since:
		if not now.has(key):
			pass
	tally.since = now


static func report(tally: Dictionary) -> String:
	return "buried nestmates (head, thorax and gaster all in the soil): %.2f%% of ant-frames over %d frames, %d buried a second or more" % [
		100.0 * float(tally.get("buried", 0)) / maxf(1.0, float(tally.get("ant_frames", 0))), int(tally.get("frames", 0)), int(tally.get("episodes", 0))]
