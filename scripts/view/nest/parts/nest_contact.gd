extends "res://scripts/view/nest/parts/nest_rest.gd"
## Nest view, layer 8 of 10 (new in v0.8.63): bodies meeting - an ant looking ahead and waiting for the one in its
## way, climbing over a nestmate's back or onto the brood, worked out from the bodies' real shapes.


# a worker's body for climbing over another (model units, size 1; worker_lo.antmesh): [x, y above its feet,
# radius] - head, thorax, waist, gaster, gaster tip
const CLIMB_PARTS := [Vector3(0.85, 0.4, 0.27), Vector3(0.2, 0.38, 0.22), Vector3(-0.35, 0.33, 0.25),
	Vector3(-0.85, 0.36, 0.42), Vector3(-1.3, 0.36, 0.28)]


## Up on a nestmate's back, passing it in a narrow tunnel (`over_on`, set in _keep_apart), or up on the brood -
## crossing the pile, or a larva or cocoon it brushes: every frame each part of its body is kept above what is
## under it - so it climbs on head first (its body tipping nose up as the head rises), walks along the other's back
## with its legs straddling it, and steps down off the far end nose down. It used to be raised level by a fixed
## height after the two bodies had met, lower than the other's back (the gaster is ~0.8 high, it was lifted ~0.6):
## it came up through the other's body; on the brood only its middle was raised, its head and gaster were in the
## larvae. `tr` is where it is drawn before climbing; returns it raised and tipped.
func _climb(m: Dictionary, tr: Transform3D, md: float, at: float) -> Transform3D:
	var want := 0.0
	var tip := 0.0
	var up := tr.basis.y.normalized()
	var unders := []                                  # [centre, radius] of what it must keep above
	var o = m.get("over_on")
	var on_ant: bool = o != null and o.has("xf") and float(m.get("over_hold", 0.0)) > 0.0
	# (on a nestmate's back: what it needs is worked out 15 times a second, the height eased between - a crowd of
	# ants climbing over one another, each against all those round it, cost ~5 ms a frame every frame)
	m.climb_t = float(m.get("climb_t", 1.0)) + md
	if on_ant and float(m.climb_t) < 0.066 and m.has("cw"):
		return _climb_ease(m, tr, at, (m.cw as Vector2).x, (m.cw as Vector2).y)
	# (by the brood, as it was a frame or two ago: two frames in three it keeps that - most stand still there)
	if not on_ant and int(m.get("bc_gen", -1)) == _brood_gen and (_mate_frame + int(m.get("wid", 0))) % 3 != 0:
		return _climb_ease(m, tr, at, (m.cw as Vector2).x, (m.cw as Vector2).y)
	m.climb_t = 0.0
	if on_ant:
		# over the one it climbs onto, and once up on its back any other beside it (in a crowd its body came down into
		# a neighbour of the one it was on) - not before: a resting neighbour pressed against it lifted it straight up
		# before its head had reached the one it climbs; the bodies on the same surface (not one on a wall), not those
		# up on another's back
		var all_round := float(m.get("over", 0.0)) > 0.3
		var key := Vector3i(floori(tr.origin.x / 3.0), floori(tr.origin.y / 3.0), floori(tr.origin.z / 3.0))
		for off in _NEAR:
			for q in _near_bins.get(key + off, []):
				if is_same(q, m) or not q.has("xf") or is_same(q.get("over_on"), m) or float(q.get("over", 0.0)) > 0.1 and not is_same(q, o) \
						or not all_round and not is_same(q, o):
					continue
				var qx: Transform3D = q.xf
				if qx.origin.distance_squared_to(tr.origin) < 11.0 and qx.basis.y.normalized().dot(up) > 0.7:
					unders.append_array(_body_spheres(q))
	var tends := false
	var by_brood := not _brood_occ.is_empty() and up.y > 0.7 and _brood_wide.has(Vector3i(roundi(tr.origin.x), roundi(tr.origin.y + 0.4), roundi(tr.origin.z))) \
			and not m.has("script") or _on_brood(m)
	if not by_brood:
		m.erase("bc_gen")
		if not on_ant and float(m.get("over", 0.0)) <= 0.0 and float(m.get("over_tip", 0.0)) == 0.0:
			m.cw = Vector2.ZERO
			return tr                         # (nothing under it, and not up on anything: most ants, most frames)
	if by_brood:
		if unders.is_empty():
			# by the brood only (most of them, in a crowded founding cell): worked out again only once it has moved or
			# turned a little, or the brood is laid out again - a resting ant keeps what it had (300 ants round the
			# brood cost ~4 ms a frame worked out every frame)
			if int(m.get("bc_gen", -1)) != _brood_gen or (m.bc_at as Vector3).distance_squared_to(tr.origin) > 0.02 \
					or (m.bc_f as Vector3).dot(tr.basis.x) < 0.995 * tr.basis.x.length_squared():
				m.bc_gen = _brood_gen
				m.bc_at = tr.origin
				m.bc_f = tr.basis.x
				# (over the brood up to two cocoons high: a heap of them is ~2 units - capped at 1.3 the body stayed in it)
				m.bc = _headroom(tr, up, _need_lift(_climb_need(tr, _brood_spheres(tr.origin), up, _tends_brood(m)), float(m.size), 1.8))
			want = (m.bc as Vector2).x
			tip = (m.bc as Vector2).y
		else:
			tends = _tends_brood(m)
			unders.append_array(_brood_spheres(tr.origin))
	if not unders.is_empty():
		var need := _need_lift(_climb_need(tr, unders, up, tends), float(m.size))
		var lt := _headroom(tr, up, need)
		want = lt.x
		tip = lt.y
		# (no room to climb over it - a low chamber or tunnel: the one climbing came through the other's body
		# instead; it gives up climbing, and waits, rests where it is or goes another way - as in a jam)
		if on_ant and need.x - lt.x > 0.25 and float(m.get("over", 0.0)) < 0.3:
			m.erase("over_on")
			m.erase("cross_on")
			m.over_hold = 0.0
			m.no_climb_t = 3.0
			m.stop_here = not m.has("deliver") and not m.get("carry", false) and not m.get("leaving", false) and randf() < 0.5
	m.cw = Vector2(want, tip)
	return _climb_ease(m, tr, at, want, tip)


