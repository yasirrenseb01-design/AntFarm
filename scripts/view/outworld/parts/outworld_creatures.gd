extends "res://scripts/view/outworld/parts/outworld_props.gd"
## Outworld view, layer 3 of 5: foragers (and how they stand on the food they handle), corpses,
## the spider, rain, the day/night light and the tool ring.


func _light() -> void:
	var sky: Color = world._sky_color()
	var day: float = sim.daylight()
	_sun.light_color = sky
	_sun.light_energy = 0.25 + 0.72 * day       # a little moonlight at night
	_env.ambient_light_color = sky
	_env.ambient_light_energy = 0.5 + 0.1 * day
	_sun.directional_shadow_max_distance = maxf(150.0, cam_dist * 2.5)


func _update_ants(delta: float) -> void:
	var kp := 1.0 - exp(-20.0 * delta)
	var ka := 1.0 - exp(-10.0 * delta)
	var adt := delta if speed > 0 else 0.0
	# in daylight the ants need their true (linear) colour or the sun bleaches them grey
	var body: Color = AntModel.tint(sim.sp["body_color"]).srgb_to_linear()
	var young: Color = AntModel.tint(sim.sp["callow_color"]).srgb_to_linear()
	var xs := []
	var cols := []
	var cus := []
	var loads := []
	var carried := []
	var dews := []
	var soil := []
	for a in sim.outside:
		if a.state == Ant.IN_NEST or a.dead:
			continue
		if a.vpos.x == INF or a.vpos.distance_squared_to(a.pos) > 400.0:
			a.vpos = a.pos
			a.vang = a.ang
			a.anim = randf() * 50.0
		var step: Vector2 = a.pos - a.vpos
		a.vpos += step * kp
		var moving := step.length_squared() > 0.01
		if moving:
			a.vang = lerp_angle(a.vang, step.angle(), ka)
		elif a.busy > 0:
			a.vang = lerp_angle(a.vang, a.ang, ka)
		a.vmv = lerpf(a.vmv, 1.0 if moving else 0.0, minf(1.0, 10.0 * delta))
		a.anim += adt
		var p: Vector2 = a.vpos * U
		var up := ground_n(p.x, p.y)
		var f := Vector3(cos(a.vang), 0, sin(a.vang))
		f = (f - up * f.dot(up)).normalized()
		var s: float = ANT_SCALE * a.size
		var tr := Transform3D(Basis(f, up, f.cross(up)).scaled(Vector3.ONE * s), Vector3(p.x, ground_h(p.x, p.y), p.y))
		var act: int = a.act if a.busy > 0 else 0
		var pose := _feeding_pose(a, act, s) if act in [2, 9, 10] else {}
		a.vfeed = move_toward(a.vfeed, 1.0 if not pose.is_empty() else 0.0, delta * 2.5)
		if not pose.is_empty():
			a.vpose = pose
		if a.vfeed > 0.0 and a.vpose is Dictionary and not (a.vpose as Dictionary).is_empty():
			tr = _blend_pose(tr, a.vpose, a.vfeed, s)
			if a.vfeed > 0.95 and act == 9:
				dews.append(a.vpose.dew)
		if a.carry == Ant.SUGAR:
			act += 100                      # a crop full of honeydew swells the gaster
		xs.append(tr)
		cols.append(body.lerp(young, clampf(1.0 - a.age / 6.0, 0.0, 1.0)))
		cus.append(Color(fmod(a.phase, TAU * 64.0), act, fmod(a.anim, 600.0), a.vmv))
		if a.carry == Ant.PROTEIN:
			loads.append(tr * CARRY_OFFSET)
		elif a.carry == Ant.NONE and a.state == Ant.SEARCH and a.busy <= 0 and a.id % 3 == 0 and _burying(a.pos):
			soil.append(tr * Transform3D(Basis.from_scale(Vector3.ONE * 0.38), Vector3(1.4, 0.45, 0)))
		elif a.carry == Ant.CORPSE:
			carried.append(tr * Transform3D(Basis(Vector3.RIGHT, PI).scaled(Vector3.ONE * 0.9), Vector3(2.3, 0.95, 0)))
	_ant_mm.instance_count = xs.size()
	for i in xs.size():
		_ant_mm.set_instance_transform(i, xs[i])
		_ant_mm.set_instance_color(i, cols[i])
		_ant_mm.set_instance_custom_data(i, cus[i])
	_soil_mm.instance_count = soil.size()
	for i in soil.size():
		_soil_mm.set_instance_transform(i, soil[i])
	_dew_mm.instance_count = dews.size()
	for i in dews.size():
		var pulse := 0.6 + 0.4 * sin(_t * 3.0 + i)
		_dew_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * pulse), dews[i]))
	_prey_mm.instance_count = loads.size()
	for i in loads.size():
		_prey_mm.set_instance_transform(i, loads[i])
	_carried = carried


