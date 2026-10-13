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
	var adt := delta * minf(speed, 1.0) if speed > 0 else 0.0     # (below 1x, real time, poses play in slow motion)
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
	var spray := []
	var sel_at := []                  # the selected ant's transform and pose, for its outline
	for a in sim.outside:
		if a.state == Ant.IN_NEST or a.dead:
			continue
		var beyond: bool = a.act == 22 and a.busy > 0
		if beyond:
			# off it goes past the edge of the plot (seen for a moment, then out of sight)
			a.vbeyond += adt
			if a.vbeyond > BEYOND_SHOW:
				continue
		elif a.vbeyond > 0.0:
			a.vbeyond = 0.0
			if a.vpos.x != INF:
				a.vpos += _out_dir(a.pos) * BEYOND_WALK      # back in: it walks in from out there
		var out_step := _out_dir(a.pos) * BEYOND_WALK * minf(1.0, a.vbeyond / BEYOND_SHOW) if beyond else Vector2.ZERO
		if a.vpos.x == INF or a.vpos.distance_squared_to(a.pos) > 400.0:
			a.vpos = a.pos
			a.vang = a.ang
			a.anim = randf() * 50.0
			a.vgait = randf() * TAU
		if a.vflung:
			a.vflung = false
			a.vright = THROWN_S
			a.vfly_from = a.vpos
		var flung := 0.0                                  # 0..1 through being thrown off and righting itself
		if a.vright > 0.0:
			a.vright = maxf(0.0, a.vright - adt)
			flung = 1.0 - a.vright / THROWN_S
		var step: Vector2 = a.pos + out_step - a.vpos
		if flung > 0.0 and flung < 0.25:
			step = Vector2.ZERO
			a.vpos = a.vfly_from.lerp(a.pos, smoothstep(0.0, 1.0, flung / 0.25))    # through the air
		elif flung >= 0.25 and flung < 0.92:
			step = Vector2.ZERO                              # on its back where it fell
		a.vpos += step * kp
		var moving := step.length_squared() > 0.01
		var was_ang: float = a.vang
		var hauling: bool = a.state == Ant.DRAG
		if hauling:
			a.vang = lerp_angle(a.vang, a.ang + PI, ka)      # facing the item it holds, whichever way it goes
		elif moving:
			a.vang = lerp_angle(a.vang, step.angle(), ka)
		elif a.busy > 0:
			a.vang = lerp_angle(a.vang, a.ang, ka)
		var turned := absf(wrapf(a.vang - was_ang, -PI, PI))    # turning on the spot takes steps too
		if turned > 0.004:
			moving = true
		a.vmv = lerpf(a.vmv, 1.0 if moving else 0.0, minf(1.0, 10.0 * delta))
		a.anim += adt
		var p: Vector2 = a.vpos * U
		var up := ground_top_n(p.x, p.y)                # over pebbles, twigs and leaves as well as the ground
		var f := Vector3(cos(a.vang), 0, sin(a.vang))
		f = (f - up * f.dot(up)).normalized()
		var s: float = ANT_SCALE * a.size
		# strides lengthen with pace (cold, rain, a load or an injury slow it); the leg cycle advances by
		# the distance actually walked over the stride, so planted feet do not slide
		var pace: float = (0.35 + 0.65 * sim.activity) * (1.0 - 0.35 * a.hurt) * (1.3 if a.state == Ant.DEFEND else 1.0)
		var stride := AntModel.stride_scale(pace, a.carry == Ant.PROTEIN or a.carry == Ant.CORPSE)
		var walked: float = (step * kp).length() * U + turned * 0.9 * s      # feet round the body as it turns
		if hauling:
			# pulling: the legs step backward when the item goes the way the ant's back is turned
			walked = (step * kp).dot(Vector2(cos(a.vang), sin(a.vang))) * U
		a.vgait = fmod(a.vgait + walked / (AntModel.stride_len(stride) * s) * TAU, TAU * 64.0)
		var tr := Transform3D(Basis(f, up, f.cross(up)).scaled(Vector3.ONE * s), Vector3(p.x, ground_top(p.x, p.y), p.y))
		var act: int = a.act if a.busy > 0 else 0
		if act == 2 and a.carry == Ant.PROTEIN and fmod(a.anim + a.id * 0.37, 7.0) < 3.0:
			act = 10                     # at a carcass: lapping up its body fluids between bites (adults take only liquids)
		var climbing: bool = a.busy > 0 and a.act == sim.ACT_WALL
		if climbing:
			var g: Array = _on_glass(a, tr, s)  # up the glass, slipping off the Fluon band, the fall, righting
			tr = g[0]
			act = g[1]
		elif hauling:
			act = 19                     # gripping the item, braced, pulling
		elif act == 0 and (a.carry == Ant.PROTEIN or a.carry == Ant.CORPSE):
			act = 8                      # carrying: head up, the load held in the mandibles
		elif act == 0 and _on_trail(a):
			act = 16                     # following a trail: antennae low, tapping the ground left and right
		if a.state == Ant.DEFEND:
			act = 13 if a.busy > 0 else 14          # clinging and spraying / running in alarmed
			if a.busy > 0 and _creature_vis.has(a.foe):
				tr.origin += _writhe_offset(_creature_vis[a.foe], tr.origin)    # carried with the writhing body
		if flung > 0.0:
			# thrown clear: over onto its back in the air, legs flailing where it lands, then a roll back upright
			var roll := PI * smoothstep(0.0, 0.25, flung) + PI * smoothstep(0.7, 0.92, flung)
			var hop := sin(clampf(flung / 0.25, 0.0, 1.0) * PI) * 2.2 * s
			var belly := 0.42 * s * (1.0 - cos(roll))          # on its back the body rests on its upper side
			tr = Transform3D(tr.basis * Basis(Vector3.RIGHT, roll), tr.origin + up * (hop + belly))
			if flung > 0.08 and flung < 0.8:
				act = 18
		var pose := _feeding_pose(a, act, s) if act in [2, 9, 10] else {}
		a.vfeed = move_toward(a.vfeed, 1.0 if not pose.is_empty() else 0.0, delta * 0.9)    # (~1 s: walking up the stem is seen)
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
		a.vact = AntModel.act_step(a.vact, act, a.anim)                     # poses ease into one another
		cus.append(Color(a.vgait, AntModel.act_y(a.vact, a.anim), fmod(a.anim, 600.0), AntModel.gait_w(a.vmv, stride)))
		if sel_kind == "worker" and a.id == sel_id:
			sel_at = [tr, cus[-1]]
		if act == 13:
			# formic acid sprayed from the curled gaster tip, under the body
			var puff := 0.5 + 0.5 * sin(a.anim * 9.0 + a.id)
			spray.append(tr * Transform3D(Basis.from_scale(Vector3.ONE * (0.12 + 0.18 * puff)), Vector3(0.35, 0.25, 0.0)))
		if a.carry == Ant.PROTEIN:
			loads.append(tr * CARRY_OFFSET)
		elif a.carry == Ant.NONE and a.state == Ant.SEARCH and a.busy <= 0 and a.id % 3 == 0 and _burying(a.pos):
			soil.append(tr * Transform3D(Basis.from_scale(Vector3.ONE * 0.38), Vector3(1.4, 0.45, 0)))
		elif a.carry == Ant.CORPSE:
			carried.append(tr * Transform3D(Basis(Vector3.RIGHT, PI).scaled(Vector3.ONE * 0.9), Vector3(2.3, 0.95, 0)))
	_sel_mm.instance_count = 1 if not sel_at.is_empty() else 0
	if not sel_at.is_empty():
		_sel_mm.set_instance_transform(0, sel_at[0])
		_sel_mm.set_instance_custom_data(0, sel_at[1])
	_ant_mm.instance_count = xs.size()
	for i in xs.size():
		_ant_mm.set_instance_transform(i, xs[i])
		_ant_mm.set_instance_color(i, cols[i])
		_ant_mm.set_instance_custom_data(i, cus[i])
	_spray_mm.instance_count = spray.size()
	for i in spray.size():
		_spray_mm.set_instance_transform(i, spray[i])
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
	if not sim.sp.get("buries_prey", false):
		return false
	for f in sim.foods:
		if FoodKinds.info(f.kind).get("buried", false) and f.found and _cover(f) < 0.85 and f.pos.distance_squared_to(p) < 2500.0:
			return true
	return false