## `tr` raised by `want` and tipped by `tip` (see _climb), eased in the ants' own time `at` (slowed with the clock
## below 1x and in the cold, as their steps are: at 0.2x it rose at the full rate while it walked on five times slower,
## and looked pushed up). The height and the tip move like a body, not a lerp toward a target that jumps: they gather
## speed and settle (critically damped), so climbing on and stepping down flow - the user asked for smoother poses,
## 2026-10-16. Up a little quicker than down (its head must come up onto the other's back as it reaches it).
func _climb_ease(m: Dictionary, tr: Transform3D, at: float, want: float, tip: float) -> Transform3D:
	var ov0 := float(m.get("over", 0.0))
	var tp0 := float(m.get("over_tip", 0.0))
	if want <= 0.0 and ov0 <= 0.0 and tp0 == 0.0:
		m.over_v = 0.0
		m.tip_v = 0.0
		return tr                             # (nothing under it: nothing to ease)
	# (over a nestmate gently; onto the brood - which lies still, and is low - more briskly, else it walked into the
	# larvae before it was up)
	var brood_only: bool = not m.has("over_on")
	var hv := _spring(ov0, float(m.get("over_v", 0.0)), want, (20.0 if brood_only else 13.0) if want > ov0 else 8.0, at)
	# (never more than a quarter of a unit below what it needs - a body plainly inside the one under it - however
	# smooth: then it keeps up)
	var sink := 0.12 if brood_only else 0.25
	if hv.x < want - sink:
		hv = Vector2(want - sink, maxf(hv.y, 0.0))
	var ov := maxf(hv.x, 0.0)
	# (and never above the room there is where it is now: stepping down off the other's back it walks on, into a low
	# tunnel or up a wall, while still eased down - it was carried into the ceiling)
	if ov > 0.05:
		var room := _headroom(tr, tr.basis.y.normalized(), Vector2(ov, tp0)).x
		if room < ov:
			ov = room
			hv.y = minf(hv.y, 0.0)
	m.over = ov
	m.over_v = hv.y if ov > 0.0 else 0.0
	# (its legs step it up and down: rising onto the other's back - or stepping down off it - with its legs still, it
	# looked lifted by something under it; the height climbed drives the gait as distance walked does)
	var rise := absf(ov - ov0)
	if rise > 0.0005 and at > 0.0:
		var sz := float(m.size)
		m.gait = fmod(float(m.get("gait", 0.0)) + rise * 1.6 / (AntModel.stride_len(float(m.get("stride", 1.0))) * sz) * TAU, TAU * 64.0)
		m.mv = maxf(float(m.get("mv", 0.0)), clampf(rise / at / 0.4, 0.0, 1.0))
	var tv := _spring(tp0, float(m.get("tip_v", 0.0)), tip if want > 0.0 else 0.0, 12.0 if brood_only else 7.0, at)
	m.over_tip = tv.x
	m.tip_v = tv.y
	if ov <= 0.002 and absf(tv.x) < 0.005 and absf(tv.y) < 0.02 and want <= 0.0:
		m.over = 0.0
		m.over_tip = 0.0
		m.over_v = 0.0
		m.tip_v = 0.0
		if m.has("over_on") and float(m.get("over_hold", 0.0)) <= 0.0:
			m.erase("over_on")
		return tr
	var b2 := tr.basis
	if absf(float(m.over_tip)) > 0.002:
		b2 = b2.rotated(tr.basis.z.normalized(), float(m.over_tip))
	return Transform3D(b2, tr.origin + tr.basis.y.normalized() * ov)


