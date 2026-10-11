extends "res://scripts/view/nest/parts/nest_lifecycle.gd"
## Nest view, layer 5 of 6: the nestmates walking the real tunnels, their roles and activities,
## meetings, and the diggers from the simulation.


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
		v.vf = (v.vf as Vector3).slerp(want, minf(1.0, 9.0 * delta)) if (v.vf as Vector3).dot(want) > -0.99 else want
		v.gait = fmod(v.gait + step.length() * 6.0 / scale, TAU * 64.0)
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


func _move_mate(m: Dictionary, n: Vector3i) -> void:
	m.prev = m.cell
	m.cell = n
	m.from = m.to
	m.to = Vector3(n)
	m.up = _up_at(n)


## What an ant does when it reaches the place it was heading for.
func _arrive(m: Dictionary) -> void:
	if m.has("deliver"):
		m.deliver.done = true                       # cocoon set down, or empty shell taken out
		m.erase("deliver")
		m.carry = false
		m.item = ""
		if m.goal == -1:
			m.goal = _brood_room(_larva_group)
	match m.role:
		"nurse":
			m.rest = randi_range(30, 140)
			m.wander = randi_range(2, 6)              # then a short shuffle around the brood pile
		"attend":
			m.rest = randi_range(80, 260)             # the queen's retinue stays close to her
			m.wander = randi_range(1, 3)
		"idle":
			m.rest = randi_range(60, 240)
			if randf() < 0.25:
				m.goal = _random_room()
		"traffic":
			# a forager passing through: in at the entrance (crop full of honeydew), down to a chamber
			m.rest = randi_range(2, 10)
			if m.goal == -1:
				m.fed = randf() < 0.7
				m.goal = _random_room()
			else:
				m.goal = -1
		"carry":
			if _moved >= sim.larvae.size():
				m.role = "nurse"
				m.carry = false
				m.goal = _brood_room(_larva_group)
			elif not m.carry:
				m.carry = true                          # picks up a larva from the old pile
				m.goal = _brood_room(_larva_group)
				m.rest = 3
			else:
				m.carry = false                         # sets it down in the new chamber
				_moved += maxi(1, sim.larvae.size() / 10)
				m.goal = _brood_room(_larva_prev)
				m.rest = 3


func _step_mate(m: Dictionary) -> void:
	var c: Vector3i = m.cell
	if m.rest > 0:
		m.rest -= 1
		m.from = m.to
		return
	if m.wander > 0:
		m.wander -= 1
		var opts: Array[Vector3i] = []
		for d in DIRS:
			if c + d != m.prev and nest.walkable(c + d):
				opts.append(c + d)
		if not opts.is_empty():
			_move_mate(m, opts[randi() % opts.size()])
		return
	var field: Dictionary = _fields.get(m.goal, {})
	var here: int = field.get(c, -1)
	if here == 0:
		_arrive(m)
		return
	if here < 0:
		# off the map (new tunnel, stale field): pick another goal and drift
		m.goal = _random_room()
		m.wander = 3
		return
	var best: Array[Vector3i] = []
	var floaty: Array[Vector3i] = []
	for d in DIRS:
		var n := c + d
		if field.get(n, 1 << 20) < here:
			if nest.walkable(n):
				best.append(n)
			else:
				floaty.append(n)
	if best.is_empty():
		best = floaty
	if not best.is_empty():
		_move_mate(m, best[randi() % best.size()])


func _sample_size() -> float:
	return sim.workers[randi() % sim.workers.size()].size if not sim.workers.is_empty() else 1.0


func _spawn_mate(role: String, inside: int) -> bool:
	if _spots.all.is_empty() or _rooms.is_empty():
		return false
	var sp: Vector3 = _spots.all[randi() % _spots.all.size()]
	var c := Vector3i(roundi(sp.x), roundi(sp.y + 0.45), roundi(sp.z))
	if not nest.walkable(c):
		return false
	var goal := _random_room()
	match role:
		"nurse": goal = _brood_room(_larva_group)
		"attend": goal = _queen_room()
		"traffic": goal = -1
	var callow := randf() < float(sim.callow) / maxf(1.0, inside)
	var born: int = sim.tick - int(randf() * sim.TPD * float(sim.sp["callow_days"])) if callow else -1000000000
	_mates.append({"cell": c, "prev": c, "from": Vector3(c), "to": Vector3(c), "t": 1.0, "rest": randi_range(0, 30),
		"up": _up_at(c), "born": born, "role": role, "goal": goal,
		"wander": 0, "carry": false, "item": "", "size": _sample_size(), "act": ACT_WALK, "act_left": 0.0, "cool": randf() * 4.0,
		"anim": randf() * 100.0, "fed": false})
	return true


func _begin(m: Dictionary, act: int, secs: float, face := Vector3.INF) -> void:
	m.act = act
	m.act_left = secs
	m.face = face


