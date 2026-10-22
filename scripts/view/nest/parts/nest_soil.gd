extends "res://scripts/view/nest/parts/nest_rest.gd"
## Nest view, layer 8 of 12 (split from nest_contact.gd in v0.11.26): bodies out of the soil - an ant shifted and
## turned out of the walls of a bend, feeling ahead with its antennae, its head tipped up and its gaster lifted where
## they meet the surface.


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
# (just ahead of its head, left and right: where its antennae touch)
const _FEEL_PTS := [Vector3(1.3, 0.4, 0.2), Vector3(1.3, 0.4, -0.2)]
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
	if moving:
		# (feeling ahead with its antennae: soil just in front of its head turns it along the wall before it walks
		# into it - pushed out only once in, its head went into the wall at every bend of a tunnel)
		for q0 in _FEEL_PTS:
			var c: Vector3 = t2 * _bent(q0, bend, lat)
			if _density_at(c) >= 0.45:
				torque -= 0.5 * signf(q0.z) * (1.0 if hits == 0 else 0.5)
				if hits == 0:
					hits = -1                        # (turned only: nothing of its body is in the soil yet)
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
		var yaw_new := clampf(lerpf(yaw, yaw - torque * 0.6, 1.0 - exp(-16.0 * sdt)), -0.8, 0.8)
		# (standing, it turns out of the wall one way only: turned back the other way a moment later, by the wall on
		# its other side or the gaster's end, it swung its heading to and fro on the spot)
		var yd := signf(yaw_new - yaw)
		if moving:
			m.soil_yd = 0.0
		elif yd != 0.0 and yd == -float(m.get("soil_yd", 0.0)):
			yaw_new = yaw
		elif absf(yaw_new - yaw) > 0.002:
			m.soil_yd = yd
		yaw = yaw_new
	elif hits < 0:
		yaw = clampf(lerpf(yaw, yaw - torque * 0.6, 1.0 - exp(-16.0 * sdt)), -0.8, 0.8)
	else:
		# (clear: it drifts back onto its path - but only as far as it stays clear there: relaxing straight back, it
		# touched the wall again, was pushed out again, and stood swinging its head and gaster to and fro beside the
		# wall; the keeper saw it, 2026-10-22)
		# (looked at every third frame, over the time since: the check is another pass over the body, for every ant
		# walking clear of the walls)
		m.relax_t = float(m.get("relax_t", 0.0)) + sdt if (off != Vector3.ZERO or yaw != 0.0) else 0.0
		var k_back := 1.0
		if moving and (off != Vector3.ZERO or yaw != 0.0) and (_mate_frame + int(m.get("wid", 0))) % 3 == 0:
			k_back = pow(0.5, float(m.relax_t) / 0.35)
			m.relax_t = 0.0
			var tb := tr
			if yaw * k_back != 0.0:
				tb.basis = tb.basis.rotated(up, yaw * k_back)
			tb.origin += off * k_back
			if _body_touches(tb, bend, lat) or _feels(tb, bend, lat):
				k_back = 1.0                       # (it would be back in the wall: it stays as it is)
		elif not moving:
			m.relax_t = 0.0                        # (standing: it stays as the wall left it - it eases back walking on)
		off *= k_back
		yaw *= k_back
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


## Whether its antennae (_FEEL_PTS) would touch the soil with it at t.
func _feels(t: Transform3D, bend: Vector2, lat: float) -> bool:
	for q0 in _FEEL_PTS:
		if _density_at(t * _bent(q0, bend, lat)) >= 0.45:
			return true
	return false


## Whether any of the body's points (_SOIL_PTS, bent as drawn) are in the soil with the body at t.
func _body_touches(t: Transform3D, bend: Vector2, lat: float) -> bool:
	for q0 in _SOIL_PTS:
		if _density_at(t * _bent(q0, bend, lat)) >= 0.45:
			return true
	return false


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
		# (and down only as far as it stays clear lowered: let straight down it touched again and nodded up and down)
		var lowered := (base + sb - Vector2(0.12, 0.12)).clamp(Vector2(-0.6, -0.6), Vector2(0.6, 0.6))
		var head_low := false
		var gaster_low := false
		if not head_in and sb.y > 0.0:
			for q in _HEAD_PTS:
				if _density_at(tr * _bent(q, Vector2(b.x, lowered.y), 0.0)) >= 0.5:
					head_low = true
					break
		if not gaster_in and sb.x > 0.0:
			for q in _GASTER_PTS:
				if _density_at(tr * _bent(q, Vector2(lowered.x, b.y), 0.0)) >= 0.5:
					gaster_low = true
					break
		# (standing still it holds the pose it took: it relaxes only as it walks on)
		var still := float(m.get("mv", 0.0)) < 0.3
		sb.y = minf(sb.y + 5.0 * dt, 0.6) if head_in else (sb.y if head_low or still else maxf(sb.y - 0.6 * dt, 0.0))
		sb.x = minf(sb.x + 5.0 * dt, 0.6) if gaster_in else (sb.x if gaster_low or still else maxf(sb.x - 0.6 * dt, 0.0))
		m.sbend = sb
	if sb != Vector2.ZERO:
		m.bend = (base + sb).clamp(Vector2(-0.6, -0.6), Vector2(0.6, 0.6))


## q turned about the vertical through x = px by the shader's rot_y(a).
static func _yaw_at(q: Vector3, px: float, a: float) -> Vector3:
	if absf(a) < 0.001:
		return q
	var dx := q.x - px
	return Vector3(px + cos(a) * dx + sin(a) * q.z, q.y, -sin(a) * dx + cos(a) * q.z)
