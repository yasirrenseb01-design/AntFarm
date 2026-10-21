extends RefCounted
## Dev (--bodies, with --seq, nest view): how often drawn bodies are inside one another, measured in 3D from the
## models' real shapes (worker_lo.antmesh: head, thorax, gaster as spheres; a larva's curved body, a cocoon, an
## egg) - not the flat discs the nest view keeps apart with. Counts only what is on screen.
##   ant in brood: a nestmate's body more than BITE into an egg, larva or cocoon (by what the ant is doing)
##   ant in ant: two nestmates' bodies more than BITE into each other (by what the two are doing)
##   feet in the air: a standing ant whose two front feet (or more than two feet) have no ground under them


const BITE := 0.12                 # model units (~0.18 mm): less than this is touching, not inside
const DEEP := 0.3                  # well inside: plain to see
# a worker's body (model units, size 1; x forward, y up from its feet): centre, radius
const ANT_BODY := [[Vector3(0.85, 0.4, 0), 0.27], [Vector3(0.2, 0.38, 0), 0.22],
	[Vector3(-0.6, 0.36, 0), 0.4], [Vector3(-1.05, 0.37, 0), 0.4], [Vector3(-1.35, 0.36, 0), 0.25]]
# where its six feet stand (model units): front pair first
const FEET := [Vector3(0.9, 0.0, 1.0), Vector3(0.9, 0.0, -1.0), Vector3(0.1, 0.0, 1.05), Vector3(0.1, 0.0, -1.05),
	Vector3(-0.85, 0.0, 1.05), Vector3(-0.85, 0.0, -1.05)]


## Its body as the shader draws it: the head turned at the neck by its bend (up +), the gaster at the waist by its
## resting curl less its bend (nest_rest.NECK / WAIST / GASTER_CURL, ant_core.gdshaderinc).
static func _ant_spheres(xf: Transform3D, bend := Vector2.ZERO, lat := 0.0) -> Array:
	var out := []
	var s := xf.basis.x.length()
	for k in ANT_BODY.size():
		var c: Vector3 = ANT_BODY[k][0]
		if k == 0:
			var hq := (Vector2(c.x, c.y) - Vector2(0.46, 0.39)).rotated(bend.y) + Vector2(0.46, 0.39)
			c = Vector3(hq.x, hq.y, c.z)
			c = _yaw_about(c, 0.46, lat)                  # (turned at the neck into a bend: rot_y(lat))
		elif k >= 3:
			var gq := (Vector2(c.x, c.y) - Vector2(-0.31, 0.36)).rotated(0.1 - bend.x) + Vector2(-0.31, 0.36)
			c = Vector3(gq.x, gq.y, c.z)
			c = _yaw_about(c, -0.31, -0.8 * lat)          # (the gaster swung out round the bend: rot_y(-0.8 lat))
		out.append([xf * c, float(ANT_BODY[k][1]) * s])
	return out


## p turned about the vertical through x = px by the shader's rot_y(a).
static func _yaw_about(p: Vector3, px: float, a: float) -> Vector3:
	if a == 0.0:
		return p
	var dx := p.x - px
	return Vector3(px + cos(a) * dx + sin(a) * p.z, p.y, -sin(a) * dx + cos(a) * p.z)


## A larva as the nest view draws it (mesh_kit.larva, the same curve as nest_piles._larva_pts): seven spheres.
static func _larva_spheres(xf: Transform3D) -> Array:
	var out := []
	var s := xf.basis.x.length()
	for i in 7:
		var t := float(i) / 6.0
		var th := lerpf(-0.75, 0.95, t)
		var r := maxf(0.36 * sin(lerpf(0.35, 2.75, t)), 0.1)
		out.append([xf * Vector3(sin(th) * 1.15, r * 0.95, (1.0 - cos(th)) * 0.55 - 0.18), r * s])
	return out