## Two ants that bump into each other stop and drum antennae; a forager back from outside
## regurgitates a droplet of honeydew to the other (trophallaxis).
func _meetings() -> void:
	var by_cell := {}
	for m in _mates:
		by_cell[m.cell] = m
	for m in _mates:
		if m.cool > 0.0 or m.act in STILL_ACTS or m.carry:
			continue
		for d in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
				Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
			var o = by_cell.get(m.cell + d)
			if o == null or is_same(o, m) or o.cool > 0.0 or o.act in STILL_ACTS or o.carry:
				continue
			if m.fed or o.fed:
				var secs := randf_range(3.0, 6.0)
				_begin(m, ACT_FEED, secs, o.vp if o.has("vp") else o.to)
				_begin(o, ACT_FEED, secs, m.vp if m.has("vp") else m.to)
				m.fed = false
				o.fed = false
			else:
				var secs := randf_range(1.0, 2.2)
				_begin(m, ACT_ANTENNATE, secs, o.vp if o.has("vp") else o.to)
				_begin(o, ACT_ANTENNATE, secs, m.vp if m.has("vp") else m.to)
			m.cool = randf_range(5.0, 10.0)
			o.cool = randf_range(5.0, 10.0)
			break


## Choose what a mate is doing this frame from its role and situation.
func _update_activity(m: Dictionary, delta: float) -> void:
	m.cool = maxf(0.0, m.cool - delta)
	if m.act_left > 0.0:
		m.act_left -= delta
		if m.act_left > 0.0:
			return
	m.face = Vector3.INF
	if m.carry:
		m.act = ACT_CARRY
	elif m.rest > 0:
		if m.role == "nurse" and _rooms.size() > 0:
			# nurses at the brood pile lick the larvae and regurgitate food to them
			m.act = ACT_FEED if fmod(m.anim + m.cool * 3.0, 11.0) < 4.0 and not sim.larvae.is_empty() else ACT_TEND
			m.face = _nearest_spot(m.to, _spots.larvae)
		elif m.role == "attend":
			m.act = ACT_TEND
			m.face = _spots.queen
			if fmod(m.anim, 16.0) > 9.0 and not sim.eggs.is_empty() and not _spots.eggs.is_empty():
				m.face = _egg_xf(0).origin            # licking the egg packet clean
		elif randf() < 0.04 * delta:
			_begin(m, ACT_GROOM, randf_range(2.0, 4.5))     # resting ants groom every so often
		else:
			m.act = ACT_REST
	else:
		m.act = ACT_WALK


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
	return Color(v.get("gait", 0.0), act, fmod(v.get("anim", 0.0), 600.0), v.get("mv", 0.0))


