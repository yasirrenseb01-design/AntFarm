extends "res://scripts/view/nest/parts/nest_lifecycle.gd"
## Nest view, layer 6 of 10 (split from parts/nest_mates.gd in v0.8.5): how a nestmate's body moves —
## easing along its voxel path, turning, the leg cycle, and bodies keeping out of one another (and the queen),
## and (moved from nest_mates.gd in v0.8.16) whether it stands on the brood (where it stops: nest_rest.gd).


func _pose(from: Vector3, to: Vector3, t: float, up: Vector3, scale := 1.0) -> Transform3D:
	var p := from.lerp(to, clampf(t, 0.0, 1.0))
	var f := to - from
	if f.length_squared() < 0.0001:
		f = Vector3.RIGHT
	f = f.normalized()
	var y := (up - f * f.dot(up))
	if y.length_squared() < 0.01:
		y = Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT
	y = y.normalized()
	var z := f.cross(y)
	return Transform3D(Basis(f, y, z).scaled(Vector3.ONE * scale), p - up * 0.4)


## Turns heading a part of the way (k) toward want. Slerp needs unit vectors and fails (a bad axis) when the
## two are all but the same or opposite: then it simply takes the new heading.
func _turn_to(a: Vector3, want: Vector3, k: float) -> Vector3:
	var u := a.normalized()
	var d := u.dot(want)
	if d > 0.9995 or d < -0.99:
		return want
	return u.slerp(want, k)