static func _cocoon_spheres(xf: Transform3D) -> Array:
	var s := xf.basis.x.length()
	return [[xf * Vector3(0.75, 0, 0), 0.55 * s], [xf * Vector3(0, 0, 0), 0.6 * s], [xf * Vector3(-0.75, 0, 0), 0.55 * s]]


## Which parts of two ants are deepest in each other (head, thorax, waist, gaster, gaster tip), e.g. "H-G".
static func _parts(a: Array, b: Array) -> String:
	var worst := -INF
	var w := []
	for i in a.size():
		for j in b.size():
			var d := float(a[i][1]) + float(b[j][1]) - (a[i][0] as Vector3).distance_to(b[j][0])
			if d > worst:
				worst = d
				w = ["HTWGt"[i], "HTWGt"[j]]
	w.sort()
	return "%s-%s" % w


static func _depth(a: Array, b: Array) -> float:
	var worst := 0.0
	for p in a:
		for q in b:
			worst = maxf(worst, float(p[1]) + float(q[1]) - (p[0] as Vector3).distance_to(q[0]))
	return worst


## Its sideways bend as the shader gets it (clock_z: in steps of 0.04, none under 0.02).
static func _lat(m: Dictionary) -> float:
	var l := float(m.get("lat", 0.0))
	return 0.0 if absf(l) < 0.02 else clampf(roundf(l / 0.04), -10.0, 10.0) * 0.04


## What a nestmate is doing, for the tallies.
static func _kind(nv, m: Dictionary) -> String:
	if m.has("script"):
		return "scripted"
	if float(m.get("over", 0.0)) > 0.1 and m.has("over_on"):
		return "climbing"
	if float(m.get("over", 0.0)) > 0.05:
		return "crossing"                         # (up on the brood: lifted onto it, not only on a cell by it)
	if m.get("carry", false):
		return "carrying"
	var still: bool = float(m.get("mv", 0.0)) < 0.3
	var tends: bool = nv._tends_brood(m)
	if still:
		# resting where it stopped / held up by one in its way / stopped to meet, groom or feed
		if int(m.get("act", 0)) in nv.STILL_ACTS:
			return ("tending " if tends else "") + "meeting"
		if int(m.get("rest", 0)) > 0 and (m.get("settle", []) as Array).is_empty():
			return ("tending " if tends else "") + "resting"
		return ("tending " if tends else "") + "waiting"
	return ("tending " if tends else "") + "walking"