func _update_ants(delta: float) -> void:
	var inside: int = sim.workers.size() - sim.out_count
	# a worker still climbing out of its cocoon is drawn by its eclosion, not as a nestmate yet
	var want := clampi(inside - nest.diggers.size() - _pending("eclose"), 0, 250)
	var nurses_want := mini(sim.nurses + sim.callow, want / 2 + 1)
	var attend_want := mini(3, want / 6) if sim.queen.alive else 0
	var traffic_want := mini(mini(sim.out_count, 4), want)
	while _mates.size() < want:
		var counts := {"nurse": 0, "attend": 0, "traffic": 0}
		for m in _mates:
			var r: String = "nurse" if m.role == "carry" else m.role
			if counts.has(r):
				counts[r] += 1
		var role := "idle"
		if counts.attend < attend_want:
			role = "attend"
		elif counts.nurse < nurses_want:
			role = "nurse"
		elif counts.traffic < traffic_want:
			role = "traffic"
		if not _spawn_mate(role, inside):
			break
	while _mates.size() > want:
		var drop: Dictionary = _mates.pop_back()
		if drop.has("deliver"):
			drop.deliver.done = true
	# while larvae are being moved between chambers, a few nurses do the carrying
	if _moved < sim.larvae.size():
		var carriers := 0
		for m in _mates:
			if m.role == "carry":
				carriers += 1
		for m in _mates:
			if carriers >= 4:
				break
			if m.has("script") or m.has("deliver"):
				continue
			if m.role == "nurse" or (m.role == "idle" and carriers == 0):
				m.role = "carry"
				m.goal = _brood_room(_larva_prev)
				m.rest = 0
				m.wander = 0
				m.act_left = 0.0
				carriers += 1
		if carriers == 0:
			_moved = 1 << 20

	var running := speed > 0
	var cells_per_sec := clampf(60.0 * speed / nest.STEP_EVERY, 0.0, 25.0) if running else 0.0
	# cold-blooded: a cool nest slows them, and below ~5 °C they barely stir (winter torpor)
	var chill := clampf((float(sim.climate.nest) - 3.0) / 15.0, 0.06, 1.0)
	var dt := delta * cells_per_sec * chill
	var adt := delta * lerpf(0.25, 1.0, chill) if running else 0.0          # body animation freezes with the clock
	if running:
		_meetings()
	var body: Color = AntModel.tint(sim.sp["body_color"])
	var young: Color = AntModel.tint(sim.sp["callow_color"])
	var xs := []
	var cols := []
	var cus := []
	var larva_loads := []
	var cocoon_loads := []
	var shell_loads := []
	var drops := []
	var pellet_loads := []
	for m in _mates:
		m.anim += adt
		var path: Vector3
		if m.has("script"):
			# hired for a life-cycle moment: walks where the animation needs it
			m.act = m.script.act
			m.face = m.script.face
			path = m.script.pos
		else:
			_update_activity(m, adt)
			if not m.act in STILL_ACTS:
				m.t += dt * (0.25 if sim.tick < int(m.get("weak_until", 0)) else 1.0)
				while m.t >= 1.0 and dt > 0.0:
					m.t -= 1.0
					_step_mate(m)
			path = (m.from as Vector3).lerp(m.to, clampf(m.t, 0.0, 1.0))
		var tr := _smooth(m, path, m.up, delta, m.size)
		m.xf = tr
		if m.act == ACT_FEED and _visible(tr.origin):
			drops.append(tr * Transform3D(Basis.from_scale(Vector3.ONE * (0.8 + 0.3 * sin(m.anim * 3.0))), MOUTH + Vector3(0.2, 0, 0)))
		if _visible(tr.origin):
			xs.append(tr)
			cols.append(_mate_color(m, body, young))
			cus.append(_custom(m, m.act))
			if m.carry:
				if m.get("item", "") == "cocoon":
					cocoon_loads.append(tr * CARRY_OFFSET)
				elif m.get("item", "") == "shell":
					shell_loads.append(tr * CARRY_OFFSET * Transform3D(Basis.from_scale(Vector3(0.85, 0.6, 1.1)), Vector3.ZERO))
				else:
					larva_loads.append(tr * CARRY_OFFSET)
	_emerging(xs, cols, cus, young)

	# diggers come from the simulation; we smooth their hops and show them biting at the dig face
	var seen := {}
	for d in nest.diggers:
		var id: int = d.id
		seen[id] = true
		var c := Vector3(d.cell)
		var v: Dictionary = _dig_vis.get(id, {})
		if v.is_empty():
			v = {"from": c, "to": c, "t": 1.0, "up": _up_at(d.cell), "still": 0.0, "anim": randf() * 100.0}
			_dig_vis[id] = v
		if v.to != c:
			v.from = v.from.lerp(v.to, clampf(v.t, 0.0, 1.0))
			v.to = c
			v.t = 0.0
			v.up = _up_at(d.cell)
			v.still = 0.0
		else:
			v.still += adt
		v.t += dt
		v.anim += adt
		if not v.has("size"):
			v.size = _sample_size()
		var tr := _smooth(v, (v.from as Vector3).lerp(v.to, clampf(v.t, 0.0, 1.0)), v.up, delta, v.size)
		if _visible(tr.origin):
			var act := ACT_CARRY if d.carry else (ACT_DIG if v.still > 0.25 else ACT_WALK)
			xs.append(tr)
			cols.append(body)
			cus.append(_custom(v, act))
			if d.carry:
				pellet_loads.append(tr * CARRY_OFFSET)
	for id in _dig_vis.keys():
		if not seen.has(id):
			_dig_vis.erase(id)

	_ant_mm.instance_count = xs.size()
	for i in xs.size():
		_ant_mm.set_instance_transform(i, xs[i])
		_ant_mm.set_instance_color(i, cols[i])
		_ant_mm.set_instance_custom_data(i, cus[i])
	_fill(_carry_larva_mm, larva_loads)
	_fill(_carry_cocoon_mm, cocoon_loads)
	_fill(_carry_shell_mm, shell_loads)
	_fill(_fx_drop_mm, drops)
	_fill(_carry_pellet_mm, pellet_loads)

	# the queen: rests among her retinue, curls her gaster to lay whenever a new egg appears
	_queen_anim += adt
	if sim.eggs.size() > _last_eggs and running:
		_queen_lay = 2.5
	_last_eggs = sim.eggs.size()
	_queen_lay = maxf(0.0, _queen_lay - adt)
	if _queen_mm.instance_count > 0:
		var qa := _queen_act if _queen_act >= 0 else (ACT_LAY if _queen_lay > 0.0 else ACT_REST)
		_queen_mm.set_instance_custom_data(0, Color(0.0, qa, fmod(_queen_anim, 600.0), 0.0))


func debug_summary() -> String:
	var roles := {}
	var acts := {}
	var carrying := 0
	for m in _mates:
		roles[m.role] = roles.get(m.role, 0) + 1
		acts[m.act] = acts.get(m.act, 0) + 1
		if m.carry:
			carrying += 1
	return "anims %d cam %s d%.1f yaw%.2f cut%.1f | %s %s  roles %s  acts %s  carrying %d  larvae moved %d/%d (%s→%s)  rooms %d  fields %d" % [_anims.size(), target, cam_dist, yaw, cut_offset, sim.clock_text(),
		"air>nest" if sim.climate.air > sim.climate.nest + 0.5 else "air<nest", roles, acts, carrying,
		mini(_moved, sim.larvae.size()), sim.larvae.size(), _larva_prev, _larva_group, _rooms.size(), _fields.size()]