## Eases the drawn ant along its voxel path: position, heading and body tilt follow the hops
## smoothly instead of snapping at each cell; distance walked drives the leg gait (radians) and
## `mv` (0..1) tells the shader how much the legs should be stepping. If `face` is set the ant
## turns to look at that point (meeting a nestmate, tending brood).
func _smooth(v: Dictionary, path_pos: Vector3, up: Vector3, delta: float, scale: float) -> Transform3D:
	if not v.has("vp") or v.vp.distance_squared_to(path_pos) > 36.0:
		v.vp = path_pos
		v.vp1 = path_pos
		v.vel = Vector3.ZERO
		v.vf = Vector3.RIGHT
		v.vu = up
		v.gait = randf() * TAU
		v.mv = 0.0
	# eased twice over (two smoothings in a row): the path goes from voxel to voxel, and across the grid it
	# zigzags (one step along x, the next along z) - eased once the body still swung to and fro at every corner
	# (held up by a body ahead - see nest_contact._gap_ahead - the drawn body stops at once, not only its point on
	# the path: easing on behind it, it walked on up to a cell into the one ahead)
	var k := (1.0 - exp(-10.0 * delta)) * float(v.get("fgap", 1.0))
	v.vp1 = (v.get("vp1", path_pos) as Vector3).lerp(path_pos, k)
	var np: Vector3 = v.vp.lerp(v.vp1, k)
	var step: Vector3 = np - v.vp
	var moving := step.length() > 0.12 * delta
	# it heads the way it has been going over the last fraction of a second, not the way its last step went
	v.vel = (v.get("vel", Vector3.ZERO) as Vector3).lerp(step / maxf(delta, 0.0001), 1.0 - exp(-5.0 * delta))
	var vel: Vector3 = v.vel
	var flat := vel - (v.vu as Vector3) * vel.dot(v.vu)       # (turn only within the floor's plane: a step up or
	var face: Vector3 = v.get("face", Vector3.INF)          # down - a lift, the floor rising - never tips it on end)
	# backing away from what it holds or works at (pulling a callow out): it keeps facing it, walking backwards
	var backing := face != Vector3.INF and flat.dot(face - np) < 0.0
	var lat := 0.0
	if moving and not backing and flat.length() > 0.12:
		var want := flat.normalized()
		var rate := 5.0
		# rounding a bend the body is a C: the head already turned toward where it is going, the gaster swung
		# out behind (an ant bends at its neck and waist) - as far as its heading still lags the way it walks
		var vf0: Vector3 = v.vf
		lat = clampf(atan2(vf0.cross(want).dot(v.vu), vf0.dot(want)) * 0.7, -0.4, 0.4)
		var old_f: Vector3 = v.vf
		# turning has momentum: it speeds up into a turn and eases out of it, and cannot swing back the other way
		# from one frame to the next (the path's zigzags across the voxel grid, or its floor turning into a wall,
		# flicked the heading to and fro)
		var vu0: Vector3 = v.vu
		var f0: Vector3 = (old_f - vu0 * old_f.dot(vu0))
		if f0.length_squared() > 0.0001 and absf(want.dot(vu0)) < 0.99:
			f0 = f0.normalized()
			var ang := atan2(f0.cross(want).dot(vu0), f0.dot(want))
			var wv := float(v.get("wv", 0.0))
			# (how fast it can turn grows with how fast it walks - turning is done by its steps: a fast ant turned
			# too slowly round a corner and slid along sideways)
			var spd := vel.length()
			var wmax := 5.0 + 0.7 * spd
			var wv_want := clampf(ang * rate * 0.7, -wmax, wmax)
			wv = move_toward(wv, wv_want, (30.0 + 4.0 * spd) * delta)
			v.wv = wv
			v.vf = f0.rotated(vu0, clampf(wv * delta, -absf(ang), absf(ang)))
		else:
			v.vf = _turn_to(v.vf, want, minf(1.0, rate * delta))
		var turned := old_f.angle_to(v.vf)            # turning takes steps as well as walking does
		v.gait = fmod(v.gait + (step.length() + turned * 0.9 * scale) / (AntModel.stride_len(v.get("stride", 1.0)) * scale) * TAU, TAU * 64.0)
	var rd: Vector3 = v.get("rest_dir", Vector3.ZERO)
	if moving:
		v.rest_dir = Vector3.ZERO
	else:
		v.wv = 0.0
	if face != Vector3.INF and (not moving or backing):
		var to := face - np
		to -= v.vu * to.dot(v.vu)
		if to.length_squared() > 0.01:
			var want := to.normalized()
			v.vf = _turn_to(v.vf, want, minf(1.0, 5.0 * delta))
	elif not moving and rd != Vector3.ZERO:
		# standing with its head or gaster in the wall: it turns round on the spot to lie clear (stepping)
		var want := (rd - (v.vu as Vector3) * rd.dot(v.vu)).normalized()
		var old_f: Vector3 = v.vf
		v.vf = _turn_to(v.vf, want, minf(1.0, 3.0 * delta))
		var turned := old_f.angle_to(v.vf)
		v.gait = fmod(v.gait + turned * 0.9 / AntModel.stride_len(v.get("stride", 1.0)) * TAU, TAU * 64.0)
		if turned > 0.2 * delta:
			moving = true                          # (its legs step as it turns)
		if (v.vf as Vector3).dot(want) > 0.995:
			v.rest_dir = Vector3.ZERO
	v.mv = lerpf(v.mv, 1.0 if moving else 0.0, minf(1.0, 8.0 * delta))
	v.lat = lerpf(float(v.get("lat", 0.0)), lat, minf(1.0, 6.0 * delta))
	v.vu = (v.vu as Vector3).lerp(up, minf(1.0, 2.5 * delta)).normalized()     # (slowly: zigzagging along a floor-wall crease the up of each cell differs, and the body twisted to and fro)
	v.vp = np
	var f: Vector3 = v.vf
	var y: Vector3 = v.vu - f * f.dot(v.vu)
	if y.length_squared() < 0.01:
		y = Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT
	y = y.normalized()
	f = (f - y * f.dot(y)).normalized()
	return Transform3D(Basis(f, y, f.cross(y)).scaled(Vector3.ONE * scale), np - v.vu * 0.4)


## The nearest larva (drawn) within `reach` of p, or INF.
func _larva_within(p: Vector3, reach: float) -> Vector3:
	var best := Vector3.INF
	var bd := reach
	for i in _larva_mm.instance_count:
		var o: Vector3 = _larva_mm.get_instance_transform(i).origin
		var d := o.distance_to(p)
		if d < bd:
			bd = d
			best = o
	return best