## One step `dt` of a critically damped spring at x (speed v) toward `target`, stiffness w (1/s): [x, v] after it.
static func _spring(x: float, v: float, target: float, w: float, dt: float) -> Vector2:
	if dt <= 0.0:
		return Vector2(x, v)
	var e := exp(-w * dt)
	var d := x - target
	var c := v + w * d
	return Vector2(target + (d + c * dt) * e, (v - w * c * dt) * e)


## Out of the walls: its head, thorax or gaster in the soil - rounding a bend in a narrow tunnel its body, straight
## and longer than the bend is wide, cut the corner (its drawn middle lags its path by up to a cell, and its heading the
## way the path turns) - and it is shifted away from the soil and turned a little to lie along the tunnel: the soil's
## slope at each part that is in it says which way is out, and how far. Kept and eased like the shift that keeps
## nestmates apart (what still is in the soil is added on, and it relaxes once clear), so it does not tremble.
## Walking ants were in the soil ~2,000 times per 4 test runs, waiting and meeting ones ~300 (user, 2026-10-16).
const _SOIL_PTS := [Vector3(0.85, 0.4, 0.0), Vector3(0.2, 0.38, 0.0), Vector3(-0.85, 0.35, 0.0), Vector3(-1.2, 0.33, 0.0),
	# (and its body's surface - the sides and the top of head, thorax and gaster, the ends: checked by the middle only,
	# a resting ant's gaster lay in the wall beside it, a nurse's in a low chamber's roof; v0.11.25, the keeper 2026-10-22)
	Vector3(1.01, 0.4, 0.0), Vector3(0.85, 0.4, 0.16), Vector3(0.85, 0.4, -0.16), Vector3(0.85, 0.56, 0.0),
	Vector3(0.2, 0.38, 0.13), Vector3(0.2, 0.38, -0.13), Vector3(0.2, 0.51, 0.0),
	Vector3(-0.6, 0.36, 0.24), Vector3(-0.6, 0.36, -0.24), Vector3(-0.6, 0.6, 0.0),
	Vector3(-1.05, 0.37, 0.24), Vector3(-1.05, 0.37, -0.24), Vector3(-1.05, 0.61, 0.0),
	Vector3(-1.5, 0.36, 0.0), Vector3(-1.35, 0.36, 0.15), Vector3(-1.35, 0.36, -0.15)]
