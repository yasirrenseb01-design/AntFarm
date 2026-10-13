extends "res://scripts/view/nest/parts/nest_bodies.gd"
## Nest view, layer 7 of 8: the nestmates walking the real tunnels, their roles and activities,
## meetings, the queen's idle life, and the diggers from the simulation.


func _move_mate(m: Dictionary, n: Vector3i) -> void:
	m.prev = m.cell
	m.cell = n
	m.from = m.to
	m.to = Vector3(n)
	m.up = _up_at(n)


## What an ant does when it reaches the place it was heading for.
func _arrive(m: Dictionary) -> void:
	if m.get("leaving", false):
		m.gone = true                                  # out through the entrance: the outworld draws it now
		return
	if m.has("deliver"):
		m.deliver.done = true                       # cocoon set down, or empty shell taken out
		m.erase("deliver")
		m.carry = false
		m.item = ""
		if m.goal == -1:
			m.goal = _brood_room(_larva_group)
	if m.role in ["nurse", "attend", "idle", "traffic"]:
		if not _settle(m) and m.role == "idle" and int(m.get("tries", 0)) < 3:
			# no room in this chamber at all: rest in another one
			m.tries = int(m.get("tries", 0)) + 1
			m.goal = _random_room()
			m.wander = 2
			return
		m.tries = 0
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
	var path: Array = m.get("settle", [])
	if not path.is_empty():
		var n: Vector3i = path.pop_front()          # stepping to the free spot it chose
		if nest.walkable(n) and not _queen_cells.has(n):
			_move_mate(m, n)
		else:
			m.settle = []
		return
	if m.rest > 0:
		m.rest -= 1
		m.from = m.to
		return
	if m.wander > 0:
		m.wander -= 1
		var opts: Array[Vector3i] = []
		var clear: Array[Vector3i] = []
		for d in DIRS:
			if c + d != m.prev and nest.walkable(c + d) and not _queen_cells.has(c + d):
				opts.append(c + d)
				if _cell_free(m, c + d):
					clear.append(c + d)
		opts = clear                                 # shuffle about only where there is room
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
	# getting no nearer (the way in is blocked by the brood, the queen or a nestmate it keeps meeting):
	# after a few steps this is as close as it gets - it stops here (first workers in a crowded founding
	# cell used to pace to and fro for ever)
	if m.get("near_goal", -99) != m.goal or here < int(m.get("near", 1 << 20)):
		if m.get("near_goal", -99) != m.goal:
			m.crossed = false
		m.near_goal = m.goal
		m.near = here
		m.stuck = 0
	else:
		m.stuck = int(m.get("stuck", 0)) + 1
		if m.stuck >= 6 and int(m.get("cross", 0)) == 0 and not m.get("crossed", false):
			m.cross = 8                       # no way round: it climbs over the brood pile (user, 2026-10-13)
			m.crossed = true
			m.stuck = 0
		elif m.stuck >= 6:
			m.stuck = 0
			m.near = 1 << 20
			m.crossed = false
			_arrive(m)
			return
	var best: Array[Vector3i] = []
	var floaty: Array[Vector3i] = []
	var aside: Array[Vector3i] = []
	var by_queen := false
	for d in DIRS:
		var n := c + d
		var fn: int = field.get(n, 1 << 20)
		if _queen_cells.has(n):
			by_queen = by_queen or fn < here
			continue                    # the queen lies there: walk round her
		if fn < here:
			if nest.walkable(n):
				best.append(n)
			else:
				floaty.append(n)
		elif fn <= here + 1 and n != m.prev and nest.walkable(n):
			aside.append(n)
	if by_queen and here <= 6:
		# the middle of the chamber is under the queen: beside her is as far as anyone gets (without this,
		# ants bound for her chamber paced to and fro round her for ever)
		_arrive(m)
		return
	# go round the brood: onward onto free floor if there is any, else a step aside round the pile (for a
	# while - a pile across the whole tunnel has to be crossed in the end)
	var crossing := int(m.get("cross", 0)) > 0
	if crossing:
		m.cross = int(m.cross) - 1
	var best_clear := best if crossing else best.filter(func(n): return not _brood_cells.has(n))
	var aside_clear := aside.filter(func(n): return not _brood_cells.has(n))
	var detour: int = m.get("detour", 0)
	if not best_clear.is_empty():
		best.assign(best_clear)
		m.detour = 0
	elif not best.is_empty() and not aside_clear.is_empty() and detour < 8:
		best.assign(aside_clear)
		m.detour = detour + 1
	elif best.is_empty():
		best.assign(aside_clear if not aside_clear.is_empty() else (aside if not aside.is_empty() else floaty))
	if here <= 4 and not best.is_empty() and not crossing:
		# nearly there, and the way on is onto the brood pile or a nestmate: this is near enough
		# (the chamber's middle is where its brood lies) - stop and pick a free spot here instead
		var clear := best.filter(func(n): return _cell_free(m, n))
		if clear.is_empty():
			_arrive(m)
			return
		best.assign(clear)
	if not best.is_empty():
		_move_mate(m, best[randi() % best.size()])