## True near a carcass the colony is still burying.
func _burying(p: Vector2) -> bool:
	for f in sim.foods:
		if (f.kind == "cricket" or f.kind == "fly") and f.found and _cover(f) < 0.85 and f.pos.distance_squared_to(p) < 2500.0:
			return true
	return false


## Where an ant handling food really stands: the simulation only knows it is within reach of the
## food's centre, so the view places it on the food itself. {} if no food is close.
func _feeding_pose(a, act: int, s: float) -> Dictionary:
	var best = null
	var bd := 1e9
	for f in sim.foods:
		var d: float = f.pos.distance_squared_to(a.pos)
		if d < bd:
			bd = d
			best = f
	if best == null or bd > pow(best.r + 14.0, 2.0):
		return {}
	var f: Dictionary = best
	var c := _on_ground(f.pos)
	var away := Vector3(a.pos.x - f.pos.x, 0, a.pos.y - f.pos.y)
	if away.length_squared() < 0.01:
		away = Vector3(1, 0, 0)
	away = away.normalized()
	var left: float = clampf(f.amt / f.cap, 0.0, 1.0)
	match f.kind:
		"aphids":
			if act != 9:
				return {}
			# climb the stem to one of the low aphids and stroke its abdomen for the drop
			var e: Dictionary = _foods.get(f.seed, {})
			if e.is_empty() or e.low.is_empty():
				return {}
			var root: Transform3D = e.node.transform
			var ax: Transform3D = root * (e.low[a.id % e.low.size()] as Transform3D)
			var out_dir: Vector3 = ax.basis.y.normalized()
			var stem: Vector3 = ax.origin - out_dir * (Props.STEM_R + 0.35)
			var on := stem + out_dir * (Props.STEM_R + 0.1) - Vector3(0, 1.9 * s, 0)
			var base := Vector3(on.x, ground_h(on.x, on.z), on.z) + out_dir * 0.4
			return {"climb": true, "base": base, "pos": on, "fwd": Vector3.UP, "up": out_dir,
				"dew": ax * Vector3(-0.95, 0.4, 0)}
		"honey":
			if act != 10:
				return {}
			var r := (3.0 + 7.0 * sqrt(left)) * U * 1.1
			var p := c + away * (r + 0.85 * s)
			return {"pos": Vector3(p.x, ground_h(p.x, p.z), p.z), "fwd": -away, "up": Vector3.UP}
		"cricket", "fly":
			if act != 2:
				return {}
			# around the carcass outline (an ellipse along its body), head in, cutting
			var ang: float = f.ang
			var rot := Basis(Vector3.UP, -ang)
			var dl: Vector3 = rot.inverse() * away
			var ea := 6.4 if f.kind == "cricket" else 2.2
			var eb := 2.4 if f.kind == "cricket" else 1.3
			var th := atan2(dl.z / eb, dl.x / ea)
			var n := rot * Vector3(cos(th) / ea, 0, sin(th) / eb).normalized()
			var p := c + rot * Vector3(ea * cos(th), 0, eb * sin(th)) + n * 1.1 * s
			return {"pos": Vector3(p.x, ground_h(p.x, p.z), p.z), "fwd": -n, "up": Vector3.UP}
	return {}


func _pose_xf(fwd: Vector3, up: Vector3, pos: Vector3, s: float) -> Transform3D:
	var f := fwd - up * fwd.dot(up)
	if f.length_squared() < 1e-4:
		f = up.cross(Vector3.RIGHT) if absf(up.x) < 0.9 else up.cross(Vector3.BACK)
	f = f.normalized()
	return Transform3D(Basis(f, up, f.cross(up)).scaled(Vector3.ONE * s), pos)


## Blend from the walking pose toward the feeding pose; climbing goes to the stem foot first.
func _blend_pose(ground: Transform3D, pose: Dictionary, k: float, s: float) -> Transform3D:
	var fe := _pose_xf(pose.fwd, pose.up, pose.pos, s)
	if not pose.get("climb", false):
		var b: Basis = ground.basis.orthonormalized().slerp(fe.basis.orthonormalized(), k)
		return Transform3D(b.scaled(Vector3.ONE * s), ground.origin.lerp(fe.origin, k))
	var foot := _pose_xf(pose.base - ground.origin if k < 0.5 else pose.pos - pose.base, Vector3.UP, pose.base, s)
	if k < 0.5:
		var u := k * 2.0
		var b: Basis = ground.basis.orthonormalized().slerp(foot.basis.orthonormalized(), minf(1.0, u * 2.0))
		return Transform3D(b.scaled(Vector3.ONE * s), ground.origin.lerp(pose.base, u))
	var u2 := (k - 0.5) * 2.0
	var b2: Basis = foot.basis.orthonormalized().slerp(fe.basis.orthonormalized(), minf(1.0, u2 * 3.0))
	return Transform3D(b2.scaled(Vector3.ONE * s), (pose.base as Vector3).lerp(pose.pos, u2))


