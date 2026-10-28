extends RefCounted
## Dev (--turns, with --seq, outworld): how much the foragers drawn walking swing their heading and tip their bodies
## (the keeper, 2026-10-28: "ants out there turn their bodies too much as they walk; climbing over a step is not smooth,
## the body looks stiff"). Read from each forager's drawn transform (a.vxf) frame to frame, followed by its id; only ants
## walking on the ground (moving, not busy, not thrown, not on a stem or the glass). Run at --fixed-fps 60.
##   yaw rate      how fast the heading turns, degrees a second (mean, 90th percentile), and frames over 180 °/s
##   swings        the heading's turning changing direction (left <-> right, each over 30 °/s): per ant per second
##   tilt rate     how fast the body's up tips (over pebbles, twigs, the crater's rim), degrees a second; frames over 90 °/s


static func measure(ow, sim, t: Dictionary) -> void:
	var last: Dictionary = t.get("last", {})
	var now := {}
	var dt := 1.0 / 60.0
	for a in sim.outside:
		if a.state == sim.Ant.IN_NEST or a.dead or a.busy > 0 or a.vright > 0.0 or a.vfeed > 0.0 or not (a.vxf is Transform3D):
			continue
		if a.vmv < 0.6:
			continue                                       # (standing or starting off)
		var xf: Transform3D = a.vxf
		var f := xf.basis.x.normalized()
		var up := xf.basis.y.normalized()
		var yaw := atan2(f.z, f.x)
		now[a.id] = [yaw, up, xf.origin, 0.0]
		if not last.has(a.id):
			continue
		var p: Array = last[a.id]
		if (xf.origin - (p[2] as Vector3)).length() > 2.0:
			continue                                       # (jumped: put back somewhere)
		var rate := rad_to_deg(wrapf(yaw - float(p[0]), -PI, PI)) / dt
		var tilt := rad_to_deg((p[1] as Vector3).angle_to(up)) / dt
		t.n = int(t.get("n", 0)) + 1
		t.yaw_sum = float(t.get("yaw_sum", 0.0)) + absf(rate)
		if not t.has("yaws"):
			t.yaws = []
		t.yaws.append(absf(rate))
		t.sharp = int(t.get("sharp", 0)) + (1 if absf(rate) > 180.0 else 0)
		t.tilt_sum = float(t.get("tilt_sum", 0.0)) + tilt
		t.snap = int(t.get("snap", 0)) + (1 if tilt > 90.0 else 0)
		if tilt > 90.0 and OS.has_environment("TURNDBG") and int(t.get("snap", 0)) % 25 == 1:
			print("  tilt %.0f °/s: ant %d state %d act %d carry %d vmv %.2f at %s up %s -> %s voff %s" % [tilt, a.id, a.state,
				a.act, a.carry, a.vmv, str(xf.origin), str(p[1]), str(up), str(a.voff)])
		# a swing: the turn's direction flips (each side over 30 °/s)
		var was: float = float(p[3])
		now[a.id][3] = rate if absf(rate) > 30.0 else was
		if absf(rate) > 30.0 and absf(was) > 30.0 and signf(rate) != signf(was):
			t.swings = int(t.get("swings", 0)) + 1
	t.last = now


static func report(t: Dictionary) -> String:
	var n := maxi(1, int(t.get("n", 0)))
	var ys: Array = t.get("yaws", [])
	ys.sort()
	var p90: float = ys[int(ys.size() * 0.9)] if not ys.is_empty() else 0.0
	return "turns: %d ant-frames walking; yaw rate mean %.0f °/s, p90 %.0f, over 180 °/s %.1f%%; swings %.2f per ant-second; tilt rate mean %.0f °/s, over 90 °/s %.2f%%" % [
		n, float(t.get("yaw_sum", 0.0)) / n, p90, 100.0 * int(t.get("sharp", 0)) / n,
		float(t.get("swings", 0)) / (n / 60.0), float(t.get("tilt_sum", 0.0)) / n, 100.0 * int(t.get("snap", 0)) / n]