func _custom(v: Dictionary, act: int) -> Color:
	var clock: float = v.get("anim", 0.0)
	v.vact = AntModel.act_step(v.get("vact", Vector3(-1, 0, 0)), act, clock)    # poses ease into one another
	var gx := AntModel.gait_x(v.get("gait", 0.0), v.get("bend", Vector2.ZERO))       # (and the waist and neck bent to the ground)
	var cz := AntModel.clock_z(clock, v.get("lat", 0.0))                              # (and bent sideways round a turn)
	if v.get("fed", false):
		return Color(gx, AntModel.act_y(v.vact, clock) + 100.0, cz, AntModel.gait_w(v.get("mv", 0.0), v.get("stride", 1.0)))   # crop full of honeydew
	return Color(gx, AntModel.act_y(v.vact, clock), cz, AntModel.gait_w(v.get("mv", 0.0), v.get("stride", 1.0)))


const _NEAR := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(-1, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]


## Bodies do not pass through one another: each ant is two discs along its body (head-thorax and
## gaster), the queen a long capsule. Overlaps push the ant sideways (in the floor plane) right out of
## the other body; the push is eased only a little so it never jitters.
func _keep_apart(m: Dictionary, p: Vector3, near: Dictionary, delta: float) -> Vector3:
	var up: Vector3 = m.up
	var s: float = m.size
	var a0: Vector3 = m.get("d0", p)
	var a1: Vector3 = m.get("d1", p)
	var r := 0.55 * s
	var push := Vector3.ZERO
	var key := Vector3i(floori(p.x / 3.0), floori(p.y / 3.0), floori(p.z / 3.0))
	var partner = m.get("partner")
	var callow_ok: bool = m.has("script")
	var s9 := 9.0 * s * s
	var side: Vector3 = (m.xf as Transform3D).basis.z if m.has("xf") else Vector3.RIGHT
	# meeting another ant in a narrow tunnel there is no room to step aside: a walking ant climbs over its back
	# (over a resting one, or - two passing - the one with the higher id), as real ants do in their galleries
	var walking: bool = (int(m.get("rest", 1)) == 0 or not (m.get("settle", []) as Array).is_empty()) and float(m.get("mv", 0.0)) > 0.3 \
		and not m.has("script")
	var over_on = null
	var over_d := INF
	for off in _NEAR:
		var bin = near.get(key + off)
		if bin == null:
			continue
		for o in bin:
			# (is_same: `==` on two dictionaries compares every field - it was most of this function's time)
			if is_same(o, m) or is_same(o, partner) or (callow_ok and o.has("callow")):   # (feeding partners touch heads)
				continue                 # (the nurses pulling a callow out of its cocoon hold on to it)
			var oc: Vector3 = (o.xf as Transform3D).origin
			if p.distance_squared_to(oc) > s9:
				continue
			var reach: float = r + 0.55 * float(o.size)
			var rr := reach * reach
			if is_same(o.get("over_on"), m) and float(o.get("over_hold", 0.0)) > 0.0:
				continue                 # (it is climbing over this one: on its back, not pushing it aside)
			# (or anywhere, onto one that has stood in its way a while: see nest_contact._gap_ahead)
			if (walking and (m.get("narrow", false) or o.get("narrow", false)) and (int(o.get("rest", 1)) > 0 or int(m.get("wid", 0)) > int(o.get("wid", 0))) \
					or is_same(o, m.get("cross_on")) and float(m.get("cross_t", 0.0)) > 0.0) and not o.has("callow") \
					and float(o.get("over", 0.0)) <= 0.1 and not is_same(o.get("over_on"), m) \
					and float(m.get("no_climb_t", 0.0)) <= 0.0:     # (no towers of ants; not onto one climbing over it; not where there was no room to)
				# (a little before the two bodies meet: it climbs on as its head reaches the other - _climb lifts each
				# part of its body only once it is over the other's)
				var lim := (reach + 0.5) * (reach + 0.5)
				var dmin := INF
				for a in [a0, a1]:
					for b in [o.d0, o.d1]:
						var d: Vector3 = a - b
						d -= up * d.dot(up)
						dmin = minf(dmin, d.length_squared())
				if dmin < lim:
					if dmin < over_d:
						over_d = dmin
						over_on = o
					continue
			var b0: Vector3 = o.d0
			var b1: Vector3 = o.d1
			# overlap is judged by the true distance (one ant may be on the wall, the other on the floor);
			# the push itself stays in this ant's floor plane (head-thorax and gaster discs, each against each)
			push += _disc_push(a0 - b0, rr, reach, up, side)
			push += _disc_push(a0 - b1, rr, reach, up, side)
			push += _disc_push(a1 - b0, rr, reach, up, side)
			push += _disc_push(a1 - b1, rr, reach, up, side)
	if _queen_mm.instance_count > 0:
		var qa: Vector3 = _queen_xf * QUEEN_HEAD
		var qb: Vector3 = _queen_xf * QUEEN_TAIL
		if p.distance_squared_to((qa + qb) * 0.5) < 36.0:
			var attending := m.has("script")             # an attendant may touch her with its head, no more
			for a in [a0, a1]:
				var t := clampf((a - qa).dot(qb - qa) / maxf((qb - qa).length_squared(), 0.001), 0.0, 1.0)
				var d: Vector3 = a - qa.lerp(qb, t)
				d -= up * d.dot(up)
				var l := d.length()
				# her legs reach out ~1.9 units to each side along the middle of her body (thorax): no one
				# stands in them; at her head and gaster ends the body itself is the limit
				var legs := 0.85 * smoothstep(0.05, 0.25, t) * (1.0 - smoothstep(0.55, 0.75, t))
				var reach := QUEEN_R + r + legs
				if attending and a == a0:
					reach = QUEEN_R * 0.8 + legs * 0.5
				if l < reach and l > 0.001:
					push += d / l * (reach - l)
	# brood on the floor is in the way too: ants step round the egg packet, the larvae and the cocoons
	# instead of walking over them; a nurse (or an ant carrying brood) may put its head in among them to
	# lick, feed or pick one up, but not its body
	if not _brood_occ.is_empty() and not _on_brood(m) and _brood_wide.has(Vector3i(roundi(p.x), roundi(p.y - 0.45), roundi(p.z))):   # (only near the brood)
		var tends := _tends_brood(m)
		var ar := 0.45 * s                       # an ant's half width (legs bend in round brood)
		for o in _brood_near(p):
			for a in [a0, (a0 + a1) * 0.5, a1]:     # head-thorax, waist and gaster
				var d := _brood_offset(a, o)
				var dv := d.dot(up)
				if absf(dv) > 1.2:
					continue                     # on the wall or ceiling above it
				d -= up * dv
				var reach: float = ar + float(o[3] if o.size() > 3 else o[1])
				if tends and a == a0:
					reach = float(o[3] if o.size() > 3 else o[1]) + 0.12    # head just touching it
				var l := d.length()
				if l < reach and l > 0.001:
					push += d / l * (reach - l) * 0.5     # (as hard as ant on ant: harder only squeezed them into each other)
	m.ka_push = push
	# (held a moment after the last touch, so it climbs on and steps down once - not up and down every time the
	# two bodies just touch or part; it keeps to the one it is on until it is past it)
	var on_now = m.get("over_on")
	if over_on != null and (on_now == null or float(m.get("over_hold", 0.0)) <= 0.0 \
			or not is_same(on_now, over_on) and float(m.get("over", 0.0)) < 0.05):
		m.over_on = over_on
	if over_on != null and is_same(m.get("over_on"), over_on):
		m.over_hold = 0.6
	else:
		m.over_hold = float(m.get("over_hold", 0.0)) - delta
	if float(m.get("no_climb_t", 0.0)) > 0.0:
		m.no_climb_t = float(m.no_climb_t) - delta
	if m.has("cross_on"):
		m.cross_t = float(m.get("cross_t", 0.0)) - delta
		if float(m.cross_t) <= 0.0:
			m.erase("cross_on")
	return _ease_sep(m, p, up, push, delta)


