extends RefCounted
## Dev (--queen-soil, with --seq, nest): the queen's gaster in the soil (the keeper, 2026-10-28: resting in her winter
## rest, her gaster went through the chamber's floor). Points along the underside and tip of her gaster as the model
## has them (her local units, x forward; the gaster hangs 0.24 below her feet - nest_scene.QUEEN_LIFT), through her
## drawn transform: frames with any in the soil, and how deep the deepest went (units, 1 = 1.5 mm).

const QueenWay := preload("res://scripts/view/nest/queen_way.gd")
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
	if nv._queen_mm.instance_count == 0:
		return
	var xf: Transform3D = nv._queen_xf
	# (does she jerk: how far her body goes and turns from one frame to the next, on her way and as she sets off and arrives)
	var walking: bool = not nv._queen_path.is_empty()
	if t.has("last_xf") and (walking or t.get("was_walking", false)):
		var was: Transform3D = t.last_xf
		var moved := was.origin.distance_to(xf.origin)
		var ang := rad_to_deg(was.basis.orthonormalized().get_rotation_quaternion().angle_to(xf.basis.orthonormalized().get_rotation_quaternion()))
		if walking != bool(t.get("was_walking", false)):
			print("  queen %s: moved %.2f voxels, turned %.1f degrees in one frame" % ["sets off" if walking else "arrives", moved, ang])
		else:
			if ang > 15.0:
				print("  queen flick: %.1f degrees at %s fwd %s -> %s up %s -> %s" % [ang, str(xf.origin.snapped(Vector3.ONE * 0.1)), str(was.basis.x.normalized().snapped(Vector3.ONE * 0.1)),
					str(xf.basis.x.normalized().snapped(Vector3.ONE * 0.1)), str(was.basis.y.normalized().snapped(Vector3.ONE * 0.1)), str(xf.basis.y.normalized().snapped(Vector3.ONE * 0.1))])
				if OS.has_environment("QUEENDBG"):
					print("    her way fwd %s up_s %s back %s soil off %s yaw %.2f bend %s" % [str(nv._queen_walk_fwd.snapped(Vector3.ONE * 0.01)), "-", str(nv._queen_back.snapped(Vector3.ONE * 0.01)),
						str(nv._queen_soil.get("soil_off", Vector3.ZERO)), float(nv._queen_soil.get("soil_yaw", 0.0)), str(nv._queen_soil.get("bend", Vector2.ZERO))])
			t.max_move = maxf(float(t.get("max_move", 0.0)), moved)
			t.max_ang = maxf(float(t.get("max_ang", 0.0)), ang)
			t.jerks = int(t.get("jerks", 0)) + (1 if ang > 3.0 or moved > 0.25 else 0)
			t.sum_ang = float(t.get("sum_ang", 0.0)) + ang
	t.last_xf = xf
	t.was_walking = walking
	if not walking:
		return
	var inside := 0
	if not t.has("by_pt"):
		var zeros := []
		zeros.resize(BODY.size())
		zeros.fill(0)
		t.by_pt = zeros
	for i in BODY.size():
		if nv._density_at(xf * (BODY[i] as Vector3)) > 0.5:
			inside += 1
			t.by_pt[i] += 1
	var on_wall: bool = xf.basis.y.normalized().y < 0.7
	t.wall_n = int(t.get("wall_n", 0)) + (1 if on_wall else 0)
	t.wall_hit = int(t.get("wall_hit", 0)) + (1 if on_wall and inside > 0 else 0)
	# (the room either side of her middle, her left and right as she goes: is she between the walls or along one)
	var mid: Vector3 = xf * Vector3(-0.3, 0.2, 0.0)
	var side: Vector3 = xf.basis.z.normalized()
	var dl: float = QueenWay._reach(nv, mid, side, 6.0)
	var dr: float = QueenWay._reach(nv, mid, -side, 6.0)
	t.room_l = float(t.get("room_l", 0.0)) + dl
	t.room_r = float(t.get("room_r", 0.0)) + dr
	if OS.has_environment("QUEENDBG") and int(t.get("n", 0)) % 40 == 0:
		# (where she is on her way: the room round her middle each way, her up, the points in the soil)
		var up: Vector3 = xf.basis.y.normalized()
		print("  QW %4d at %s fwd %s up %s  L %.1f R %.1f above %.1f below %.1f  in soil %d" % [int(t.get("n", 0)), str(xf.origin.snapped(Vector3.ONE * 0.1)), str(xf.basis.x.normalized().snapped(Vector3.ONE * 0.1)),
			str(up.snapped(Vector3.ONE * 0.1)), dl, dr, QueenWay._reach(nv, mid, up, 6.0), QueenWay._reach(nv, mid, -up, 6.0), inside])
	t.n = int(t.get("n", 0)) + 1
	t.frames = int(t.get("frames", 0)) + (1 if inside > 0 else 0)
	t.pts = int(t.get("pts", 0)) + inside
	t.bad = int(t.get("bad", 0)) + (1 if inside >= 3 else 0)


static func report_walk(t: Dictionary) -> String:
	var n := maxi(1, int(t.get("n", 0)))
	var names := ["head front", "head L", "head R", "thorax L", "thorax R", "thorax top", "waist L", "waist R", "gaster L", "gaster R", "gaster top", "gaster tip"]
	var parts := []
	var by: Array = t.get("by_pt", [])
	for i in by.size():
		parts.append("%s %.0f%%" % [names[i], 100.0 * int(by[i]) / n])
	print("  queen body per frame: most %.2f voxels, %.1f degrees; frames over 3 degrees or 0.25 voxels %d (%.1f%%); mean turn %.2f degrees" % [float(t.get("max_move", 0.0)), float(t.get("max_ang", 0.0)),
		int(t.get("jerks", 0)), 100.0 * int(t.get("jerks", 0)) / n, float(t.get("sum_ang", 0.0)) / n])
	return "queen walk: %d frames walking, any point in the soil %.1f%%, 3+ points %.1f%%, points in the soil %.1f%%\n  on a shaft's wall %d frames (%d with a point in the soil); room to her left %.2f, right %.2f voxels\n  %s" % [
		int(t.get("n", 0)), 100.0 * int(t.get("frames", 0)) / n, 100.0 * int(t.get("bad", 0)) / n,
		100.0 * int(t.get("pts", 0)) / (n * BODY.size()), int(t.get("wall_n", 0)), int(t.get("wall_hit", 0)), float(t.get("room_l", 0.0)) / n, float(t.get("room_r", 0.0)) / n, ", ".join(parts)]