static func measure(nv, tally: Dictionary) -> void:
	var brood := []                                   # [spheres, centre, kind]
	for i in nv._larva_mm.instance_count:
		var x: Transform3D = nv._larva_mm.get_instance_transform(i)
		if nv._shown(x):
			brood.append([_larva_spheres(x), x.origin, "larva"])
	for i in nv._pupa_mm.instance_count:
		var x: Transform3D = nv._pupa_mm.get_instance_transform(i)
		if nv._shown(x):
			brood.append([_cocoon_spheres(x), x.origin, "cocoon"])
	for i in nv._egg_mm.instance_count:
		var x: Transform3D = nv._egg_mm.get_instance_transform(i)
		if nv._shown(x):
			brood.append([[[x.origin, 0.25 * x.basis.x.length()]], x.origin, "egg"])
	var ants := []
	for m in nv._mates:
		if m.has("xf") and nv._shown(m.xf):
			ants.append(m)
	# brood in brood (two cocoons, a cocoon in a larva ...), and brood in the queen's body
	tally.brood_items = int(tally.get("brood_items", 0)) + brood.size()
	for i in brood.size():
		for j in range(i + 1, brood.size()):
			if (brood[i][1] as Vector3).distance_squared_to(brood[j][1]) > 9.0:
				continue
			var d := _depth(brood[i][0], brood[j][0])
			if d > BITE:
				var key := "brood in brood: %s" % "+".join([brood[i][2], brood[j][2]] if brood[i][2] < brood[j][2] else [brood[j][2], brood[i][2]])
				tally[key] = int(tally.get(key, 0)) + 1
				tally.brood_brood = int(tally.get("brood_brood", 0)) + 1
				_worst(tally, "brood2", d, brood[i][1], key)
				if tally.has("trace") and int(tally.get("frames", 0)) % 10 == 5:
					var pi = nv._placed_at(brood[i][1])
					var pj = nv._placed_at(brood[j][1])
					print("  overlap %.2f %s at %s / %s  | %s | %s" % [d, key, brood[i][1], brood[j][1], pi, pj])
	if nv._queen_mm.instance_count > 0:
		var qx: Transform3D = nv._queen_xf
		var qs := []
		for k in 7:
			var t := float(k) / 6.0
			qs.append([qx * nv.QUEEN_HEAD.lerp(nv.QUEEN_TAIL, t), nv.QUEEN_R * 0.75])
		for b in brood:
			if qx.origin.distance_squared_to(b[1]) < 36.0 and _depth(qs, b[0]) > BITE:
				var key := "brood in the queen: %s" % b[2]
				tally[key] = int(tally.get(key, 0)) + 1
				tally.brood_queen = int(tally.get("brood_queen", 0)) + 1
	tally.frames = int(tally.get("frames", 0)) + 1
	tally.ant_frames = int(tally.get("ant_frames", 0)) + ants.size()
	# diggers drawn in the air: no soil next to the cell their body is in (the simulation lets them cut across a
	# tunnel's middle on the way to planned work)
	for v in nv._dig_vis.values():
		if v.has("xf"):
			var o: Vector3 = (v.xf as Transform3D).origin
			tally.dig_frames = int(tally.get("dig_frames", 0)) + 1
			if float(v.get("still", 0.0)) > 0.25:
				tally.dig_at_face = int(tally.get("dig_at_face", 0)) + 1      # (drawn biting at the face: ACT_DIG)
			var u: Vector3 = (v.xf as Transform3D).basis.y.normalized()
			var lo: Vector3 = o - u * 0.7             # (its feet: the body is drawn ~0.4 above the surface)
			if not nv._walkable(Vector3i(roundi(o.x), roundi(o.y), roundi(o.z))) and not nv._walkable(Vector3i(roundi(lo.x), roundi(lo.y), roundi(lo.z))):
				tally.dig_air = int(tally.get("dig_air", 0)) + 1
	var sph := []
	for m in ants:
		sph.append(_ant_spheres(m.xf, m.get("bend", Vector2.ZERO), _lat(m)))
	# ants in the brood
	for i in ants.size():
		var m: Dictionary = ants[i]
		var o: Vector3 = (m.xf as Transform3D).origin
		var worst := 0.0
		var what := ""
		for b in brood:
			if o.distance_squared_to(b[1]) > 9.0:
				continue
			var d := _depth(sph[i], b[0])
			if d > worst:
				worst = d
				what = b[2]
		if worst > DEEP:
			tally.in_brood_deep = int(tally.get("in_brood_deep", 0)) + 1
		if worst > BITE:
			_worst(tally, "brood", worst, o, "%s in a %s" % [_kind(nv, m), what])
			var key := "in brood: %s (%s)" % [_kind(nv, m), what]
			tally[key] = int(tally.get(key, 0)) + 1
			tally.in_brood = int(tally.get("in_brood", 0)) + 1
			tally.in_brood_depth = float(tally.get("in_brood_depth", 0.0)) + worst
	# ants in ants
	for i in ants.size():
		var oi: Vector3 = (ants[i].xf as Transform3D).origin
		for j in range(i + 1, ants.size()):
			if oi.distance_squared_to((ants[j].xf as Transform3D).origin) > 12.0:
				continue
			var d := _depth(sph[i], sph[j])
			if d > DEEP:
				tally.in_ant_deep = int(tally.get("in_ant_deep", 0)) + 1
			if d > BITE:
				var ka := _kind(nv, ants[i])
				var kb := _kind(nv, ants[j])
				_worst(tally, "ant", d, oi.lerp((ants[j].xf as Transform3D).origin, 0.5), "%s + %s | %s | %s" % [ka, kb, _why(ants[i]), _why(ants[j])])
				var key := "in ant: %s + %s" % ([ka, kb] if ka < kb else [kb, ka])
				if ka == "climbing" or kb == "climbing":
					var c: Dictionary = ants[i] if ka == "climbing" else ants[j]
					var u: Dictionary = ants[j] if ka == "climbing" else ants[i]
					var cs: Array = sph[i] if ka == "climbing" else sph[j]
					var us: Array = sph[j] if ka == "climbing" else sph[i]
					var rel: float = ((u.xf as Transform3D).origin - (c.xf as Transform3D).origin).dot((c.xf as Transform3D).basis.y.normalized())
					key += " - %s, climber %s-%s, other %+.1f up, over %.2f hold %.1f" % ["the one it is on" if is_same(c.get("over_on"), u) else "another",
						_parts(cs, []) if false else "", "", rel, float(c.get("over", 0.0)), float(c.get("over_hold", 0.0))]
					key = key.substr(0, key.find(", over")) + " " + _parts(cs, us)
					_worst(tally, "climb", d, (c.xf as Transform3D).origin, "%s | want %s over %.2f hs %.2f clr %.2f gfit %.2f" % [key, c.get("cw"), float(c.get("over", 0.0)),
						float(c.get("hs", 0.0)), float(c.get("clr", 0.0)), (c.get("gfit", PackedFloat32Array([0])) as PackedFloat32Array)[0]])
				if ka == "resting" and kb == "resting":
					key += " " + _parts(sph[i], sph[j]) + " sep %.1f/%.1f push %.2f/%.2f" % [(ants[i].get("sep", Vector3.ZERO) as Vector3).length(), (ants[j].get("sep", Vector3.ZERO) as Vector3).length(),
						(ants[i].get("ka_push", Vector3.ZERO) as Vector3).length(), (ants[j].get("ka_push", Vector3.ZERO) as Vector3).length()]
					key = key.substr(0, key.length() - 2) if false else key
				if ka == "walking" and kb == "walking":
					# (which way the two are going: one behind the other, meeting head on, or across; in a narrow tunnel?)
					var fa: Vector3 = (ants[i].xf as Transform3D).basis.x.normalized()
					var fb: Vector3 = (ants[j].xf as Transform3D).basis.x.normalized()
					var dd := fa.dot(fb)
					var how := "same way" if dd > 0.5 else ("head on" if dd < -0.5 else "across")
					var nar: bool = ants[i].get("narrow", false) or ants[j].get("narrow", false)
					key += " - %s%s" % [how, ", narrow" if nar else ""]
					if ants[i].has("over_on") or ants[j].has("over_on"):
						key += " [about to climb / held low]"
					var ga := float(ants[i].get("fgap", 1.0)) < 0.3
					var gb := float(ants[j].get("fgap", 1.0)) < 0.3
					key += " " + _parts(sph[i], sph[j]) + (" mutual" if ga and gb else (" one-waits" if ga or gb else " neither-waits"))
				tally[key] = int(tally.get(key, 0)) + 1
				tally.in_ant = int(tally.get("in_ant", 0)) + 1
				tally.in_ant_depth = float(tally.get("in_ant_depth", 0.0)) + d
	# bodies in the soil: the middle of its head, thorax or gaster in the soil (plainly buried, not a leg tip)
	for i in ants.size():
		var m: Dictionary = ants[i]
		var buried := ""
		for k in [0, 1, 3]:
			if nv._density_at(sph[i][k][0]) >= 0.5:
				buried += "HTWGt"[k]
		if buried != "":
			var key := "in soil: %s (%s)" % [_kind(nv, m), buried]
			tally[key] = int(tally.get(key, 0)) + 1
			var kd := _kind(nv, m)
			if kd in ["walking", "waiting", "meeting"] and m.has("from"):
				# (why: its drawn middle off its path, its heading off the way the path goes, in a narrow tunnel, its
				# middle itself in the soil, its up off the cell's)
				var x: Transform3D = m.xf
				var pth: Vector3 = (m.from as Vector3).lerp(m.to, clampf(float(m.t), 0.0, 1.0))
				var dirv: Vector3 = (m.to as Vector3) - (m.from as Vector3)
				var off := ((x.origin + x.basis.y.normalized() * 0.4) - pth).length()
				var ang := 0.0
				if dirv.length() > 0.01:
					ang = rad_to_deg(x.basis.x.normalized().angle_to(dirv.normalized()))
				var so: Vector3 = m.get("soil_off", Vector3.ZERO)
				var why := "%s narrow=%s soil-shift>%s soil-turn=%s up.y>%s mid-in-soil=%s near-ant=%s" % [kd, m.get("narrow", false),
					"0.9" if so.length() > 0.9 else ("0.3" if so.length() > 0.3 else "0"), absf(float(m.get("soil_yaw", 0.0))) > 0.1,
					"0.7" if x.basis.y.normalized().y > 0.7 else ("-0.3" if x.basis.y.normalized().y > -0.3 else "ceiling"),
					nv._density_at(x.origin + x.basis.y.normalized() * 0.38) >= 0.5, float(m.get("fgap", 1.0)) < 1.0]
				tally["why: " + why] = int(tally.get("why: " + why, 0)) + 1
			tally.in_soil = int(tally.get("in_soil", 0)) + 1
			var clr: Vector2 = nv._soil_clearance(m.xf, float(m.size), m.get("bend", Vector2.ZERO))
			if _kind(nv, m) in ["climbing", "crossing"]:
				_worst(tally, "soilclimb", float(buried.length()) + randf() * 0.1, (m.xf as Transform3D).origin, "%s %s | rise %.2f stuck %d over %.2f tip %.2f cw %s gfit %s clr %.2f up.y %.2f narrow %s" % [_kind(nv, m), buried,
					clr.x, int(clr.y), float(m.get("over", 0.0)), float(m.get("over_tip", 0.0)), m.get("cw"), m.get("gfit"), float(m.get("clr", 0.0)),
					(m.xf as Transform3D).basis.y.normalized().y, m.get("narrow", false)])
			if _kind(nv, m) in ["resting", "tending resting"]:
				_worst(tally, "soilstill", float(buried.length()) + randf() * 0.1, (m.xf as Transform3D).origin, "%s | rise %.2f stuck %d clr_t %.2f wall_n %d rest_dir %s act %d face %s settle %d | %s" % [buried,
					clr.x, int(clr.y), float(m.get("clr_t", 0.0)), int(m.get("wall_n", 0)), m.get("rest_dir", Vector3.ZERO) != Vector3.ZERO, int(m.act),
					(m.get("face", Vector3.INF) as Vector3) != Vector3.INF, (m.get("settle", []) as Array).size(), _why(m)])
			_worst(tally, "soil", float(buried.length()), (m.xf as Transform3D).origin, "%s %s | rise %.2f stuck %d clr %.2f clr_own %.2f gfit %s tip %.2f | %s" % [_kind(nv, m),
				buried, clr.x, int(clr.y), float(m.get("clr", 0.0)), float(m.get("clr_own", 0.0)), m.get("gfit"), float(m.get("over_tip", 0.0)), _why(m)])
	# feet in the air (standing ants: a walking ant lifts its feet anyway)
	for m in ants:
		if float(m.get("mv", 0.0)) > 0.3 or float(m.get("over", 0.0)) > 0.1:
			continue
		var x: Transform3D = m.xf
		var up := x.basis.y.normalized()
		var free := 0
		var front := 0
		for k in FEET.size():
			var f: Vector3 = x * (FEET[k] as Vector3)
			var ground := false
			for h in [0.05, 0.2, 0.35, 0.5]:          # (the ground below the foot)
				if nv._density_at(f - up * h) >= 0.5:
					ground = true
					break
			if not ground and not _on_body(nv, f, up, m):
				free += 1
				if k < 2:
					front += 1
		if front == 2 or free > 2:
			_worst(tally, "feet", float(free) + (3.0 if front == 2 else 0.0), x.origin, "%s, %d feet free%s | %s" % [_kind(nv, m), free, " (both front)" if front == 2 else "", _why(m)])
			var key := "feet in the air: %s%s" % [_kind(nv, m), " (front)" if front == 2 else ""]
			tally[key] = int(tally.get(key, 0)) + 1
			tally.feet_air = int(tally.get("feet_air", 0)) + 1