## Where an ant handling food really stands: the simulation only knows it is within reach of the
## food's centre, so the view places it on the food itself. {} if no food is close.
const BEYOND_SHOW := 2.5               # seconds an ant leaving the plot is seen walking off
const BEYOND_WALK := 18.0              # px it walks out past the edge (and back in from)

## Outward from the plot at its nearest edge.
func _out_dir(p: Vector2) -> Vector2:
	var dl := p.x
	var dr: float = sim.WORLD.x - p.x
	var dt := p.y
	var db: float = sim.WORLD.y - p.y
	var m := minf(minf(dl, dr), minf(dt, db))
	if m == dl:
		return Vector2(-1, 0)
	if m == dr:
		return Vector2(1, 0)
	return Vector2(0, -1) if m == dt else Vector2(0, 1)


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
	var k := FoodKinds.info(f.kind)
	if k.is_empty() or act != int(k.handling[2]):
		return {}
	match k.get("feed_pose", ""):
		"climb":
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
		"rim":
			var r := (3.0 + 7.0 * sqrt(left)) * U * 1.1
			var p := c + away * (r + 0.85 * s)
			return {"pos": Vector3(p.x, ground_h(p.x, p.z), p.z), "fwd": -away, "up": Vector3.UP}
		"carcass":
			# around the carcass outline (an ellipse along its body), head in, cutting
			var ang: float = f.ang
			var rot := Basis(Vector3.UP, -ang)
			var dl: Vector3 = rot.inverse() * away
			var ea: float = k.carcass[0]
			var eb: float = k.carcass[1]
			var th := atan2(dl.z / eb, dl.x / ea)
			var n := rot * Vector3(cos(th) / ea, 0, sin(th) / eb).normalized()
			var p := c + rot * Vector3(ea * cos(th), 0, eb * sin(th)) * 0.88 + n * 0.55 * s   # head against the body
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