## Dead workers on the refuse pile (and wherever the spider dropped them), plus those being carried.
func _update_corpses() -> void:
	var n: int = mini(sim.corpses.size(), 300)
	_corpse_mm.instance_count = n + _carried.size()
	var dead := Color(0.2, 0.16, 0.13)
	for i in n:
		var c: Dictionary = sim.corpses[sim.corpses.size() - n + i]
		var f := Vector3(cos(c.ang), 0, sin(c.ang))
		var b := Basis(f, Vector3.DOWN, f.cross(Vector3.DOWN)).scaled(Vector3.ONE * ANT_SCALE * 0.95)
		_corpse_mm.set_instance_transform(i, Transform3D(b, _on_ground(c.pos, 0.75)))
		_corpse_mm.set_instance_color(i, AntModel.tint(dead.lerp(Color(0.32, 0.27, 0.22), clampf(c.age / 30.0, 0.0, 1.0))).srgb_to_linear())
		_corpse_mm.set_instance_custom_data(i, Color(0, 11, 0, 0))
	for i in _carried.size():
		_corpse_mm.set_instance_transform(n + i, _carried[i])
		_corpse_mm.set_instance_color(n + i, AntModel.tint(dead).srgb_to_linear())
		_corpse_mm.set_instance_custom_data(n + i, Color(0, 11, 0, 0))


func _update_spider(delta: float) -> void:
	if sim.spider.is_empty():
		_spider_mm.instance_count = 0
		_spider_vis = {}
		return
	var s: Dictionary = sim.spider
	if _spider_vis.is_empty():
		_spider_vis = {"p": s.pos, "a": s.ang, "mv": 0.0}
	var step: Vector2 = s.pos - _spider_vis.p
	_spider_vis.p += step * (1.0 - exp(-15.0 * delta))
	_spider_vis.a = lerp_angle(_spider_vis.a, s.ang, 1.0 - exp(-8.0 * delta))
	_spider_vis.mv = lerpf(_spider_vis.mv, 1.0 if step.length_squared() > 0.0004 else 0.0, minf(1.0, 6.0 * delta))
	var p: Vector2 = _spider_vis.p * U
	var up := ground_n(p.x, p.y)
	var f := Vector3(cos(_spider_vis.a), 0, sin(_spider_vis.a))
	f = (f - up * f.dot(up)).normalized()
	_spider_mm.instance_count = 1
	_spider_mm.set_instance_transform(0, Transform3D(Basis(f, up, f.cross(up)).scaled(Vector3.ONE * 0.85), Vector3(p.x, ground_h(p.x, p.y), p.y)))
	_spider_mm.set_instance_custom_data(0, Color(fmod(s.phase * 0.5, TAU * 64.0), 0, _t, _spider_vis.mv))


func _update_rain(delta: float, raining: bool) -> void:
	var sdt := delta if speed > 0 else 0.0
	for s in _splash:
		s[1] += sdt
	_splash = _splash.filter(func(s): return s[1] < 0.35)
	_splash_mm.instance_count = _splash.size()
	for i in _splash.size():
		var k: float = _splash[i][1] / 0.35
		var r := 0.25 + 0.9 * k
		_splash_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, 0.4, r)), _splash[i][0]))
		_splash_mm.set_instance_color(i, Color(1, 1, 1, 0.55 * (1.0 - k)))
	if not raining:
		_rain_mm.instance_count = 0
		return
	_rain_mm.instance_count = _rain.size()
	var dt := delta if speed > 0 else 0.0
	for i in _rain.size():
		var d: Vector3 = _rain[i]
		d.y -= 150.0 * dt
		d.x -= 30.0 * dt
		if d.y < ground_h(d.x, d.z):
			if _splash.size() < 160 and randf() < 0.7:
				_splash.append([Vector3(d.x, ground_h(d.x, d.z) + 0.1, d.z), 0.0])
			d = Vector3(randf() * 400.0, 60.0, randf() * 250.0)
		_rain[i] = d
		_rain_mm.set_instance_transform(i, Transform3D(Basis(Vector3.BACK, 0.2), d))


func _update_ring() -> void:
	var t: String = world.tool
	_ring.visible = hover != Vector3.INF and t in ["rock", "erase"]
	if _ring.visible:
		var r := (10.0 if t == "rock" else 24.0) * U
		_ring.position = hover + Vector3(0, 0.3, 0)
		_ring.scale = Vector3(r, 1.0, r)