## Why an ant is where it is drawn (dev): its pace allowed by what is ahead, how long it has been held up, how far
## it is pushed off its path, its drawn body behind its path point, stepping or not.
static func _why(m: Dictionary) -> String:
	var pth: Vector3 = (m.from as Vector3).lerp(m.to, clampf(float(m.t), 0.0, 1.0)) if m.has("from") else Vector3.ZERO
	return "wid %d push %.2f ka_t %.2f partner %s gap %.2f blocked %.1f sep %.2f lag %.2f mv %.2f rest %d over %.2f on %s cross %s" % [int(m.get("wid", -1)), (m.get("ka_push", Vector3.ZERO) as Vector3).length(), float(m.get("ka_t", 0.0)), m.has("partner"), float(m.get("fgap", 1.0)),
		float(m.get("blocked_t", 0.0)), (m.get("sep", Vector3.ZERO) as Vector3).length(), pth.distance_to(m.get("vp", pth)), float(m.get("mv", 0.0)),
		int(m.get("rest", 0)), float(m.get("over", 0.0)), m.has("over_on"), m.has("cross_on")]


## The worst case of each kind this frame (where, how deep, what): for --follow-bodies to look at.
static func _worst(tally: Dictionary, kind: String, depth: float, at: Vector3, what: String) -> void:
	var w: Dictionary = tally.get("worst", {})
	if not w.has(kind) or float(w[kind][0]) < depth:
		w[kind] = [depth, at, what]
	tally.worst = w