## Every enemy in the box, drawn with its kind's model (see _creature_views, set up in setup()).
## Each keeps its own smoothing state by creature id, so the drawn body glides between sim steps.
func _update_creatures(delta: float) -> void:
	var by_kind := {}
	for c in sim.creatures:
		if _creature_views.has(c.kind):
			if not by_kind.has(c.kind):
				by_kind[c.kind] = []
			by_kind[c.kind].append(c)
	var seen := {}
	for kind in _creature_views:
		var cv: Dictionary = _creature_views[kind]
		var list: Array = by_kind.get(kind, [])
		var mm: MultiMesh = cv.mm
		mm.instance_count = list.size()
		for i in list.size():
			var s: Dictionary = list[i]
			seen[s.id] = true
			if not _creature_vis.has(s.id):
				_creature_vis[s.id] = {"p": s.pos, "a": s.ang, "mv": 0.0}
			var v: Dictionary = _creature_vis[s.id]
			var step: Vector2 = s.pos - v.p
			v.p += step * (1.0 - exp(-15.0 * delta))
			v.a = lerp_angle(v.a, s.ang, 1.0 - exp(-8.0 * delta))
			v.mv = lerpf(v.mv, 1.0 if step.length_squared() > 0.0004 else 0.0, minf(1.0, 6.0 * delta))
			var p: Vector2 = v.p * U
			var up := ground_n(p.x, p.y)
			var f := Vector3(cos(v.a), 0, sin(v.a))
			f = (f - up * f.dot(up)).normalized()
			# out beyond the box (arriving or leaving) it is not drawn
			var inside: bool = Rect2(Vector2.ZERO, sim.WORLD).grow(-2.0).has_point(v.p)
			var sc: float = cv.scale if inside else 0.0
			mm.set_instance_transform(i, Transform3D(Basis(f, up, f.cross(up)).scaled(Vector3.ONE * sc), Vector3(p.x, ground_h(p.x, p.y), p.y)))
			var striking := 1.0 if int(s.get("strike", 0)) > 0 else 0.0
			var struggling := maxf(v.mv, 1.0 if int(s.get("held", 0)) > 0 else 0.0)    # pinned: legs thrash
			var gait := fmod(s.phase * cv.gait, TAU * 64.0)
			# w: how much it is walking, + 2 while ants are holding it down (it writhes)
			mm.set_instance_custom_data(i, Color(gait, striking, _t, v.mv + (2.0 if int(s.get("held", 0)) > 0 else 0.0)))
			v.xf = mm.get_instance_transform(i)
			v.kind = kind
			v.gait = gait
			v.held = 1.0 if int(s.get("held", 0)) > 0 else 0.0
	for id in _creature_vis.keys():
		if not seen.has(id):
			_creature_vis.erase(id)


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