func _soil_push(m: Dictionary, tr: Transform3D, md: float) -> Transform3D:
	if m.has("script") or md <= 0.0:
		return tr
	_soil_bend(m, tr, md)
	var up := tr.basis.y.normalized()
	var off: Vector3 = m.get("soil_off", Vector3.ZERO)
	var yaw := float(m.get("soil_yaw", 0.0))
	# (looked at every other frame while it walks, every third standing still - keeping the shift it has between: ~2 ms
	# a frame with 300 ants in a small nest, every frame for each)
	var moving := float(m.get("mv", 0.0)) > 0.3
	m.soil_t = float(m.get("soil_t", 0.0)) + md
	var touching := off != Vector3.ZERO or yaw != 0.0
	if float(m.soil_t) < (0.0 if moving else 0.05):      # (walking: every frame - every other, it was in the wall of a bend a frame before it was pushed)
		if off == Vector3.ZERO and yaw == 0.0:
			return tr
		var tk := tr                             # (as it was shifted and turned last time)
		if yaw != 0.0:
			tk.basis = tk.basis.rotated(up, yaw)
		tk.origin += off
		return tk
	var sdt := float(m.soil_t)              # (the time since it was last looked at: the easing below is over that)
	m.soil_t = 0.0
	var off0 := off
	var yaw0 := yaw
	var t2 := tr
	if yaw != 0.0:
		t2.basis = t2.basis.rotated(up, yaw)
	t2.origin += off
	var side := t2.basis.z.normalized()
	var push := Vector3.ZERO
	var torque := 0.0
	var hits := 0
	var bend: Vector2 = m.get("bend", Vector2.ZERO)
	var lat := float(m.get("lat", 0.0))
	for q0 in _SOIL_PTS:
		var q: Vector3 = _bent(q0, bend, lat)
		var c: Vector3 = t2 * q
		if _density_at(c) < 0.45:
			continue
		var g := Vector3(_density_at(c + Vector3(0.2, 0, 0)) - _density_at(c - Vector3(0.2, 0, 0)),
			_density_at(c + Vector3(0, 0.2, 0)) - _density_at(c - Vector3(0, 0.2, 0)),
			_density_at(c + Vector3(0, 0, 0.2)) - _density_at(c - Vector3(0, 0, 0.2)))
		# (out sideways or ahead/behind - along its up is the ground fit's - unless the soil is mostly above or below
		# it: a low ceiling, or the floor of a bend rising into its head; then out that way too, at half the rate)
		var gp := g - up * g.dot(up)
		if gp.length_squared() < 0.25 * g.length_squared():
			gp = gp + up * g.dot(up) * 0.5
		g = gp
		if g.length_squared() < 0.000001:
			continue
		var out := -g.normalized()
		var d := 0.1
		while d < 0.7 and _density_at(c + out * d) >= 0.5:
			d += 0.1
		push += out * d
		torque += out.dot(side) * d * signf(q.x)
		hits += 1
	if hits > 0:
		# (not toward a nestmate beside it: the shift that keeps them apart pushed it to the wall, this pushed it back,
		# and the two together held it in the other's body - two passing in a tunnel walked through each other)
		push /= float(hits)
		var key := Vector3i(floori(t2.origin.x / 3.0), floori(t2.origin.y / 3.0), floori(t2.origin.z / 3.0))
		for o2 in _NEAR:
			for q in _near_bins.get(key + o2, []):
				if is_same(q, m) or not q.has("xf") or float(q.get("over", 0.0)) > 0.1 or float(m.get("over", 0.0)) > 0.1:
					continue
				var to: Vector3 = (q.xf as Transform3D).origin - t2.origin
				to -= up * to.dot(up)
				var dist := to.length()
				if dist < 0.01 or dist > 1.8 * float(m.size):
					continue
				var dirq := to / dist
				var toward := push.dot(dirq)
				if toward > 0.0:
					push -= dirq * toward * clampf((1.8 * float(m.size) - dist) / (0.6 * float(m.size)), 0.0, 1.0)
		# (add on what is still in the soil: the shift so far is already in t2; turned toward lying along the tunnel -
		# head pushed one way, gaster the other: it turns, about the vertical through its middle)
		var want := (off + push).limit_length(1.0)
		if _density_at(tr.origin + want + up * 0.4) >= 0.5:
			want *= 0.5                          # (never its middle into the soil instead)
		# (nor off the edge of the floor it stands on, out over a shaft or a drop: pushed clear of a wall beside the lip,
		# it was drawn hanging in the open, legs reaching for nothing)
		for k in 3:
			if want.length_squared() < 0.0004 or _gap_under(Transform3D(tr.basis, tr.origin + want)) < 0.8:
				break
			want *= 0.5
		off = off.lerp(want, 1.0 - exp(-(45.0 if moving else 25.0) * sdt))
		yaw = clampf(lerpf(yaw, yaw - torque * 0.6, 1.0 - exp(-16.0 * sdt)), -0.8, 0.8)
	else:
		off *= pow(0.5, sdt / 0.35)                # (clear: it drifts back onto its path)
		yaw *= pow(0.5, sdt / 0.35)
		if off.length_squared() < 0.0001:
			off = Vector3.ZERO
		if absf(yaw) < 0.002:
			yaw = 0.0
	m.soil_off = off
	m.soil_yaw = yaw
	# (shifted or turned out of the wall, its legs step it there - as when a nestmate pushes it aside: it glided)
	var moved := (off - off0).length() + absf(yaw - yaw0) * 1.1 * float(m.size)
	if moved > 0.0005:
		m.gait = fmod(float(m.get("gait", 0.0)) + moved / (AntModel.stride_len(float(m.get("stride", 1.0))) * float(m.size)) * TAU, TAU * 64.0)
		m.mv = maxf(float(m.get("mv", 0.0)), clampf(moved / sdt / 0.5, 0.0, 1.0))
	if off == Vector3.ZERO and yaw == 0.0:
		return tr
	var t3 := tr
	if yaw != 0.0:
		t3.basis = t3.basis.rotated(up, yaw)
	t3.origin += off
	return t3


