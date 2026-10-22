extends RefCounted
## (--feet, dev) how the drawn bodies move from frame to frame: the legs' step rate and walking speed, bodies
## bobbing up and down, heads and gasters swaying on ants standing still, and over about a second an ant that stays
## put swinging its heading or bend to and fro (split from foot_check.gd in v0.11.26).


static func measure(nv, tally: Dictionary) -> void:
	var mm: MultiMesh = nv._ant_mm
	# how fast the legs step: the gait phase turned per second (one turn = one step of each leg), walking ants only,
	# and how fast they walk (body lengths a second)
	var dt: float = nv.get_process_delta_time()
	var gprev: Dictionary = tally.get("gait_prev", {})
	var gnow := {}
	for i in mm.instance_count:
		var cu := mm.get_instance_custom_data(i)
		var g := cu.r - floorf(cu.r / 512.0) * 512.0
		var w := cu.a - floorf(cu.a / 1000.0) * 1000.0
		var mvv := w - floorf(w) if floorf(w) >= 1.0 else w
		var X := mm.get_instance_transform(i)
		gnow[i] = [g, X.origin]
		if gprev.has(i) and mvv > 0.8 and dt > 0.0:
			var dg: float = fposmod(g - float(gprev[i][0]), TAU * 64.0)
			var dp: float = X.origin.distance_to(gprev[i][1])
			if dg < 3.0 and dp < 0.6:
				tally.g_sum = float(tally.get("g_sum", 0.0)) + dg / TAU / dt
				tally.v_sum = float(tally.get("v_sum", 0.0)) + dp / dt / (2.6 * X.basis.x.length())
				tally.g_n = int(tally.get("g_n", 0)) + 1
	tally.gait_prev = gnow
	# the body bobbing: up and down along its up by more than 0.01, then the other way next frame
	var bprev: Dictionary = tally.get("bob_prev", {})
	var bnow := {}
	for i in mm.instance_count:
		var X := mm.get_instance_transform(i)
		var u := X.basis.y.normalized()
		var dv := 0.0
		if bprev.has(i) and (bprev[i][0] as Vector3).distance_to(X.origin) < 0.5:
			dv = (X.origin - (bprev[i][0] as Vector3)).dot(u)
			tally.bob_n = int(tally.get("bob_n", 0)) + 1
			if absf(dv) > 0.01 and absf(float(bprev[i][1])) > 0.01 and signf(dv) != signf(float(bprev[i][1])):
				tally.bob = int(tally.get("bob", 0)) + 1
		bnow[i] = [X.origin, dv]
	tally.bob_prev = bnow
	# head and gaster swaying on an ant standing still: its bend at the neck or the waist changing from frame to frame
	var wprev: Dictionary = tally.get("wob_prev", {})
	var wnow := {}
	for i in mm.instance_count:
		var cu := mm.get_instance_custom_data(i)
		var w := cu.a - floorf(cu.a / 1000.0) * 1000.0
		var mvv := w - floorf(w) if floorf(w) >= 1.0 else w
		var bcode := int(floorf(cu.r / 512.0))
		var X := mm.get_instance_transform(i)
		var hd := X.basis.x.normalized()
		wnow[i] = [bcode, X.origin, hd, 0.0]
		if mvv < 0.3 and wprev.has(i) and (wprev[i][1] as Vector3).distance_to(X.origin) < 0.08 and wprev[i].size() > 3:
			var turn := (wprev[i][2] as Vector3).signed_angle_to(hd, X.basis.y.normalized())
			wnow[i][3] = turn
			tally.sway_n = int(tally.get("sway_n", 0)) + 1
			if absf(turn) > 0.004 and absf(float(wprev[i][3])) > 0.004 and signf(turn) != signf(float(wprev[i][3])):
				tally.sway = int(tally.get("sway", 0)) + 1      # (turned one way, then back: swaying)
		if mvv < 0.05 and wprev.has(i) and (wprev[i][1] as Vector3).distance_to(X.origin) < 0.05:
			tally.wob_n = int(tally.get("wob_n", 0)) + 1
			if int(wprev[i][0]) != bcode:
				tally.wob = int(tally.get("wob", 0)) + 1
	tally.wob_prev = wnow
	# over about a second: an ant that stays where it is - how far its heading, its neck/waist bend and its sideways bend
	# swing back and forth (a wall beside it pushing it round and letting go)
	var tr_d: Dictionary = tally.get("track", {})
	var tr_new := {}
	for m in nv._mates:
		if not m.has("xf") or m.has("script"):
			continue
		var X: Transform3D = m.xf
		var hd := X.basis.x.normalized()
		var bd: Vector2 = m.get("bend", Vector2.ZERO)
		var id := int(m.get("wid", -1))
		var t: Array = tr_d.get(id, [])
		if t.is_empty() or (t[0][0] as Vector3).distance_to(X.origin) > 0.15:
			t = []
		t.append([X.origin, hd, bd, float(m.get("lat", 0.0)), float(m.get("soil_yaw", 0.0))])
		if t.size() >= 60:
			var amin := 0.0
			var amax := 0.0
			var bmin := Vector2(9, 9)
			var bmax := Vector2(-9, -9)
			var lmin := 9.0
			var lmax := -9.0
			for e in t:
				var a: float = (t[0][1] as Vector3).signed_angle_to(e[1], X.basis.y.normalized())
				amin = minf(amin, a)
				amax = maxf(amax, a)
				bmin = bmin.min(e[2]); bmax = bmax.max(e[2])
				lmin = minf(lmin, e[3]); lmax = maxf(lmax, e[3])
			var near_wall := false
			for q in [Vector3(0, 0.4, 0.6), Vector3(0, 0.4, -0.6), Vector3(0.9, 0.4, 0.5), Vector3(0.9, 0.4, -0.5), Vector3(-1.1, 0.4, 0.6), Vector3(-1.1, 0.4, -0.6)]:
				if nv._density_at(X * q) >= 0.5:
					near_wall = true
			var key := "wall" if near_wall else "open"
			tally["st_n:" + key] = int(tally.get("st_n:" + key, 0)) + 1
			# (swinging: back and forth - two turns of direction or more, each of at least the given size)
			var heads := []
			var gs := []
			var hs := []
			var ls := []
			for e in t:
				heads.append((t[0][1] as Vector3).signed_angle_to(e[1], X.basis.y.normalized()))
				gs.append((e[2] as Vector2).x)
				hs.append((e[2] as Vector2).y)
				ls.append(e[3])
			if _swings(heads, deg_to_rad(3.0)) >= 2:
				tally["st_turn:" + key] = int(tally.get("st_turn:" + key, 0)) + 1
				var sy := []
				for e in t:
					sy.append(e[4])
				var src := "pushed round by the soil" if _swings(sy, deg_to_rad(3.0)) >= 2 else "its own heading"
				tally["st_src:%s, %s" % [key, src]] = int(tally.get("st_src:%s, %s" % [key, src], 0)) + 1
			if _swings(gs, 0.05) >= 2 or _swings(hs, 0.05) >= 2:
				tally["st_bend:" + key] = int(tally.get("st_bend:" + key, 0)) + 1
			if _swings(ls, 0.04) >= 2:
				tally["st_lat:" + key] = int(tally.get("st_lat:" + key, 0)) + 1
			t = []
		tr_new[id] = t
	tally.track = tr_new


## How many times a series turns back by at least `step` (a swing to and fro is two).
static func _swings(v: Array, step: float) -> int:
	var n := 0
	var ext: float = v[0]
	var dir := 0
	for x in v:
		if dir >= 0 and float(x) > ext:
			ext = x
			dir = 1
		elif dir <= 0 and float(x) < ext:
			ext = x
			dir = -1
		elif dir == 1 and ext - float(x) >= step:
			n += 1
			dir = -1
			ext = x
		elif dir == -1 and float(x) - ext >= step:
			n += 1
			dir = 1
			ext = x
	return n