func _sample_size() -> float:
	return sim.workers[randi() % sim.workers.size()].size if not sim.workers.is_empty() else 1.0


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
				_start_feed(m if m.fed else o, o if m.fed else m)       # the one with a full crop gives
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
	elif not (m.get("settle", []) as Array).is_empty():
		m.act = ACT_WALK
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


func _update_ants(delta: float) -> void:
	_bind_workers()                         # one drawn nestmate per real worker inside
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
	# body animation freezes with the clock, and below 1x (real time) plays in slow motion with it
	var adt := delta * minf(speed, 1.0) * lerpf(0.25, 1.0, chill) if running else 0.0
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
	# where everyone stood last frame, binned by cell: nestmates keep a body width apart instead of
	# standing inside one another (the queen, much bigger, keeps a wider berth)
	var tp := Time.get_ticks_usec()                # (dev --perf: where this function's time goes)
	var sel_at := []                  # the selected ant's transform and pose, for its outline
	var near := {}
	for m in _mates + _dig_vis.values():          # the diggers from the simulation have bodies too
		if m.has("xf"):
			var x: Transform3D = m.xf
			var o: Vector3 = x.origin
			var f: Vector3 = x.basis.x.normalized() * (0.7 * float(m.size))
			m.d0 = o + f                 # head-thorax and gaster discs, worked out once per frame
			m.d1 = o - f
			var key := Vector3i(floori(o.x / 3.0), floori(o.y / 3.0), floori(o.z / 3.0))
			if not near.has(key):
				near[key] = []
			near[key].append(m)
	# workers still being pulled out of their cocoons have bodies too (they stay put; the others step round)
	for a in _anims:
		if a.k == "eclose" and a.t / a.d > 0.3:
			var ep := _eclose_parts(a, a.t / a.d)
			var cx: Transform3D = ep.callow
			var cf: Vector3 = cx.basis.x.normalized() * (0.7 * float(a.s))
			var cbody := {"callow": true, "xf": cx, "size": a.s, "d0": cx.origin + cf, "d1": cx.origin - cf}
			var ck := Vector3i(floori(cx.origin.x / 3.0), floori(cx.origin.y / 3.0), floori(cx.origin.z / 3.0))
			if not near.has(ck):
				near[ck] = []
			near[ck].append(cbody)
	tp = _nprof("ants: bins", tp)
	var us_step := 0
	var us_smooth := 0
	var us_apart := 0
	_mate_cells.clear()
	for m in _mates:
		_mate_cells[m.cell] = m
		var st: Array = m.get("settle", [])
		if not st.is_empty():
			_mate_cells[st[-1]] = m
	for v in _dig_vis.values():
		_mate_cells[Vector3i(roundi(v.to.x), roundi(v.to.y), roundi(v.to.z))] = v
	_mate_frame += 1
	for mi in _mates.size():
		var m: Dictionary = _mates[mi]
		# off screen a nestmate is moved on only every fourth frame (with the time it missed): it is not drawn
		m.lag = float(m.get("lag", 0.0)) + delta
		var seen_now: bool = not m.has("xf") or _visible((m.xf as Transform3D).origin)
		if not seen_now and not m.has("script") and (_mate_frame + mi) % 4 != 0:
			continue
		var md: float = m.lag
		m.lag = 0.0
		var mdt := md * cells_per_sec * chill
		var madt := md * minf(speed, 1.0) * lerpf(0.25, 1.0, chill) if running else 0.0
		m.anim += madt
		var path: Vector3
		if m.has("script"):
			# hired for a life-cycle moment: walks where the animation needs it
			m.act = m.script.act
			m.face = m.script.face
			path = m.script.pos
		else:
			var ta := Time.get_ticks_usec()
			_update_activity(m, madt)
			if not m.act in STILL_ACTS:
				m.t += mdt * (0.25 if sim.tick < int(m.get("weak_until", 0)) else 1.0)
				while m.t >= 1.0 and mdt > 0.0:
					m.t -= 1.0
					_step_mate(m)
			path = (m.from as Vector3).lerp(m.to, clampf(m.t, 0.0, 1.0))
			us_step += Time.get_ticks_usec() - ta
		m.stride = AntModel.stride_scale(chill, m.carry)      # shorter, slower steps when cold or laden
		var tb := Time.get_ticks_usec()
		var tr := _smooth(m, path, m.up, md, m.size)
		var tc := Time.get_ticks_usec()
		us_smooth += tc - tb
		if _visible(tr.origin):
			if m.has("partner"):
				m.sep = (m.get("sep", Vector3.ZERO) as Vector3).move_toward(Vector3.ZERO, 3.0 * md)   # (feeding: stands where it stepped to)
				tr.origin += m.sep
			else:
				tr.origin += _keep_apart(m, tr.origin, near, md)      # only where anyone can see it
		# crossing the brood pile: up on top of it (eased, so it climbs on and steps down)
		var want_lift := _brood_top(tr.origin) if _on_brood(m) else 0.0
		m.blift = move_toward(float(m.get("blift", 0.0)), want_lift, 1.5 * md)
		tr.origin += tr.basis.y.normalized() * float(m.blift)
		us_apart += Time.get_ticks_usec() - tc
		m.xf = tr
		if m.act == ACT_FEED and not m.has("script") and _visible(tr.origin):
			drops.append(tr * Transform3D(Basis.from_scale(Vector3.ONE * (0.8 + 0.3 * sin(m.anim * 3.0))), MOUTH + Vector3(0.2, 0, 0)))
		if _visible(tr.origin):
			xs.append(tr)
			cols.append(_mate_color(m, body, young))
			cus.append(_custom(m, m.act))
			if sel_kind == "worker" and int(m.get("wid", -1)) == sel_id:
				sel_at = [tr, cus[-1]]
			if m.carry:
				if m.get("item", "") == "cocoon":
					cocoon_loads.append(tr * CARRY_OFFSET)
				elif m.get("item", "") == "shell":
					shell_loads.append(tr * CARRY_OFFSET * Transform3D(Basis.from_scale(Vector3(0.85, 0.6, 1.1)), Vector3.ZERO))
				else:
					larva_loads.append(tr * CARRY_OFFSET)
	fprof["ants: activity+route"] = fprof.get("ants: activity+route", 0) + us_step
	fprof["ants: smooth"] = fprof.get("ants: smooth", 0) + us_smooth
	fprof["ants: keep apart"] = fprof.get("ants: keep apart", 0) + us_apart
	tp = _nprof("ants: loop (all)", tp)
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
			tr.origin += _keep_apart(v, tr.origin, near, delta)
		v.xf = tr
		if _visible(tr.origin):
			var act := ACT_CARRY if d.carry else (ACT_DIG if v.still > 0.25 else ACT_WALK)
			xs.append(tr)
			cols.append(body)
			cus.append(_custom(v, act))
			if sel_kind == "digger" and id == sel_id:
				sel_at = [tr, cus[-1]]
			if d.carry:
				pellet_loads.append(tr * CARRY_OFFSET)
	for id in _dig_vis.keys():
		if not seen.has(id):
			_dig_vis.erase(id)

	tp = _nprof("ants: diggers", tp)
	_sel_mm.instance_count = 1 if not sel_at.is_empty() else 0
	if not sel_at.is_empty():
		_sel_mm.set_instance_transform(0, sel_at[0])
		_sel_mm.set_instance_custom_data(0, sel_at[1])
	_ant_mm.instance_count = xs.size()
	for i in xs.size():
		_ant_mm.set_instance_transform(i, xs[i])
		_ant_mm.set_instance_color(i, cols[i])
		_ant_mm.set_instance_custom_data(i, cus[i])
	_fill(_carry_larva_mm, larva_loads)
	_fill(_carry_cocoon_mm, cocoon_loads)
	_fill(_carry_shell_mm, shell_loads)
	drops.append_array(_anim_drops)
	_fill(_fx_drop_mm, drops)
	_fill(_carry_pellet_mm, pellet_loads)

	# the queen: rests among her retinue, curls her gaster to lay whenever a new egg appears
	_queen_anim += adt
	if sim.eggs.size() > _last_eggs and running:
		_queen_lay = 2.5
	_last_eggs = sim.eggs.size()
	_queen_lay = maxf(0.0, _queen_lay - adt)
	if _queen_mm.instance_count > 0:
		# between lifecycle moments she is not a statue: she rests, grooms, feels about with her antennae
		# and now and then shifts round on the spot, stepping as she turns
		_queen_mode_left -= adt
		if _queen_mode_left <= 0.0 and _queen_act < 0:
			var r := randf()
			_queen_mode = ACT_REST if r < 0.45 else (ACT_GROOM if r < 0.65 else (ACT_ANTENNATE if r < 0.85 else ACT_WALK))
			_queen_mode_left = randf_range(3.0, 9.0)
			if _queen_mode == ACT_WALK:
				_queen_turn_t = _queen_turn + randf_range(0.5, 1.2) * (1.0 if randf() < 0.5 else -1.0)
		var turned := absf(wrapf(_queen_turn - _queen_prev_turn, -PI, PI))
		_queen_prev_turn = _queen_turn
		var walked := (_queen_step - _queen_step_prev).length() / QUEEN_SCALE
		_queen_step_prev = _queen_step
		var qs := 0.6                       # short, heavy steps
		_queen_gait = fmod(_queen_gait + (turned * 0.9 + walked) / AntModel.stride_len(qs) * TAU, TAU * 64.0)
		_queen_mv = lerpf(_queen_mv, 1.0 if turned > 0.002 or walked > 0.001 else 0.0, minf(1.0, 8.0 * adt))
		var qa := _queen_act if _queen_act >= 0 else (ACT_LAY if _queen_lay > 0.0 else _queen_mode)
		_queen_vact = AntModel.act_step(_queen_vact, qa, _queen_anim, AntModel.QUEEN_BLEND)     # she eases slowly from one pose into the next
		_queen_mm.set_instance_custom_data(0, Color(_queen_gait, AntModel.act_y(_queen_vact, _queen_anim, AntModel.QUEEN_BLEND), fmod(_queen_anim, 600.0), AntModel.gait_w(_queen_mv, qs)))
	var q_sel: bool = sel_kind == "queen" and _queen_mm.instance_count > 0
	_sel_queen_mm.instance_count = 1 if q_sel else 0
	if q_sel:
		_sel_queen_mm.set_instance_transform(0, _queen_xf)
		_sel_queen_mm.set_instance_custom_data(0, _queen_mm.get_instance_custom_data(0))