## How far one disc pair (centres d apart) pushes this ant, in its floor plane (zero unless they overlap).
static func _disc_push(d: Vector3, rr: float, reach: float, up: Vector3, side: Vector3) -> Vector3:
	var l2 := d.length_squared()
	if l2 >= rr or l2 <= 0.000001:
		return Vector3.ZERO
	var dir := d - up * d.dot(up)
	if dir.length_squared() < 0.0001:
		dir = side
	return dir.normalized() * (reach - sqrt(l2)) * 0.5


## The shift that keeps a body clear of the others, eased toward what still overlaps (`push`).
func _ease_sep(m: Dictionary, p: Vector3, up: Vector3, push: Vector3, delta: float) -> Vector3:
	# The discs above already include last frame's shift, so `push` is what still overlaps: add it on, and
	# let the shift relax slowly (half-life ~1 s) so an ant drifts back to its path once there is room.
	var was: Vector3 = m.get("sep", Vector3.ZERO)
	# standing still it stays where it settled unless it is really squeezed: small pushes that flip with the
	# neighbours' own shifts (and the soil check on a sloping chamber edge) made resting ants tremble
	if float(m.get("mv", 1.0)) < 0.15 and push.length() < 0.05:     # (only the tiniest: a bigger overlap is sorted out)
		return was
	var sep: Vector3 = (was + push * minf(1.0, 12.0 * delta)) * pow(0.5, delta)
	sep = sep.limit_length(2.5)
	# never into the soil: in a cramped chamber ants press together (as real ones do) rather than
	# through the walls
	if not _open_at(p + sep, up):
		sep *= 0.5
		if not _open_at(p + sep, up):
			sep = Vector3.ZERO
	# the shift itself changes no faster than a slow step (~4.5 mm/s): two ants pressed together, or one
	# squeezed against the wall, used to flick back and forth a millimetre or more every frame
	# eased (not only rate-limited): pressed in a crowd the push each frame flips to and fro a little - the
	# body follows only its average, and ignores changes too small to see (else it trembled on the spot)
	# (a walking ant steps aside about twice as briskly: brushing past another its body was in the other's for
	# a moment before the shift caught up)
	var brisk := float(m.get("mv", 0.0)) > 0.5
	var target := sep
	sep = was.lerp(target, 1.0 - exp(-(5.0 if brisk else 2.5) * delta))
	sep = was.move_toward(sep, (5.5 if brisk else 3.0) * delta)
	if (sep - was).length() < 0.004 and (target - was).length() < 0.08:
		sep = was
	m.sep = sep
	return sep