## A forager climbing the glass wall of the box: up to the slippery Fluon band under the rim, where its foot pads
## lose their hold - it slides and drops back to the floor, lands on its back, legs flailing, and rights itself
## (the simulation holds it at the foot of the wall meanwhile; ant.busy counts the climb down). Returns
## [transform, activity].
func _on_glass(a: Ant, floor_tr: Transform3D, s: float) -> Array:
	var u := 1.0 - float(a.busy) / float(sim.WALL_TICKS)
	var w: float = sim.WORLD.x * U
	var d: float = sim.WORLD.y * U
	var p: Vector2 = a.vpos * U
	# the nearest wall: where on it, and its inward normal
	var dists := [p.x, w - p.x, p.y, d - p.y]
	var k := dists.find(dists.min())
	var n: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD][k]
	var at := Vector3(p.x, 0.0, p.y)
	match k:
		0: at.x = 0.05
		1: at.x = w - 0.05
		2: at.z = 0.05
		3: at.z = d - 0.05
	var base_y := ground_top(at.x, at.z)
	var band: float = WALL_H - 2.0 - FLUON_BAND - base_y        # how high it gets before the slippery band
	var act := 0
	if u < 0.55:
		# up the glass, head first; the last stretch slipping on the band before it lets go
		var h := smoothstep(0.0, 0.5, u) * band
		var fwd := Vector3.UP
		var slip := smoothstep(0.5, 0.55, u)
		var on_wall := Transform3D(Basis(fwd, n, fwd.cross(n)).scaled(Vector3.ONE * s), at + Vector3(0, base_y + h, 0) + n * 0.3 * slip)
		var k2 := smoothstep(0.0, 0.05, u)                     # stepping from the floor onto the glass
		var b := floor_tr.basis.orthonormalized().slerp(on_wall.basis.orthonormalized(), k2).scaled(Vector3.ONE * s)
		a.vgait = fmod(a.vgait + band * 0.02 * (1.0 - slip), TAU * 64.0)
		a.vmv = 1.0 - slip
		return [Transform3D(b, floor_tr.origin.lerp(on_wall.origin, k2)), act]
	# lost its hold: falls (tumbling away from the glass), lands on its back, flails, rolls upright
	var f := clampf((u - 0.55) / 0.07, 0.0, 1.0)              # the fall, ~a fifth of a second of game time
	var land := at + n * 1.2 + Vector3(0, ground_top(at.x + n.x * 1.2, at.z + n.z * 1.2), 0)
	var top := at + n * 0.3 + Vector3(0, base_y + band, 0)
	var pos := top.lerp(land, f * f)
	var roll := PI * smoothstep(0.0, 1.0, f) + PI * smoothstep(0.82, 0.95, u)
	var flat := Basis(n.cross(Vector3.UP).normalized() if absf(n.y) < 0.9 else Vector3.RIGHT, Vector3.UP, Vector3.ZERO)
	flat.z = flat.x.cross(flat.y)
	var on_floor := flat * Basis(Vector3.RIGHT, roll)
	var hang := Basis(Vector3.UP, n, Vector3.UP.cross(n))
	var b := hang.slerp(on_floor.orthonormalized(), smoothstep(0.0, 0.6, f))
	if u > 0.6 and u < 0.88:
		act = 18                                               # on its back, legs clawing at the air
	a.vmv = 0.0
	var belly := 0.42 * s * (1.0 - cos(roll))
	return [Transform3D(b.scaled(Vector3.ONE * s), pos + Vector3(0, belly, 0)), act]


