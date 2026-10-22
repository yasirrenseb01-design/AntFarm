extends "res://scripts/view/nest/parts/nest_duties.gd"
## Nest view, layer 10 of 11: the nestmates walking the real tunnels, their roles and activities,
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
	if m.role in ["nurse", "attend", "idle", "traffic", "wander"]:
		var tries := int(m.get("tries", 0))
		if not _settle(m) and (tries < 3 or (not _cell_fits(m.cell) and tries < 6)):
			# no room in this chamber at all: rest in another one (and never in a narrow tunnel, where everyone
			# passing had to squeeze through it; ants bound for a full chamber used to pile up in its middle)
			m.tries = tries + 1
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
		"wander":
			# walking about: a stop, a look round, and every other time on to another chamber (walking the tunnels all
			# the time, they were in the soil and over the brood twice as often - and side steps had them skating)
			m.rest = randi_range(20, 60)
			m.wander = randi_range(2, 5)
			if randf() < 0.5:
				m.goal = _random_room()
		"giver", "groomer":
			m.rest = 0                                 # on its way to its partner (nest_duties._duty_pairs steers it)
		"traffic":
			# a forager passing through: in at the entrance (crop full of honeydew if it brought some), down to a chamber
			m.rest = randi_range(2, 10)
			if m.goal == -1:
				m.goal = _random_room()
			else:
				m.goal = -1
		"carry":
			# larvae first, then cocoons (each from the old pile to the new one)
			var larva: bool = _moved < sim.larvae.size()
			var cocoon: bool = not larva and _moved_p < sim.pupae.size()
			if m.carry:
				m.carry = false                         # sets it down in the new chamber
				if m.get("item", "") == "cocoon":
					_moved_p += maxi(1, sim.pupae.size() / 10)
				else:
					_moved += maxi(1, sim.larvae.size() / 10)
				m.item = ""
				larva = _moved < sim.larvae.size()
				cocoon = not larva and _moved_p < sim.pupae.size()
				m.goal = _brood_room(_larva_prev if larva else (_pupa_prev if cocoon else _larva_group))
				m.rest = 3
				if not larva and not cocoon:
					m.role = "nurse"
			elif not larva and not cocoon:
				m.role = "nurse"
				m.goal = _brood_room(_larva_group)
			else:
				m.carry = true                          # picks one up from the old pile
				m.item = "cocoon" if cocoon else ""
				m.goal = _brood_room(_larva_group if larva else _pupa_group)
				m.rest = 3


func _step_mate(m: Dictionary) -> void:
	var c: Vector3i = m.cell
	var path: Array = m.get("settle", [])
	if not path.is_empty():
		var n: Vector3i = path.pop_front()          # stepping to the free spot it chose
		if _walkable(n) and not _queen_cells.has(n):
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
			if c + d != m.prev and _walkable(c + d) and not _queen_cells.has(c + d):
				opts.append(c + d)
				if _cell_free(m, c + d):
					clear.append(c + d)
		opts = clear                                 # shuffle about only where there is room
		var on_floor := opts.filter(func(n): return _up_at(n).y > 0.7)
		if not on_floor.is_empty():
			opts.assign(on_floor)                    # (and on the floor, not up the walls)
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
			m.dbg_stuck = here
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
			if _walkable(n):
				best.append(n)
			else:
				floaty.append(n)
		elif fn <= here + 1 and n != m.prev and _walkable(n):
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
		# onward is only across the open middle (of a wide shaft): take it, rather than step aside for ever
		best.assign(floaty if not floaty.is_empty() else (aside_clear if not aside_clear.is_empty() else aside))
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
			# (who gives whom a drop is the simulation's: nest_duties walks the giver to its partner; met by chance,
			# two ants only drum antennae)
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
			# nurses at the brood pile lick the larvae and regurgitate food to them - only a larva within reach
			# of its mouth (else it rests): the droplet is given to a real larva
			m.larva_chk = float(m.get("larva_chk", 0.0)) - delta
			if m.larva_chk <= 0.0:
				m.larva_chk = 1.5
				m.larva_at = _larva_within((m.vp as Vector3) if m.has("vp") else Vector3(m.to), 2.6 * float(m.size))
			var lv: Vector3 = m.get("larva_at", Vector3.INF)
			if lv != Vector3.INF:
				m.act = ACT_FEED if fmod(m.anim + m.cool * 3.0, 11.0) < 4.0 else ACT_TEND
				m.face = lv
			else:
				m.act = ACT_REST
		elif m.role == "attend":
			m.act = ACT_TEND
			m.face = _spots.queen
			if fmod(m.anim, 16.0) > 9.0 and not sim.eggs.is_empty() and not _spots.eggs.is_empty():
				m.face = _egg_xf(0).origin            # licking the egg packet clean
		elif int(m.get("vd", -1)) == Ant.D_GROOM and randf() < 0.5 * delta:
			_begin(m, ACT_GROOM, randf_range(3.0, 6.0))     # its duty: cleaning itself (in bouts)
		elif int(m.get("vd", -1)) != Ant.D_REST and randf() < 0.04 * delta:
			_begin(m, ACT_GROOM, randf_range(2.0, 4.5))     # resting ants groom every so often (not one set to stand still)
		else:
			m.act = ACT_REST
	else:
		m.act = ACT_WALK