## Whether this nestmate is walking across the brood pile (its way on led over it: no way round). Real
## ants climb over the brood in a crowded chamber (user's choice, 2026-10-13); it is not pushed off sideways.
func _on_brood(m: Dictionary) -> bool:
	return m.has("cell") and _brood_cells.has(m.cell) and not m.has("script")    # (diggers have no cell: never); stays up if it stops there


## How high the brood under p reaches above the floor (0 if none): an ant crossing the pile walks on top of
## it - eggs, larvae and cocoons are firm enough to step on.
func _brood_top(p: Vector3) -> float:
	var top := 0.0
	var f := _floor_cached(p)
	for o in _brood_near(p):
		var d := _brood_offset(p, o)
		var half: float = float(o[3] if o.size() > 3 else o[1])
		if Vector2(d.x, d.z).length() < half + 0.15:
			top = maxf(top, float(o[0].y) + half - f)
	return top


## Whether this nestmate works at the brood itself (its head may go in among the eggs, larvae and cocoons).
func _tends_brood(m: Dictionary) -> bool:
	return m.get("role", "") in ["nurse", "carry", "attend"] or m.has("script") or m.has("deliver")


## How many body parts of nestmates still stand on eggs, larvae or cocoons: dev check (--trace).
var _overlap_who := []