## Whether a foot at f rests on something other than soil: another ant's back, or the brood.
static func _on_body(nv, f: Vector3, up: Vector3, m: Dictionary) -> bool:
	for o in nv._mates:
		if is_same(o, m) or not o.has("xf") or (o.xf as Transform3D).origin.distance_squared_to(f) > 6.0:
			continue
		for s in _ant_spheres(o.xf, o.get("bend", Vector2.ZERO), _lat(o)):
			if (s[0] as Vector3).distance_to(f - up * 0.1) < float(s[1]) + 0.15:
				return true
	for b in nv._brood_near(f):
		if nv._brood_offset(f, b).length() < float(b[3] if b.size() > 3 else b[1]) + 0.5:
			return true
	return false


static func report(tally: Dictionary) -> String:
	var n := maxf(1.0, float(tally.get("ant_frames", 0)))
	var lines := ["bodies over %d frames, %d ant-frames on screen:" % [int(tally.get("frames", 0)), int(n)],
		"  ant in brood %.2f%% of ant-frames (mean depth %.2f; deep %.2f%%)" % [100.0 * float(tally.get("in_brood", 0)) / n, float(tally.get("in_brood_depth", 0.0)) / maxf(1.0, float(tally.get("in_brood", 0))),
			100.0 * float(tally.get("in_brood_deep", 0)) / n],
		"  ant in ant %.2f pairs per 100 ant-frames (mean depth %.2f; deep %.2f)" % [100.0 * float(tally.get("in_ant", 0)) / n, float(tally.get("in_ant_depth", 0.0)) / maxf(1.0, float(tally.get("in_ant", 0))),
			100.0 * float(tally.get("in_ant_deep", 0)) / n],
		"  feet in the air %.2f%% of ant-frames" % [100.0 * float(tally.get("feet_air", 0)) / n],
		"  body in the soil %.2f%% of ant-frames" % [100.0 * float(tally.get("in_soil", 0)) / n],
		"  brood in brood %.2f pairs per 100 brood-frames, brood in the queen %.2f per 100" % [100.0 * float(tally.get("brood_brood", 0)) / maxf(1.0, float(tally.get("brood_items", 0))), 100.0 * float(tally.get("brood_queen", 0)) / maxf(1.0, float(tally.get("brood_items", 0)))],
		"  diggers in the air %.2f%% of %d digger-frames, at the face digging %.1f%%" % [100.0 * float(tally.get("dig_air", 0)) / maxf(1.0, float(tally.get("dig_frames", 0))), int(tally.get("dig_frames", 0)),
			100.0 * float(tally.get("dig_at_face", 0)) / maxf(1.0, float(tally.get("dig_frames", 0)))]]
	var keys := tally.keys().filter(func(k): return String(k).contains(":"))
	keys.sort_custom(func(a, b): return int(tally[a]) > int(tally[b]))
	for k in keys:
		lines.append("    %5d  %s" % [int(tally[k]), k])
	return "\n".join(lines)