## A point of an ant's body (model units) where the shader draws it: the head turned at the neck (its bend, up +,
## and into a turn by `lat`), the gaster at the waist (its resting curl less its bend, swung out by -0.8 lat) -
## ant_core.gdshaderinc.
static func _bent(q: Vector3, bend: Vector2, lat: float) -> Vector3:
	if q.x > NECK.x:
		var h := (Vector2(q.x, q.y) - NECK).rotated(bend.y) + NECK
		return _yaw_at(Vector3(h.x, h.y, q.z), NECK.x, lat)
	if q.x < WAIST.x:
		var g := (Vector2(q.x, q.y) - WAIST).rotated(GASTER_CURL - bend.x) + WAIST
		return _yaw_at(Vector3(g.x, g.y, q.z), WAIST.x, -0.8 * lat)
	return q


## Its head tipped up at the neck where it pokes into the surface ahead (a floor curving up into a wall), its gaster
## lifted at the waist where it dips into the floor - as an ant does, not pushed back or up as a whole (that left its
## head in the wall and its gaster in the floor: walking ants' bodies were through the soil ~17% of the time). Added on
## to the bend the ground fit gives it (m.bend: x gaster, y head; + = up), eased, at most 0.6 in all.
const _HEAD_PTS := [Vector3(1.01, 0.4, 0.0), Vector3(0.95, 0.26, 0.0), Vector3(0.85, 0.24, 0.0)]
const _GASTER_PTS := [Vector3(-1.05, 0.13, 0.0), Vector3(-1.5, 0.36, 0.0), Vector3(-1.35, 0.21, 0.0), Vector3(-0.6, 0.12, 0.0)]
func _soil_bend(m: Dictionary, tr: Transform3D, md: float) -> void:
	var sb: Vector2 = m.get("sbend", Vector2.ZERO)
	if float(m.get("over", 0.0)) > 0.05:
		sb = sb.move_toward(Vector2.ZERO, 0.6 * md)      # (up on the brood or a nestmate: not bent for the soil)
		m.sbend = sb
		return
	var base: Vector2 = m.get("bend", Vector2.ZERO)
	m.sb_t = float(m.get("sb_t", 0.0)) + md
	if float(m.sb_t) >= 0.05 or float(m.get("mv", 0.0)) > 0.3:
		var dt := float(m.sb_t)
		m.sb_t = 0.0
		var b := (base + sb).clamp(Vector2(-0.6, -0.6), Vector2(0.6, 0.6))
		var head_in := false
		for q in _HEAD_PTS:
			if _density_at(tr * _bent(q, b, 0.0)) >= 0.5:
				head_in = true
				break
		var gaster_in := false
		for q in _GASTER_PTS:
			if _density_at(tr * _bent(q, b, 0.0)) >= 0.5:
				gaster_in = true
				break
		# (up quickly while in the soil, back down slowly once clear: checked again as it bends, it would flicker)
		sb.y = minf(sb.y + 5.0 * dt, 0.6) if head_in else maxf(sb.y - 0.6 * dt, 0.0)
		sb.x = minf(sb.x + 5.0 * dt, 0.6) if gaster_in else maxf(sb.x - 0.6 * dt, 0.0)
		m.sbend = sb
	if sb != Vector2.ZERO:
		m.bend = (base + sb).clamp(Vector2(-0.6, -0.6), Vector2(0.6, 0.6))


