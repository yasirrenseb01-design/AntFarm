extends "res://scripts/view/nest/parts/nest_lifecycle.gd"
## Nest view, layer 5 of 7 (split from parts/nest_mates.gd in v0.8.5): how a nestmate's body moves —
## easing along its voxel path, turning, the leg cycle, and bodies keeping out of one another (and the queen).


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


## Eases the drawn ant along its voxel path: position, heading and body tilt follow the hops
## smoothly instead of snapping at each cell; distance walked drives the leg gait (radians) and
## `mv` (0..1) tells the shader how much the legs should be stepping. If `face` is set the ant
## turns to look at that point (meeting a nestmate, tending brood).
func _smooth(v: Dictionary, path_pos: Vector3, up: Vector3, delta: float, scale: float) -> Transform3D:
	if not v.has("vp") or v.vp.distance_squared_to(path_pos) > 36.0:
		v.vp = path_pos
		v.vf = Vector3.RIGHT
		v.vu = up
		v.gait = randf() * TAU
		v.mv = 0.0
	var np: Vector3 = v.vp.lerp(path_pos, 1.0 - exp(-12.0 * delta))
	var step: Vector3 = np - v.vp
	var moving := step.length() > 0.12 * delta
	if moving:
		var want := step.normalized()
		var old_f: Vector3 = v.vf
		v.vf = (v.vf as Vector3).slerp(want, minf(1.0, 9.0 * delta)) if (v.vf as Vector3).dot(want) > -0.99 else want
		var turned := old_f.angle_to(v.vf)            # turning takes steps as well as walking does
		v.gait = fmod(v.gait + (step.length() + turned * 0.9 * scale) / (AntModel.stride_len(v.get("stride", 1.0)) * scale) * TAU, TAU * 64.0)
	var face: Vector3 = v.get("face", Vector3.INF)
	if face != Vector3.INF and not moving:
		var to := face - np
		to -= v.vu * to.dot(v.vu)
		if to.length_squared() > 0.01:
			var want := to.normalized()
			v.vf = (v.vf as Vector3).slerp(want, minf(1.0, 5.0 * delta)) if (v.vf as Vector3).dot(want) > -0.99 else want
	v.mv = lerpf(v.mv, 1.0 if moving else 0.0, minf(1.0, 8.0 * delta))
	v.vu = (v.vu as Vector3).lerp(up, minf(1.0, 6.0 * delta)).normalized()
	v.vp = np
	var f: Vector3 = v.vf
	var y: Vector3 = v.vu - f * f.dot(v.vu)
	if y.length_squared() < 0.01:
		y = Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT
	y = y.normalized()
	f = (f - y * f.dot(y)).normalized()
	return Transform3D(Basis(f, y, f.cross(y)).scaled(Vector3.ONE * scale), np - v.vu * 0.4)


func _nearest_spot(p: Vector3, spots: Array) -> Vector3:
	var best := Vector3.INF
	var bd := 9.0
	for s in spots:
		var d := p.distance_squared_to(s)
		if d < bd:
			bd = d
			best = s
	return best


func _custom(v: Dictionary, act: int) -> Color:
	return Color(v.get("gait", 0.0), act, fmod(v.get("anim", 0.0), 600.0), AntModel.gait_w(v.get("mv", 0.0), v.get("stride", 1.0)))


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
	for off in _NEAR:
		var bin = near.get(key + off)
		if bin == null:
			continue
		for o in bin:
			if o == m:
				continue
			var oc: Vector3 = (o.xf as Transform3D).origin
			if p.distance_squared_to(oc) > 9.0 * s * s:
				continue
			var reach: float = r + 0.55 * float(o.size)
			var rr := reach * reach
			for a in [a0, a1]:
				for b in [o.d0, o.d1]:
					var d: Vector3 = a - b
					d -= up * d.dot(up)
					var l2 := d.length_squared()
					if l2 < rr and l2 > 0.000001:
						var l := sqrt(l2)
						push += d / l * (reach - l) * 0.5
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
				var reach := QUEEN_R + r
				if attending and a == a0:
					reach = QUEEN_R * 0.8
				if l < reach and l > 0.001:
					push += d / l * (reach - l)
	var want := push.limit_length(2.5)
	var sep: Vector3 = m.get("sep", Vector3.ZERO)
	sep = sep.lerp(want, minf(1.0, 14.0 * delta))
	m.sep = sep
	return sep