const CLR_MAX := 0.3                # how far an ant is lifted clear of the soil (beyond: its legs could not reach)


func _update_ants(delta: float) -> void:
	_bind_workers()                         # one drawn nestmate per real worker inside
	_end_approaches()                       # (nest_duties: givers and groomers that have walked up to their partner)
	_duty_pairs()
	# while larvae or cocoons are being moved between chambers, a few nurses do the carrying
	if _moved < sim.larvae.size() or _moved_p < sim.pupae.size():
		var carriers := 0
		for m in _mates:
			if m.role == "carry":
				carriers += 1
		# those the simulation set to carry brood first (nest_duties), then nurses, then anyone resting
		var order := _mates.duplicate()
		order.sort_custom(func(a, b): return int(a.get("vd", -1) == Ant.D_CARRY) > int(b.get("vd", -1) == Ant.D_CARRY))
		for m in order:
			if carriers >= 4:
				break
			if m.has("script") or m.has("deliver"):
				continue
			if int(m.get("vd", -1)) == Ant.D_CARRY or m.role == "nurse" or (m.role == "idle" and carriers == 0):
				m.role = "carry"
				m.goal = _brood_room(_larva_prev if _moved < sim.larvae.size() else _pupa_prev)
				m.rest = 0
				m.wander = 0
				m.act_left = 0.0
				carriers += 1
		if carriers == 0:
			_moved = 1 << 20
			_moved_p = 1 << 20

	var running := speed > 0
	var cells_per_sec := clampf(60.0 * speed / nest.STEP_EVERY, 0.0, 25.0) if running else 0.0
	# cold-blooded: a cool nest slows them, and below ~5 °C they barely stir (winter torpor)
	var chill := clampf((float(sim.climate.nest) - 3.0) / 15.0, 0.06, 1.0)
	var dt := delta * cells_per_sec * chill
	# body animation freezes with the clock, and below 1x (real time) plays in slow motion with it
	var adt := delta * minf(speed, 1.0) * lerpf(0.25, 1.0, chill) if running else 0.0
	if running:
		_meetings()
	var body: Color = AntModel.body_linear(sim.sp["body_color"])       # (as in the outworld)
	var young: Color = AntModel.body_linear(sim.sp["callow_color"])
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
	var clr_budget := 60
	_gfit_budget = 3
	var near := {}
	for m in _mates + _dig_vis.values():          # the diggers from the simulation have bodies too
		if m.has("xf"):
			var x: Transform3D = m.xf
			var o: Vector3 = x.origin
			var f: Vector3 = x.basis.x.normalized() * (0.7 * float(m.size))
			m.d0 = o + f                 # head-thorax and gaster discs, worked out once per frame
			# (the gaster's disc at its middle, -0.84 of a body: at -0.7 its tip - out to -1.5 - was outside it, and
			# resting ants lay with a head in a nestmate's gaster tip)
			m.d1 = o - f * 1.2
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
	_near_bins = near
	tp = _nprof("ants: bins", tp)
	var us_step := 0
	var us_smooth := 0
	var us_apart := 0
	var us_fit := 0
	var us_climb := 0
	var us_gap := 0
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
		# (stepping off the brood or a nestmate to a free spot: even a chilled ant does that much)
		var mdt := md * cells_per_sec * (maxf(chill, 0.35) if not (m.get("settle", []) as Array).is_empty() else chill)
		var madt := md * minf(speed, 1.0) * lerpf(0.25, 1.0, chill) if running else 0.0
		m.anim += madt
		var path: Vector3
		if m.has("script"):
			# hired for a life-cycle moment: walks where the animation needs it
			m.act = m.script.act
			m.face = m.script.face
			path = m.script.pos
			m.fgap = 1.0
		else:
			var ta := Time.get_ticks_usec()
			m.gap_dt = float(m.get("gap_dt", 0.0)) + md
			var fg := float(m.get("fgap", 1.0))
			if (_mate_frame + mi) % 3 == 1 or fg < 1.0 and fg > 0.0 and (_mate_frame + mi) % 2 == 0:     # (more often while closing on something ahead)
				var tg := Time.get_ticks_usec()
				m.fgap = _gap_ahead(m, near, float(m.gap_dt))     # (a third of the ants each frame, as keeping apart is)
				m.gap_dt = 0.0
				if m.get("stop_here", false):
					m.erase("stop_here")
					m.settle = []
					_arrive(m)                    # (held up in a jam: as near as it gets)
					m.fgap = 1.0
				us_gap += Time.get_ticks_usec() - tg
			_update_activity(m, madt)
			if not m.act in STILL_ACTS:
				m.t += mdt * (0.25 if sim.tick < int(m.get("weak_until", 0)) else 1.0) * float(m.get("fgap", 1.0))
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
				# worked out for a third of the ants each frame, each on its own turn (with the time since its
				# last turn); between, it keeps the shift it has (eased slowly anyway) - the costliest part of
				# the nest view with hundreds of ants
				m.ka_t = float(m.get("ka_t", 0.0)) + md
				if (_mate_frame + mi) % 3 == 0 or not m.has("sep"):
					m.narrow = _cell_narrow(m.cell)
					tr.origin += _keep_apart(m, tr.origin, near, minf(m.ka_t, 0.25))
					_step_aside(m, m.ka_t)
					_make_room(m, m.ka_t)
					m.ka_t = 0.0
				else:
					tr.origin += m.sep
		# (crossing the brood pile, or brushing a larva: up on top of it - see nest_contact._climb, last of all below)
		# lying on the real surface under it: where a chamber floor or wall curves (or drops away) the cell it
		# walks on is not where the ground is - its body is tipped to the slope under its feet, raised or lowered
		# onto it, and its gaster and head bent toward the ground under them (eased)
		# (the same near the camera and far from it: done only for near ones, an ant changed its height as the camera
		# came closer or turned)
		var tf := Time.get_ticks_usec()
		var gfit := _fit_for(m, tr, md, (_mate_frame + mi) % 3 == 0)
		tr = _apply_fit(tr, gfit)
		m.bend = Vector2(gfit[3], gfit[4])
		us_fit += Time.get_ticks_usec() - tf
		# and nothing of its body in the soil where it really stands (a bump, pushed off its cell, turned):
		# checked for a few ants a frame, each again once it has moved or turned a little
		var ck: Vector3 = m.get("clr_at", Vector3.INF)
		var cf: Vector3 = m.get("clr_f", Vector3.ZERO)
		# (and twice a second anyway: a resting ant nudged a little at a time by its neighbours never moved far enough at
		# once to be checked again, and lay with its head in the soil - user, 2026-10-16)
		m.clr_t = float(m.get("clr_t", 0.0)) + md
		if clr_budget > 0 and (ck.x == INF or ck.distance_squared_to(tr.origin) > 0.008 or int(m.get("clr_gen", -1)) != _soil_gen or float(m.clr_t) > 0.5 \
				or cf.dot(tr.basis.x) < 0.97 * cf.length() * tr.basis.x.length() or not m.get("gfit_still", true)):     # (or as it is still settling onto the ground)
			clr_budget -= 1
			m.clr_t = 0.0
			m.clr_at = tr.origin
			m.clr_f = tr.basis.x
			m.clr_gen = _soil_gen
			var cl := _soil_clearance(tr, float(m.size), m.bend)
			# (lifted at most CLR_MAX: higher, its legs hung in the air under it - the keeper saw them dangle; an ant
			# resting there turns to where it fits instead, as for a wall)
			m.clr_own = minf(cl.x, CLR_MAX)
			# its head or gaster in a wall (rising would not clear it), or its front feet over a drop: standing
			# still, it turns away from the wall or the drop, stepping round on the spot
			var still: bool = not m.has("script") and (m.rest > 0 and (m.get("settle", []) as Array).is_empty() or m.act in STILL_ACTS) \
					and (m.get("face", Vector3.INF) as Vector3) == Vector3.INF
			if still and clr_budget > 2 and (cl.y > 0 or cl.x > CLR_MAX or float(m.get("over", 0.0)) < 0.05 and _feet_over_drop(tr) >= 4):
				clr_budget -= 3
				m.rest_dir = _free_heading(m, tr, 0.0)
				# no way round lies clear here (its head or gaster in the soil whichever way it faces):
				# it gets up and finds another spot to rest
				if cl.y > 0 and m.rest_dir == Vector3.ZERO and m.rest > 0 and not m.carry:
					m.wall_n = int(m.get("wall_n", 0)) + 1
					if int(m.wall_n) >= 1:
						m.wall_n = 0
						m.act_left = 0.0
						if not _settle(m) or (m.settle as Array).is_empty():
							m.goal = _random_room()          # (no room near: it goes to rest in another chamber)
							m.rest = 0
							m.wander = 0
							m.settle = []
				else:
					m.wall_n = 0
		# (up quickly out of the soil, down slowly: checked again as it shifts a little, the answer can flip between
		# two heights - at the same speed both ways it bobbed up and down)
		var clr0 := float(m.get("clr", 0.0))
		var clr1 := float(m.get("clr_own", 0.0))
		m.clr = move_toward(clr0, clr1, (2.0 if clr1 > clr0 else 0.3) * md)
		tr.origin += tr.basis.y.normalized() * float(m.clr)
		# how high it is drawn, smoothed once more along its up: the ground under it, its lift clear of the soil and
		# the path's own steps up and down each change a little every frame, and their sum bobbed the body up and
		# down as it walked (not when the drawn ant jumps: moved on after being off screen)
		var upn := tr.basis.y.normalized()
		var hh := (tr.origin - (m.get("vp", tr.origin) as Vector3)).dot(upn)     # (above its path: the up turns, the world does not)
		var hs = m.get("hs")
		if hs == null or absf(hh - float(hs)) > 1.5 or (m.get("hs_up", upn) as Vector3).dot(upn) < 0.9:
			m.hs = hh
		else:
			m.hs = lerpf(float(hs), hh, 1.0 - exp(-12.0 * md))
			tr.origin += upn * (float(m.hs) - hh)
		m.hs_up = upn
		var sgr: float = m.get("sgr", 0.0)
		if sgr > 0.0:
			# stepping aside (see _step_aside): its legs keep pace with the shift every frame
			m.gait = fmod(float(m.gait) + sgr * md, TAU * 64.0)
			m.mv = maxf(float(m.mv), float(m.smv))
		# up on a nestmate's back passing it (see _keep_apart), or on the brood (see nest_contact._climb): last, on the
		# body as it lies on the ground - what is under it is drawn so (raised before, the ground fit then lowered it
		# into them)
		# settled onto the surface under it: drawn a cell or two behind its path, it cut the corners where a floor turns
		# into a wall or a wall into the ceiling, and hung off the surface, legs reaching for nothing (lifted on purpose -
		# clear of the soil, up on another or the brood - it is not pulled down)
		if not m.has("script") and float(m.get("over", 0.0)) < 0.05 and not m.has("over_on"):
			if (_mate_frame + int(m.get("wid", 0))) % 4 == 0 or not m.has("sink_t"):
				m.sink_t = clampf(_gap_under(tr) - float(m.get("clr", 0.0)) - 0.05, 0.0, 1.2)
		else:
			m.sink_t = 0.0
		m.sink = move_toward(float(m.get("sink", 0.0)), float(m.sink_t), 2.5 * md)
		tr.origin -= tr.basis.y.normalized() * float(m.sink)
		var tcl := Time.get_ticks_usec()
		tr = _soil_push(m, tr, md)               # (out of the walls of a narrow bend: nest_contact)
		tr = _climb(m, tr, md, madt)
		us_climb += Time.get_ticks_usec() - tcl
		us_apart += Time.get_ticks_usec() - tc
		# last, its height smoothed once more along its up (the lifts and pushes above - clear of the soil, onto the
		# surface, over another, out of a bend - each eased on its own, together they still bobbed it up and down a
		# little from frame to frame, its planted feet with it: the keeper saw the legs twitch, 2026-10-22). Not
		# when it was moved on a long way (off screen) or turned over onto another surface.
		var up2 := tr.basis.y.normalized()
		var prev_o = m.get("zo")
		if prev_o != null and (prev_o as Vector3).distance_to(tr.origin) < 0.6 and (m.get("zo_up", up2) as Vector3).dot(up2) > 0.95:
			var dz: float = (tr.origin - (prev_o as Vector3)).dot(up2)
			var k2 := 1.0 - exp(-14.0 * md) if md > 0.0 else 1.0
			tr.origin -= up2 * dz * (1.0 - k2)
		m.zo = tr.origin
		m.zo_up = up2
		m.xf = tr
		if m.act == ACT_FEED and not m.has("script") and _visible(tr.origin) and m.get("larva_at", Vector3.INF) != Vector3.INF:
			# the droplet between its mandibles and the larva's head end
			var lm: Vector3 = tr * MOUTH
			var la: Vector3 = m.larva_at
			drops.append(Transform3D(Basis.from_scale(Vector3.ONE * (0.6 + 0.2 * sin(m.anim * 3.0))), lm.lerp(la + Vector3(0, 0.25, 0), 0.25)))
		if _shown(tr):
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
	fprof["ants: ground fit"] = fprof.get("ants: ground fit", 0) + us_fit
	fprof["ants: climb"] = fprof.get("ants: climb", 0) + us_climb
	fprof["ants: look ahead"] = fprof.get("ants: look ahead", 0) + us_gap
	tp = _nprof("ants: loop (all)", tp)
	_emerging(xs, cols, cus, young)

	# diggers come from the simulation; we smooth their hops and show them biting at the dig face
	var seen := {}
	for d in nest.diggers:
		var id: int = d.id
		seen[id] = true
		var cell: Vector3i = _on_soil(d.cell)
		var c := Vector3(cell)
		var v: Dictionary = _dig_vis.get(id, {})
		if v.is_empty():
			v = {"from": c, "to": c, "t": 1.0, "up": _up_at(cell), "still": 0.0, "anim": randf() * 100.0}
			_dig_vis[id] = v
		if v.to != c:
			v.from = v.from.lerp(v.to, clampf(v.t, 0.0, 1.0))
			v.to = c
			v.t = 0.0
			v.up = _up_at(cell)
			v.still = 0.0
		else:
			v.still += adt
		v.t += dt
		v.anim += adt
		if not v.has("size"):
			v.size = _sample_size()
		v.cell = cell
		# biting at the dig face: it faces the soil it digs (where it last stepped, else the nearest soil beside it)
		if v.still > 0.25:
			if not v.has("face_at") or v.face_cell != cell:
				v.face_cell = cell
				v.face_at = _dig_face(cell, d.dir)
			v.face = v.face_at
		else:
			v.face = Vector3.INF
		var tr := _smooth(v, (v.from as Vector3).lerp(v.to, clampf(v.t, 0.0, 1.0)), v.up, delta, v.size)
		if _visible(tr.origin):
			v.ka_t = float(v.get("ka_t", 0.0)) + delta
			if (_mate_frame + id) % 3 == 0 or not v.has("sep"):
				tr.origin += _keep_apart(v, tr.origin, near, minf(v.ka_t, 0.25))   # (a third each frame, as above)
				v.ka_t = 0.0
			else:
				tr.origin += v.sep
		# lying on the ground and clear of the soil as the nestmates do (a digger drawn on its cell alone stood with
		# its body in the soil it was digging: in the x-ray view ants seemed to come up out of the ground) - its
		# head may be at the face it bites
		var dfit := _fit_for(v, tr, delta, (_mate_frame + id) % 3 == 0)
		tr = _apply_fit(tr, dfit)
		v.bend = Vector2(dfit[3], dfit[4])
		if (_mate_frame + id) % 3 == 2 or not v.has("dclr"):
			v.dclr = _soil_clearance(tr, float(v.size), v.bend, v.still > 0.25).x
		v.clr = move_toward(float(v.get("clr", 0.0)), float(v.dclr), (2.0 if float(v.dclr) > float(v.get("clr", 0.0)) else 0.3) * delta)
		tr.origin += tr.basis.y.normalized() * float(v.clr)
		v.xf = tr
		if _shown(tr):
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
		_sel_mm.set_instance_color(0, Color.WHITE)       # (its alpha carries nothing: the body parts are in the mesh's own)
	# written as one buffer (a call per instance per field was a millisecond or more with hundreds of ants)
	if _ant_mm.instance_count != xs.size():
		_ant_mm.instance_count = xs.size()
	var buf := PackedFloat32Array()
	buf.resize(xs.size() * 20)
	var k := 0
	for i in xs.size():
		var x: Transform3D = xs[i]
		var c: Color = cols[i]
		var u: Color = cus[i]
		buf[k] = x.basis.x.x; buf[k + 1] = x.basis.y.x; buf[k + 2] = x.basis.z.x; buf[k + 3] = x.origin.x
		buf[k + 4] = x.basis.x.y; buf[k + 5] = x.basis.y.y; buf[k + 6] = x.basis.z.y; buf[k + 7] = x.origin.y
		buf[k + 8] = x.basis.x.z; buf[k + 9] = x.basis.y.z; buf[k + 10] = x.basis.z.z; buf[k + 11] = x.origin.z
		buf[k + 12] = c.r; buf[k + 13] = c.g; buf[k + 14] = c.b; buf[k + 15] = c.a
		buf[k + 16] = u.r; buf[k + 17] = u.g; buf[k + 18] = u.b; buf[k + 19] = u.a
		k += 20
	if xs.size() > 0:
		_ant_mm.buffer = buf
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
		var dturn := wrapf(_queen_turn - _queen_prev_turn, -PI, PI)
		var turned := absf(dturn)
		_queen_prev_turn = _queen_turn
		var walked: float = ((_queen_step - _queen_step_prev).length() + ((_spots.queen as Vector3) - _queen_home_prev).length()) / QUEEN_SCALE
		_queen_step_prev = _queen_step
		_queen_home_prev = _spots.queen
		var qs := 0.6                       # short, heavy steps
		# a foot ~1.1 model units out sweeps that far per radian turned: the steps keep pace with the turn
		var sweep := turned * 1.1
		_queen_gait = fmod(_queen_gait + (sweep + walked) / AntModel.stride_len(qs) * TAU, TAU * 64.0)
		var moving := adt > 0.0 and (turned / adt > 0.05 or walked / adt > 0.03)      # (by rate: right at any speed)
		_queen_mv = lerpf(_queen_mv, 1.0 if moving else 0.0, minf(1.0, 8.0 * adt))
		var tshare := sweep / maxf(sweep + walked, 0.0001) * signf(dturn) if moving else 0.0
		_queen_tshare = lerpf(_queen_tshare, tshare, minf(1.0, 6.0 * adt))
		var qa := _queen_act if _queen_act >= 0 else (ACT_LAY if _queen_lay > 0.0 else _queen_mode)
		_queen_vact = AntModel.act_step(_queen_vact, qa, _queen_anim, AntModel.QUEEN_BLEND)     # she eases slowly from one pose into the next
		_queen_mm.set_instance_custom_data(0, Color(_queen_gait, AntModel.act_y(_queen_vact, _queen_anim, AntModel.QUEEN_BLEND), fmod(_queen_anim, 600.0), AntModel.gait_w(_queen_mv, qs, _queen_tshare)))
	var q_sel: bool = sel_kind == "queen" and _queen_mm.instance_count > 0
	_sel_queen_mm.instance_count = 1 if q_sel else 0
	if q_sel:
		_sel_queen_mm.set_instance_transform(0, _queen_xf)
		_sel_queen_mm.set_instance_custom_data(0, _queen_mm.get_instance_custom_data(0))
		_sel_queen_mm.set_instance_color(0, Color.WHITE)


## Where a digger is drawn for the cell the simulation has it in: on the way to planned work it may cut across the
## middle of a tunnel or a chamber (sim nest_volume._step_digger), and drawn there it hung in the air - a swarm of
## them looked like flying ants round the work. It is drawn on the nearest floor or wall instead: straight below
## first (a few voxels), else the nearest cell beside soil.
func _on_soil(c: Vector3i) -> Vector3i:
	if _walkable(c):
		return c
	for k in range(1, 5):
		var b := c - Vector3i(0, k, 0)
		if not nest.is_open(b):
			break
		if _walkable(b):
			return b
	var best := c
	var bd := INF
	for dz in range(-2, 3):
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var n := c + Vector3i(dx, dy, dz)
				var dd := float(dx * dx + dy * dy * 1.5 + dz * dz)      # (a little rather on the floor than overhead)
				if dd < bd and _walkable(n):
					bd = dd
					best = n
	return best