## q turned about the vertical through x = px by the shader's rot_y(a).
static func _yaw_at(q: Vector3, px: float, a: float) -> Vector3:
	if absf(a) < 0.001:
		return q
	var dx := q.x - px
	return Vector3(px + cos(a) * dx + sin(a) * q.z, q.y, -sin(a) * dx + cos(a) * q.z)


## A walking ant looks ahead: another body in its way (a nestmate walking ahead of it the same way, one coming the
## other way or crossing its path, one resting there, a digger) and it slows, to a stop before it touches - it
## used to keep walking and only be pushed aside once the two were in each other, slower than it walked (in wide
## chambers walking ants were inside one another ~10 pairs per 100 ants on screen). One that keeps standing in its
## way for a while it climbs over (as ants do in a crowded nest: cross_on, see _keep_apart and _climb); of two
## meeting head on, the one with the higher id. Returns how fast it may walk (1: its own pace). Replaces the
## follow-only gap of v0.8.61. `dt`: the time since it last looked.
func _gap_ahead(m: Dictionary, near: Dictionary, dt: float) -> float:
	# (resting - not stepping to the free spot it chose, which is walking too)
	if not m.has("xf") or m.has("script") or int(m.get("rest", 0)) > 0 and (m.get("settle", []) as Array).is_empty():
		m.blocked_t = 0.0
		return 1.0
	if m.has("over_on") and float(m.get("over_hold", 0.0)) > 0.0:
		m.blocked_t = 0.0
		return 0.6                           # (climbing over: it walks on over what is in its way, see _climb - slowly)
	var x: Transform3D = m.xf
	var up := x.basis.y.normalized()
	var f := x.basis.x.normalized()
	var s := float(m.size)
	var head := x * Vector3(CLIMB_PARTS[0].x, CLIMB_PARTS[0].y, 0.0)
	var hr: float = CLIMB_PARTS[0].z * s
	var key := Vector3i(floori(head.x / 3.0), floori(head.y / 3.0), floori(head.z / 3.0))
	# (the body drawn eases along behind the point on its path - up to a cell behind when walking fast: stopped
	# there, it still moves on that far)
	var lag := 0.0
	if m.has("vp"):
		var pth: Vector3 = (m.from as Vector3).lerp(m.to, clampf(float(m.t), 0.0, 1.0))
		lag = maxf(0.0, (pth - (m.vp as Vector3)).dot(f))
	var k := 1.0
	var by = null
	var on = m.get("over_on")
	for off in _NEAR:
		var bin = near.get(key + off)
		if bin == null:
			continue
		for o in bin:
			if is_same(o, m) or not o.has("xf") or is_same(o, on) or is_same(o.get("over_on"), m) or float(o.get("over", 0.0)) > 0.1:
				continue                     # (the one it is on, one climbing over it, one up on another's back)
			var ox: Transform3D = o.xf
			if ox.origin.distance_squared_to(head) > 9.0 or ox.basis.y.normalized().dot(up) < 0.5:
				continue
			var os := ox.basis.x.length()
			for q in CLIMB_PARTS:
				var to: Vector3 = ox * Vector3(q.x, q.y, 0.0) - head
				to -= up * to.dot(up)
				var ahead := to.dot(f)
				if ahead < 0.0:
					continue                 # (beside or behind its head: not in its way)
				var reach: float = hr + q.z * os + 0.06
				var lat := (to - f * ahead).length()
				if lat >= reach:
					continue
				# how far it can go on before its head touches that part (slowing over the last ~half a body)
				var gap := ahead - sqrt(reach * reach - lat * lat) - lag
				var kk := clampf(gap / (0.7 * s), 0.0, 1.0)
				if kk < k:
					k = kk
					by = o
	# held up: a while later it climbs over the one in its way
	if k < 0.15 and by != null:
		m.blocked_t = float(m.get("blocked_t", 0.0)) + dt
		var mutual: bool = is_same(by.get("cross_on"), m) or float(by.get("blocked_t", 0.0)) > 0.0 and int(by.get("wid", 0)) > int(m.get("wid", 0))
		if float(m.blocked_t) > 1.0 and not mutual and not by.has("callow"):
			m.blocked_t = 0.0
			# (a jam - the one in its way is resting, or held up itself: half of them stop here instead, and rest
			# where they are, as most do in a packed chamber; else every ant in a crowd was climbing over another)
			var jam: bool = int(by.get("rest", 0)) > 0 and (by.get("settle", []) as Array).is_empty() or float(by.get("fgap", 1.0)) < 0.15
			# (and where there was no room to climb over it a moment ago, it does not try again: it stops)
			var low := float(m.get("no_climb_t", 0.0)) > 0.0
			if (jam and randf() < 0.5 or low) and not m.has("deliver") and not m.get("carry", false) and not m.get("leaving", false):
				m.stop_here = true                  # (nest_mates: it arrives where it is)
			else:
				m.cross_on = by
				m.cross_t = 2.5
	else:
		m.blocked_t = 0.0
	return k