## How far the writhing body of a creature has carried the point p (on or by it) sideways from where the
## simulation has it - kept in step with the body wave in shaders/creatures/centipede.gdshader.
func _writhe_offset(v: Dictionary, p: Vector3) -> Vector3:
	if v.get("kind", "") != "centipede" or not v.has("xf"):
		return Vector3.ZERO
	var xf: Transform3D = v.xf
	if xf.basis.x.length_squared() < 0.000001:
		return Vector3.ZERO
	var x: float = (xf.affine_inverse() * p).x
	var dz := sin(x * 0.5 - float(v.gait) * 1.4) * 0.45 * float(v.mv) + sin(x * 0.3 + _t * 0.6) * 0.12
	dz += float(v.held) * (sin(x * 0.55 - _t * 6.0) * 0.6 + sin(_t * 1.7) * 0.012 * (x - 2.0) * (x - 2.0))
	return xf.basis.z * dz


## Whether a forager is walking along a scent trail (laden ones lay and follow the food trail home).
func _on_trail(a) -> bool:
	if a.carry != Ant.NONE:
		return true
	var i: int = int(a.pos.y * sim.INV_CELL) * sim.gw + int(a.pos.x * sim.INV_CELL)
	return i >= 0 and i < sim.food_cell.size() and sim.food.read_i(i) > 0.4


## The selected forager as it is now (ui/ant_tip.gd), or {} if it is not out here.
func info_for(kind: String, id: int) -> Dictionary:
	if kind != "worker":
		return {}
	for a in sim.outside:
		if a.id == id and a.state != Ant.IN_NEST and not a.dead and not (a.act == 22 and a.busy > 0):
			var act: int = a.act if a.busy > 0 else 0
			if a.state == Ant.DRAG:
				act = 19
			elif a.state == Ant.DEFEND:
				act = 13 if a.busy > 0 else 14
			elif act == 0 and (a.carry == Ant.PROTEIN or a.carry == Ant.CORPSE):
				act = 8
			return {"kind": "worker", "w": a, "act": act}
	return {}


## A click selects an ant only with the hand (camera) tool; the other tools place things.
func can_select() -> bool:
	return world.tool == "pan"


## The forager under the mouse (a screen position) for the selection (ui/ant_tip.gd), or {}.
func pick_ant(sp: Vector2) -> Dictionary:
	var best := {}
	var best_d := 26.0
	for a in sim.outside:
		if a.state == Ant.IN_NEST or a.dead or a.vpos.x == INF or (a.act == 22 and a.busy > 0):
			continue
		var p: Vector2 = a.vpos * U
		var o := Vector3(p.x, ground_top(p.x, p.y), p.y)
		if _cam.is_position_behind(o):
			continue
		var d := _cam.unproject_position(o).distance_to(sp)
		if d < best_d:
			best_d = d
			var act: int = a.act if a.busy > 0 else 0
			if a.state == Ant.DRAG:
				act = 19
			elif a.state == Ant.DEFEND:
				act = 13 if a.busy > 0 else 14
			elif act == 0 and (a.carry == Ant.PROTEIN or a.carry == Ant.CORPSE):
				act = 8
			best = {"kind": "worker", "w": a, "act": act}
	return best