## Dev (--trace): the nestmates within reach of the queen: role, activity, rest/wander left, position.
func trace_near_queen() -> String:
	var out := []
	for m in _mates:
		if m.has("xf") and (m.xf as Transform3D).origin.distance_to(_spots.queen) < 7.0:
			var o: Vector3 = (m.xf as Transform3D).origin
			out.append("%s%s a%d r%d w%d (%.1f,%.1f,%.1f) sep%.2f" % [m.role, "*" if m.has("script") else "", m.act, m.rest, m.wander,
				o.x, o.y, o.z, (m.get("sep", Vector3.ZERO) as Vector3).length()])
	return " | ".join(out)


## Dev (--trace-mates): every nestmate: role, activity, cell, goal room, carrying what, settle/step state.
func trace_mates() -> String:
	var out := []
	for m in _mates:
		var o: Vector3 = (m.xf as Transform3D).origin if m.has("xf") else Vector3(m.cell)
		var line := "w%s %s%s a%d c%s->%s goal%s carry%s/%s r%d w%d t%.2f set%d" % [m.get("wid", -1), m.role,
			"*" if m.has("script") else "", m.act, m.cell, m.to, m.get("goal", -9), m.carry, m.get("item", ""),
			m.rest, m.wander, m.t, (m.get("settle", []) as Array).size()]
		out.append(line + " here%d free%s lift%.2f" % [(_fields.get(m.goal, {}) as Dictionary).get(m.cell, -1), _cell_free(m, m.cell), float(m.get("blift", 0.0))])
	for id in _dig_vis:
		out.append("dig%d" % id)
	return " | ".join(out)


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