## The heading (in its floor's plane) in which an ant drawn at `tr` lies clear of the walls - and not with its
## head or gaster in a nestmate beside it, nor its feet over a drop (moved from nest_rest.gd in v0.8.63) - nearest
## its own: Vector3.ZERO if no heading is clearer than the one it has.
func _free_heading(m: Dictionary, tr: Transform3D, lift: float) -> Vector3:
	var up := tr.basis.y.normalized()
	var f := tr.basis.x.normalized()
	var sc := tr.basis.x.length()
	var o := tr.origin + up * lift
	var best := Vector3.ZERO
	var best_s := INF
	for k in 8:
		var a := (k + 1) / 2 * (1 if k % 2 == 1 else -1) * TAU / 8.0     # 0, +45, -45, +90, -90 ... degrees
		var h := f.rotated(up, a)
		var t := Transform3D(Basis(h, up, h.cross(up)).scaled(Vector3.ONE * sc), o)
		var c := _soil_clearance(t, sc)
		var drop := _feet_over_drop(t)
		var score := c.y * 10.0 + c.x + absf(a) * 0.05 + drop * 6.0
		for e in [o + h * (1.2 * sc), o - h * (1.2 * sc)]:     # its two ends: a nestmate there?
			var ec := Vector3i(roundi(e.x), roundi(e.y), roundi(e.z))
			for d in _NEAR:
				var n = _mate_cells.get(ec + d)
				if n != null and not is_same(n, m):
					score += 4.0
					break
		if k == 0:
			if c.y == 0 and drop == 0:
				return Vector3.ZERO
			best_s = score
			continue
		if score < best_s:
			best_s = score
			best = h
	return best


## How many of the feet of an ant drawn at `tr` have no ground under them (a shaft's mouth, the edge of a floor):
## its two front feet count double. Standing still, an ant does not stand with its front over a drop (one resting at
## the lip of a shaft had its front legs hanging in the air).
const _FEET := [Vector3(0.9, 0.0, 1.0), Vector3(0.9, 0.0, -1.0), Vector3(0.1, 0.0, 1.05), Vector3(0.1, 0.0, -1.05),
	Vector3(-0.85, 0.0, 1.05), Vector3(-0.85, 0.0, -1.05)]
func _feet_over_drop(tr: Transform3D) -> int:
	var up := tr.basis.y.normalized()
	var n := 0
	for k in _FEET.size():
		var f: Vector3 = tr * (_FEET[k] as Vector3)
		var ground := false
		for h in [0.05, 0.25, 0.45]:
			if _density_at(f - up * h) >= 0.5:
				ground = true
				break
		if not ground:
			n += 2 if k < 2 else 1
	return n


## A nestmate's body as drawn this frame, as spheres [centre, radius] (CLIMB_PARTS): worked out once a frame
## however many climb over it or beside it.
func _body_spheres(q: Dictionary) -> Array:
	if int(q.get("sph_f", -1)) == _mate_frame and q.has("sph"):
		return q.sph
	var qx: Transform3D = q.xf
	var qs := qx.basis.x.length()
	var out := []
	for c in CLIMB_PARTS:
		out.append([qx * Vector3(c.x, c.y, 0.0), c.z * qs])
	q.sph = out
	q.sph_f = _mate_frame
	return out