func brood_overlaps() -> int:
	_overlap_who.clear()
	var n := 0
	for m in _mates:
		if not m.has("xf"):
			continue
		var x: Transform3D = m.xf
		var f: Vector3 = x.basis.x.normalized() * (0.7 * float(m.size))
		# (a nurse's head may be in among the brood; its body may not)
		for a in ([x.origin, x.origin - f] if _tends_brood(m) else [x.origin + f, x.origin, x.origin - f]):
			for o in _brood_near(a):
				var d := _brood_offset(a, o)
				var dy := d.y
				d.y = 0.0
				var half: float = o[3] if o.size() > 3 else o[1]
				if absf(dy) < 1.2 and d.length() < (0.45 * float(m.size) + half) * 0.75:
					n += 1
					_overlap_who.append("%s/a%d/r%d/s%d" % [m.get("role", "dig"), m.get("act", 0), m.get("rest", 0), (m.get("settle", []) as Array).size()])
	return n


## How many pairs of nestmates still overlap by more than a third of a body width: dev check (--trace).
func mate_overlaps() -> int:
	var n := 0
	for i in _mates.size():
		var m: Dictionary = _mates[i]
		if not m.has("d0"):
			continue
		for j in range(i + 1, _mates.size()):
			var o: Dictionary = _mates[j]
			if not o.has("d0") or (m.d0 as Vector3).distance_squared_to(o.d0) > 16.0:
				continue
			if absf(((m.xf as Transform3D).origin - (o.xf as Transform3D).origin).dot(m.up)) > 0.4:
				continue                 # (one up on the other's back: climbing over it)
			var lim: float = (0.55 * float(m.size) + 0.55 * float(o.size)) * 0.85     # (bodies visibly inside each other)
			var hit := false
			for a in [m.d0, m.d1]:
				for b in [o.d0, o.d1]:
					hit = hit or (a as Vector3).distance_to(b) < lim
			if hit:
				n += 1
				_overlap_who.append("M:%s/a%d+%s/a%d@%d" % [m.role, m.act, o.role, o.act, int((m.xf as Transform3D).origin.y)])
	return n


## Whether a body standing at p (on a surface whose up is `up`) is in open space, not in the soil.
func _open_at(p: Vector3, up: Vector3) -> bool:
	var c := p + up * 0.6
	return nest.is_open(Vector3i(roundi(c.x), roundi(c.y), roundi(c.z)))


## A walkable cell just inside the entrance (where foragers come in), or (-1, 0, 0).
func _entrance_cell() -> Vector3i:
	var c := Vector3i(nest.entrance)
	for k in 10:
		if _walkable(c):
			return c
		c.y -= 1
	return _any_spot()


## A walkable floor spot somewhere in the chambers, or (-1, 0, 0).
func _any_spot() -> Vector3i:
	if _spots.all.is_empty():
		return Vector3i(-1, 0, 0)
	for k in 6:
		var sp: Vector3 = _spots.all[randi() % _spots.all.size()]
		var c := Vector3i(roundi(sp.x), roundi(sp.y + 0.45), roundi(sp.z))
		if _walkable(c):
			return c
	return Vector3i(-1, 0, 0)