## (--bodies, outworld) foragers drawn inside one another on the ground, the food and the plants: every ant out in the
## plot this frame (not only those on screen), by what the two are doing. Ants clinging to an enemy are left out.
static func measure_out(ow, sim, tally: Dictionary) -> void:
	var ants := []
	for a in sim.outside:
		if a.state == 0 or a.dead or a.vpos.x == INF or not (a.vxf is Transform3D) or (a.act == 22 and a.busy > 0):
			continue
		if a.state == 5 and a.busy > 0:
			continue
		ants.append(a)
	tally.frames = int(tally.get("frames", 0)) + 1
	tally.ant_frames = int(tally.get("ant_frames", 0)) + ants.size()
	var sph := []
	for a in ants:
		sph.append(_ant_spheres(a.vxf))
	for i in ants.size():
		var oi: Vector3 = (ants[i].vxf as Transform3D).origin
		for j in range(i + 1, ants.size()):
			if oi.distance_squared_to((ants[j].vxf as Transform3D).origin) > 12.0:
				continue
			var d := _depth(sph[i], sph[j])
			if d > DEEP:
				tally.in_ant_deep = int(tally.get("in_ant_deep", 0)) + 1
			if d > BITE:
				var ka := _out_kind(ants[i])
				var kb := _out_kind(ants[j])
				_worst(tally, "ant", d, oi.lerp((ants[j].vxf as Transform3D).origin, 0.5), "%s + %s" % [ka, kb])
				if tally.has("trace") and d > DEEP:
					for x in [ants[i], ants[j]]:
						print("  deep %.2f  id %d st %d act %d busy %d vfeed %.2f vrim %s voff %.1f food %s d-pos %.1f" % [d, x.id, x.state, x.act, x.busy,
							x.vfeed, str(snappedf(x.vrim, 0.01)) if x.vrim != INF else "-", x.voff.length(), x.vfood != Vector2(INF, INF),
							(Vector2(x.vxf.origin.x, x.vxf.origin.z) * 3.0).distance_to(x.pos)])
				var key := "in ant: %s + %s" % ([ka, kb] if ka < kb else [kb, ka])
				tally[key] = int(tally.get(key, 0)) + 1
				tally.in_ant = int(tally.get("in_ant", 0)) + 1
				tally.in_ant_depth = float(tally.get("in_ant_depth", 0.0)) + d


static func _out_kind(a) -> String:
	if a.busy > 0 and a.act in [2, 9, 10]:
		return ["", "", "cutting", "", "", "", "", "", "", "milking", "drinking"][a.act]
	if a.busy > 0:
		return "busy %d" % a.act
	if a.state == 6:
		return "hauling"
	return "walking"