## From the rise each part needs (_climb_need): how far to raise the body and tip it (nose up +) - tipped along
## what it is over (the line from its gaster's need to its head's), then raised so that no part is in what is
## under it with that tip.
## A lift and tip (_need_lift) cut down to the room there is above the body drawn at `tr`: its head, thorax and
## gaster, raised and tipped so, must not go up into the soil - in a low tunnel an ant climbing over a nestmate or
## onto a larva was lifted into the ceiling (one seemed to float up into the soil, user 2026-10-16); there it
## squeezes past as real ants do instead.
func _headroom(tr: Transform3D, up: Vector3, lt: Vector2) -> Vector2:
	if lt.x <= 0.0:
		return lt
	var s := tr.basis.x.length()
	var want := lt.x
	var sn := sin(lt.y)
	while want > 0.0:
		var clear := true
		for i in [0, 1, 3]:
			var p: Vector3 = CLIMB_PARTS[i]
			var top: Vector3 = tr * Vector3(p.x, p.y, 0.0) + up * (want + p.x * s * sn + p.z * s + 0.05)
			if _density_at(top) >= 0.5:
				clear = false
				break
		if clear:
			break
		want -= 0.1
	return Vector2(maxf(want, 0.0), lt.y if want > 0.0 else 0.0)


static func _need_lift(need: Array, size: float, cap := 1.3) -> Vector2:
	var a: Vector2 = need[0]
	var b: Vector2 = need[need.size() - 1]
	var tip := clampf(atan2(a.y - b.y, a.x - b.x), -0.45, 0.45)
	var want := 0.0
	for n in need:
		want = maxf(want, n.y - n.x * sin(tip))
	return Vector2(minf(want, cap * size), tip)


## The eggs, larvae and cocoons near p as spheres [centre, radius]: a larva (lying on the floor) and a cocoon
## (centred) as three along their length.
var _bsph := {}                  # the brood's spheres by bin of _brood_occ, for the layout _bsph_gen
var _bsph_gen := -1
func _brood_spheres(p: Vector3) -> Array:
	if _bsph_gen != _brood_gen:
		_bsph_gen = _brood_gen
		_bsph.clear()
	var out := []
	var key := Vector3i(floori(p.x / 1.5), floori(p.y / 1.5), floori(p.z / 1.5))
	for dx in [-2, -1, 0, 1, 2]:                     # (two bins each way: a cocoon is 2.7 long, a bin 1.5)
		for dy in [-1, 0, 1, 2]:
			for dz in [-2, -1, 0, 1, 2]:
				var k: Vector3i = key + Vector3i(dx, dy, dz)
				var bs = _bsph.get(k)
				if bs == null:
					bs = []
					for o in _brood_occ.get(k, []):
						var c: Vector3 = o[0]
						if o.size() < 4:
							bs.append([c, 0.25])             # an egg
							continue
						if o.size() > 5:
							bs.append_array(o[5])            # its body as drawn, tilted with the floor (nest_piles._pile_spheres)
							continue
						var half: float = o[3]
						if o.size() > 4 and o[4]:
							c += Vector3.UP * half * 0.9     # (a larva's body rests on the floor)
						var ax: Vector3 = o[2]
						bs.append_array([[c - ax, half], [c, half], [c + ax, half]])
					_bsph[k] = bs
				for b in bs:
					if (b[0] as Vector3).distance_squared_to(p) < 7.0:
						out.append(b)
	return out


## How high each part of a body drawn at `tr` (along `up`) must rise to be clear of the spheres `unders`
## ([centre, radius]): [Vector2(x along the body, rise)] head first, gaster tip last. (`head_free`: its head may be
## in among them - a nurse at the brood.)
func _climb_need(tr: Transform3D, unders: Array, up: Vector3, head_free := false) -> Array:
	var s := tr.basis.x.length()
	var out := []
	for i in CLIMB_PARTS.size():
		var p: Vector3 = CLIMB_PARTS[i]
		var c: Vector3 = tr * Vector3(p.x, p.y, 0.0)
		var lift := 0.0
		if not (head_free and i == 0):
			for t in unders:
				var d: Vector3 = c - (t[0] as Vector3)
				var dv := d.dot(up)
				var h := (d - up * dv).length()
				var rr: float = p.z * s + float(t[1]) + 0.04
				if h < rr:
					lift = maxf(lift, sqrt(rr * rr - h * h) - dv)
		out.append(Vector2(p.x * s, lift))
	return out