## The ant under the mouse (a screen position) for the hover box (ui/ant_tip.gd): a nestmate (with its real
## worker), a digger, or the queen; {} if none is close.
func pick_ant(sp: Vector2) -> Dictionary:
	# the ant whose body (head to gaster tip on screen) the click is on - the nearest to the eye where bodies
	# overlap on screen - else the one it is nearest to, within a finger's breadth (it used to be measured to the
	# middle of the body only, so a click on the head or the gaster missed)
	var cands := []                 # [gap, distance from the camera, info]
	var all := {}
	for w in sim.workers:
		all[w.id] = w
	var eye := _cam.global_position
	for m in _mates:
		if m.has("xf") and m.get("wid", -1) >= 0:
			var d := _body_gap(m.xf, sp)
			if d < 14.0:
				cands.append([d, eye.distance_to((m.xf as Transform3D).origin), {"kind": "worker", "w": all.get(m.wid), "role": m.role, "act": m.act}])
	# diggers: the colony's diggers are the workers set to dig, lowest id first, one per digger drawn
	var dig_ws: Array = sim.workers.filter(func(w): return w.task == Ant.TASK_DIG)
	dig_ws.sort_custom(func(a, b): return a.id < b.id)
	var ds: Array = nest.diggers.duplicate()
	ds.sort_custom(func(a, b): return a.id < b.id)
	for i in ds.size():
		var v: Dictionary = _dig_vis.get(ds[i].id, {})
		if v.has("xf"):
			var d := _body_gap(v.xf, sp)
			if d < 14.0:
				cands.append([d, eye.distance_to((v.xf as Transform3D).origin), {"kind": "digger", "w": dig_ws[i] if i < dig_ws.size() else null,
					"act": ACT_CARRY if ds[i].carry else ACT_DIG, "dig": ds[i].id}])
	if _queen_mm.instance_count > 0 and _visible(_queen_xf.origin):
		var qd := AntModel.screen_gap(_cam, _queen_xf, sp, QUEEN_HEAD + Vector3(0.25, 0, 0), QUEEN_TAIL - Vector3(0.2, 0, 0), 0.32)
		if qd < 14.0:
			cands.append([qd, eye.distance_to(_queen_xf.origin) + 0.8, {"kind": "queen", "act": _queen_act if _queen_act >= 0 else _queen_mode}])
	# the brood: an egg, a larva or a cocoon can be clicked as well (what stage, how far on, fed or hungry)
	for kind in ["eggs", "larvae", "pupae"]:
		var ends: Array = [Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0), 0.7] if kind == "eggs" else \
			([Vector3(1.0, 0.3, 0), Vector3(-0.8, 0.3, 0), 0.32] if kind == "larvae" else [Vector3(1.3, 0, 0), Vector3(-1.3, 0, 0), 0.36])
		for e in _brood_drawn[kind]:
			var bxf: Transform3D = e[0]
			var d := AntModel.screen_gap(_cam, bxf, sp, ends[0], ends[1], ends[2])
			if d < 10.0:
				cands.append([d, eye.distance_to(bxf.origin), {"kind": kind, "id": int((e[1] as Dictionary).get("_v", -1))}])
	var best := {}
	var on := INF                   # on a body: the nearest to the eye
	var near := INF                 # else: the nearest on screen
	for c in cands:
		if c[0] <= 0.0 and c[1] < on:
			on = c[1]
			best = c[2]
	if best.is_empty():
		for c in cands:
			if c[0] < near:
				near = c[0]
				best = c[2]
	return best


func _body_gap(xf: Transform3D, sp: Vector2) -> float:
	return AntModel.screen_gap(_cam, xf, sp) if _visible(xf.origin) else INF


## The selected ant as it is now (ui/ant_tip.gd): the same fields as pick_ant(), or {} if it is not in the nest.
func info_for(kind: String, id: int) -> Dictionary:
	if kind == "queen":
		return {"kind": "queen", "act": _queen_act if _queen_act >= 0 else _queen_mode} if _queen_mm.instance_count > 0 else {}
	if kind in ["eggs", "larvae", "pupae"]:
		# an item of brood, by its view tag: as it is now ({} once it has moved on to the next stage, or was eaten)
		for it in (sim.eggs if kind == "eggs" else (sim.larvae if kind == "larvae" else sim.pupae)):
			if int((it as Dictionary).get("_v", -1)) == id:
				return {"kind": kind, "item": it}
		return {}
	if kind == "digger":
		var dig_ws: Array = sim.workers.filter(func(w): return w.task == Ant.TASK_DIG)
		dig_ws.sort_custom(func(a, b): return a.id < b.id)
		var ds: Array = nest.diggers.duplicate()
		ds.sort_custom(func(a, b): return a.id < b.id)
		for i in ds.size():
			if ds[i].id == id:
				return {"kind": "digger", "w": dig_ws[i] if i < dig_ws.size() else null, "act": ACT_CARRY if ds[i].carry else ACT_DIG, "dig": id}
		return {}
	for m in _mates:
		if int(m.get("wid", -1)) == id:
			for w in sim.workers:
				if w.id == id:
					return {"kind": "worker", "w": w, "role": m.role, "act": m.act}
	return {}


## Whether a click may select an ant here (the nest view has no tools).
func can_select() -> bool:
	return true
