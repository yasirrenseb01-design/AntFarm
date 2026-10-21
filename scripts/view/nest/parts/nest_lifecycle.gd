extends "res://scripts/view/nest/parts/nest_piles.gd"
## Nest view, layer 5 of 10: life-cycle moments acted out from sim.events (egg laying, pupation,
## eclosion, carrying the empty cocoon out).


func _anim_k() -> float:
	return 1.0 / clampf(sqrt(speed), 1.0, 2.3)


func _poll_events() -> void:
	var watch := speed > 0.0 and speed <= 5.0
	for e in _feed.take():
		if not watch:
			continue
		var busy := 0
		for a in _anims:
			if a.k == e.k:
				busy += 1
		match e.k:
			"egg":
				if busy < 2:
					_start_egg()
			"pupate":
				if busy < 2:
					_start_pupate(e.s)
			"eclose":
				if busy < 3:
					_start_eclose(e.s)


## Nearby nestmates free to help; they must be close, since they walk straight to the spot.
func _helpers(p: Vector3, n: int, max_d := 6.0) -> Array:
	var cands := []
	for m in _mates:
		if m.has("script") or m.has("deliver") or m.carry or m.role == "carry" or m.role == "traffic":
			continue
		var d := Vector3(m.cell).distance_to(p)
		if d < max_d:
			cands.append([d - (4.0 if int(m.get("vd", -1)) == Ant.D_CARRY else 0.0), m])     # (set to carry brood: first)
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	for c in cands.slice(0, n):
		out.append(c[1])
	return out


## Take a nestmate off its usual routine and walk it to `goal` (a floor point).
func _hire(m: Dictionary, goal: Vector3, face: Vector3, act: int) -> void:
	var from: Vector3 = (m.vp as Vector3) + (m.vu as Vector3) * 0.4 if m.has("vp") else Vector3(m.to)
	m.script = {"pos": from, "goal": goal + Vector3(0, 0.45, 0), "face": face, "act": act}


func _release(m: Dictionary) -> void:
	if not m.has("script"):
		return
	var p: Vector3 = m.script.pos
	m.erase("script")
	var c := Vector3i(roundi(p.x), roundi(p.y), roundi(p.z))
	if _walkable(c):
		m.cell = c
		m.prev = c
		m.from = Vector3(c)
		m.to = Vector3(c)
		m.t = 1.0
		m.up = _up_at(c)
	m.rest = randi_range(20, 80)


func _beside(p: Vector3, m: Dictionary, dist := 1.6) -> Vector3:
	var d: Vector3 = Vector3(m.cell) - p
	d.y = 0.0
	if d.length_squared() < 0.01:
		d = Vector3(randf() - 0.5, 0, randf() - 0.5)
	return p + d.normalized() * dist


func _start_egg() -> void:
	if not _queen_path.is_empty():
		return                         # (on her way to another chamber: she lays once she is there)
	if not sim.queen.alive or _spots.queen == Vector3.ZERO:
		return
	var pile: Vector3 = _egg_xf(_next_egg_slot()).origin if not _spots.eggs.is_empty() else _spots.queen
	var a := {"k": "egg", "t": 0.0, "d": 22.0 * _anim_k(), "pile": pile, "helper": null}   # slow enough to watch
	var hs := _helpers(_spots.queen, 1, 7.0)
	if not hs.is_empty():
		a.helper = hs[0]
		_hire(a.helper, _beside(_queen_xf * GASTER_TIP, a.helper, 1.2), _queen_xf * GASTER_TIP, ACT_TEND)
	_anims.append(a)


## A founding queen with no workers yet tends her brood herself (claustral founding: she licks the eggs
## clean, feeds the larvae from her own reserves - trophic eggs and saliva, Janet 1907 - and sees to the
## cocoons). Now and then she turns to one of them, steps up, works over it with her mouthparts for a while
## and goes back to her place. Nothing in the pile moves. (How often, and for how long: chosen, not measured.)
func _start_care(want := "") -> void:
	if not _queen_path.is_empty():
		return
	var kinds := []
	if _egg_mm.instance_count > 0:
		kinds.append([_egg_mm, "eggs"])
	if _larva_mm.instance_count > 0:
		kinds.append([_larva_mm, "larvae"])
		kinds.append([_larva_mm, "larvae"])              # (the larvae need her most: fed as well as cleaned)
	if _pupa_mm.instance_count > 0:
		kinds.append([_pupa_mm, "pupae"])
	if kinds.is_empty():
		return
	var pick: Array = kinds[randi() % kinds.size()]
	for k in kinds:
		if k[1] == want:
			pick = k                                      # (dev --anim=care --care=eggs: that kind)
	# she goes to the nearest one of that kind (the outside of the egg packet, the near edge of the pile)
	var mm: MultiMesh = pick[0]
	var home: Vector3 = _spots.queen + Vector3.UP * QUEEN_LIFT + _queen_step
	var p := Vector3.INF
	var sc := 1.0
	for i in mm.instance_count:
		var xf: Transform3D = mm.get_instance_transform(i)
		if xf.origin.distance_to(home) < p.distance_to(home):
			p = xf.origin
			sc = xf.basis.get_scale().x
	if p == Vector3.INF or p.distance_to(_spots.queen) > 9.0:
		return                                            # (brood carried off to another chamber)
	# how far from its middle her mandible tips stop: just touching it (egg ~0.3 across, a larva lying on its
	# side ~0.36 x its size, a cocoon 0.62 x its size)
	var contact: float = {"eggs": 0.08, "larvae": 0.25 * sc, "pupae": 0.68 * sc}[pick[1]]
	_anims.append({"k": "care", "t": 0.0, "d": randf_range(14.0, 22.0) * _anim_k(), "at": p, "what": pick[1], "contact": contact})


## A founding queen's own egg, after laying it (`u` = progress of the moment; the steps that follow wait for
## her: turning a heavy body takes as long as it takes).
func _queen_egg_moment(a: Dictionary, u: float) -> void:
	var home: Vector3 = _spots.queen + Vector3.UP * QUEEN_LIFT
	if not a.has("turn0"):
		a.turn0 = _queen_turn
		a.step0 = _queen_step
		var to: Vector3 = (a.pile as Vector3) - (home + _queen_step)
		a.turn1 = atan2(-to.z, to.x)
	if u < 0.34:
		_queen_act = ACT_TAKE_EGG                         # gaster curled under, head bowed to the tip
		_queen_turn_t = a.turn0
		_queen_step_t = a.step0
		return
	if not a.has("down_at"):
		# holding the egg up, she turns to the packet; once facing it she steps up to it
		_queen_act = ACT_CARRY
		_queen_turn_t = a.turn1
		if not a.has("step"):
			var face := Transform3D(Basis(Vector3.UP, a.turn1).scaled(Vector3.ONE * QUEEN_SCALE), home + _queen_step)
			var reach: Vector3 = ((a.pile as Vector3) - face * MOUTH_CARRY) * Vector3(1, 0, 1)
			reach -= reach.normalized() * 0.25 if reach.length() > 0.25 else reach
			a.step = _queen_step + reach.limit_length(3.5)
			for k in 8:
				if _queen_feet_clear(home + (a.step as Vector3), a.turn1):
					break
				a.step = _queen_step + ((a.step as Vector3) - _queen_step) * 0.85
		if absf(wrapf(a.turn1 - _queen_turn, -PI, PI)) < 0.12:
			a.stepping = true
		_queen_step_t = a.step if a.get("stepping", false) else a.step0
		if a.get("stepping", false) and (_queen_step - (a.step as Vector3)).length() < 0.08 and u > 0.4:
			a.down_at = a.t
		return
	var since: float = a.t - a.down_at
	if since < 2.2:
		_queen_act = ACT_TEND                             # bowed over the packet: sets it down, a lick
		_queen_turn_t = a.turn1
		_queen_step_t = a.step
		return
	# back to her place
	_queen_act = ACT_WALK
	_queen_turn_t = a.turn0
	_queen_step_t = a.step0
	if absf(wrapf(a.turn0 - _queen_turn, -PI, PI)) < 0.03 and (_queen_step - (a.step0 as Vector3)).length() < 0.05:
		a.done = true


## Whether her six feet (roughly where they stand, in her model) would be on open floor with her centre at
## `at` facing `turn`, not in the soil of a chamber wall.
func _queen_feet_clear(at: Vector3, turn: float) -> bool:
	var xf := Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * QUEEN_SCALE), at)
	var mid := _floor_cached(at)
	for f in [Vector3(0.8, 0, 0.85), Vector3(0.8, 0, -0.85), Vector3(-0.1, 0, 1.1), Vector3(-0.1, 0, -1.1),
			Vector3(-0.85, 0, 1.0), Vector3(-0.85, 0, -1.0)]:
		var p: Vector3 = xf * f
		var fl := _floor_cached(p)
		# a foot can reach ~0.9 above or ~0.6 below where she stands (shader: -0.36..0.6 of her size)
		if fl - mid > 0.9 or mid - fl > 0.6 or _density_at(Vector3(p.x, fl + 0.15, p.z)) >= 0.5:
			return false
	return true


## How far (in steps of a quarter body, up to 3 bodies) the floor runs open from p along heading yaw.
func _open_run(p: Vector3, yaw: float, s: float) -> int:
	var bx := Basis(Vector3.UP, yaw).x
	for k in range(1, 13):
		var q: Vector3 = p + bx * (0.25 * k * s + 1.35 * s)
		var fl := _floor_cached(q)
		if absf(fl - p.y) > 0.8 or _density_at(Vector3(q.x, fl + 0.3, q.z)) >= 0.5 or not _floor_solid(q):
			return k
	return 13


## The eclosion's progress on its own timeline: the opening and pulling out take the first 70% of the time,
## and the end - the newcomer peeled, rolling upright, licked clean and given its first meal - the last 30%
## (it used to be over in two seconds).
func _ecl_u(r: float) -> float:
	return r / 0.7 * 0.85 if r < 0.7 else 0.85 + (r - 0.7) / 0.3 * 0.15


## A founding queen opening her first cocoons: she steps up until her mandibles are at the cocoon's head end,
## bites the silk open, then backs away a little at each tug as the callow comes out (her mouth on its head),
## and goes back to her place.
func _queen_eclose(a: Dictionary, u: float, ep: Dictionary, callow_head: Vector3) -> void:
	var home: Vector3 = _spots.queen + Vector3.UP * QUEEN_LIFT
	if not a.has("q_turn0"):
		a.q_turn0 = _queen_turn
		a.q_step0 = _queen_step
		var d0: Vector3 = (ep.head as Vector3) - (home + _queen_step)
		a.q_turn = atan2(-d0.z, d0.x)
	if u >= 0.92:
		_queen_turn_t = a.q_turn0
		_queen_step_t = a.q_step0
		_queen_act = ACT_WALK
		return
	var grip: Vector3 = ep.head if u < 0.5 else callow_head
	_queen_turn_t = a.q_turn
	var face := Transform3D(Basis(Vector3.UP, a.q_turn).scaled(Vector3.ONE * QUEEN_SCALE), home + _queen_step)
	var reach: Vector3 = (grip - face * TIP_LICK) * Vector3(1, 0, 1)
	var want: Vector3 = _queen_step + reach.limit_length(4.0)
	if not _queen_feet_clear(home + want, a.q_turn):
		want = _queen_step                  # (no room to step there: she reaches from where she is)
	var turned := absf(wrapf(a.q_turn - _queen_turn, -PI, PI)) < 0.12
	_queen_step_t = want if turned else a.q_step0
	if not turned or (_queen_step - want).length() > 0.15:
		_queen_act = ACT_WALK
	else:
		_queen_act = ACT_DIG if u > 0.18 and u < 0.72 else ACT_TEND


## No nurse is near a hatching cocoon: the nearest free one walks over by the tunnels (not straight through
## the soil); once it is close it is taken on as the helper.
func _call_nurse(a: Dictionary) -> void:
	var c = a.get("called")
	if c != null and (not _mates.has(c) or c.has("script") or c.has("deliver") or c.carry):
		a.erase("called")
		c = null
	if c == null:
		var best = null
		var bd := INF
		for m in _mates:
			if m.has("script") or m.has("deliver") or m.carry or not m.role in ["nurse", "idle", "attend", "wander"]:
				continue
			var d := Vector3(m.cell).distance_to(a.p)
			if d < bd:
				bd = d
				best = m
		if best == null:
			return
		var room := -1
		var rd := INF
		for i in _rooms.size():
			for sp in _rooms[i].spots:
				var d: float = (sp as Vector3).distance_to(a.p)
				if d < rd:
					rd = d
					room = i
		best.goal = room
		best.rest = 0
		best.wander = 0
		best.act_left = 0.0
		a.called = best
		return
	# taken on only once it is in the cocoon's chamber, a step or two away on the same floor (from farther off
	# the last stretch would be a straight line through the soil)
	var from: Vector3 = (c.vp as Vector3) if c.has("vp") else Vector3(c.cell)
	if from.distance_to(a.p) < 10.0 and _open_walk(from, a.p):
		a.erase("called")
		a.helpers.append(c)
		_hire(c, _beside(a.p, c, 1.6), a.p, ACT_TEND)


## Trophallaxis: `giver` (crop full of honeydew) and `taker` meet head to head. The taker drums the giver's
## head with its antennae; the giver opens its mandibles and holds a droplet out between them; the taker laps
## at it; a few seconds, then they part. (Lasius: food is shared mouth to mouth - docs/BIOLOGY.md; the
## antenna drumming as the begging signal is general ant behaviour, Hoelldobler & Wilson 1990.)
func _start_feed(giver: Dictionary, taker: Dictionary) -> bool:
	if giver.has("script") or taker.has("script") or not giver.has("vp") or not taker.has("vp"):
		return false
	if (taker.vu as Vector3).y < 0.85 or (giver.vu as Vector3).y < 0.85:
		return false                            # (one is up the chamber wall: they only touch antennae)
	var tp: Vector3 = taker.vp
	# where the giver stands: head to head with the taker, on open floor clear of the brood and of other
	# ants; tried all round the taker, starting from where the giver already is. None: they only antennate.
	# origin to origin: both mandible tips (MOUTH, x size) plus the droplet between them (~0.3 across)
	var gap: float = MOUTH.x * (float(giver.size) + float(taker.size)) + 0.28
	var d0: Vector3 = (giver.vp as Vector3) - tp
	d0.y = 0.0
	var base_ang := atan2(-d0.z, d0.x) if d0.length() > 0.01 else 0.0
	var spot := Vector3.INF
	if not _brood_cells.has(Vector3i(roundi(tp.x), roundi(tp.y - 0.45), roundi(tp.z))):
		for k in 12:
			var ang := base_ang + (k / 2) * 0.5 * (1.0 if k % 2 == 0 else -1.0)
			var q: Vector3 = tp + Basis(Vector3.UP, ang).x * gap
			var fl := _floor_cached(q)
			q.y = fl + 0.45
			var cell := Vector3i(roundi(q.x), roundi(fl), roundi(q.z))
			if absf(fl + 0.45 - tp.y) < 0.6 and _density_at(q) < 0.5 and not _brood_cells.has(cell) 					and not _brood_cells.has(cell + Vector3i(0, 1, 0)) and _brood_free(Vector3(q.x, fl, q.z), 0.5):
				spot = q
				break
	if spot == Vector3.INF or (giver.vp as Vector3).distance_to(spot) > 2.5:
		return false                            # (no room to meet head to head, or too far to step there)
	var a := {"k": "feed", "t": 0.0, "d": randf_range(6.0, 10.0) * _anim_k(), "giver": giver, "taker": taker, "spot": spot}
	giver.partner = taker
	taker.partner = giver
	giver.sep = Vector3.ZERO
	taker.sep = Vector3.ZERO
	_hire(taker, tp - Vector3(0, 0.45, 0) + (taker.vu as Vector3) * 0.0, giver.vp, ACT_ANTENNATE)
	taker.script.pos = tp
	taker.script.goal = tp
	_hire(giver, giver.vp - Vector3(0, 0.45, 0), tp, ACT_ANTENNATE)
	giver.script.pos = giver.vp
	giver.script.goal = giver.vp
	a.p = tp
	_anims.append(a)
	return true

## Whether there is ground under q near its height (a hole or a tunnel going down has none: _floor_cached then
## gives back the height it was asked at, which would pass for level floor).
func _floor_solid(q: Vector3) -> bool:
	var fl := _floor_cached(q)
	return _density_at(Vector3(q.x, fl - 0.25, q.z)) >= 0.5


## Whether an ant can walk straight from a to b over open floor (every half unit: floor found, no soil just
## above it, no step up or down of more than ~a body height).
func _open_walk(a: Vector3, b: Vector3) -> bool:
	var n := maxi(1, int(a.distance_to(b) / 0.5))
	var last := _floor_cached(a)
	for k in range(1, n + 1):
		var q := a.lerp(b, float(k) / n)
		var fl := _floor_cached(q)
		if absf(fl - last) > 0.9 or _density_at(Vector3(q.x, fl + 0.35, q.z)) >= 0.5 or _density_at(Vector3(q.x, fl + 0.9, q.z)) >= 0.5 or not _floor_solid(q):
			return false
		last = fl
	return true


## A helper's goal kept on the open chamber floor: on the floor under it, drawn back toward the cocoon
## `toward` if it would be inside the soil (else helpers walked into the chamber wall while pulling).
func _open_floor_goal(goal: Vector3, toward: Vector3, fallback: Vector3) -> Vector3:
	# where it was meant to stand, else the same place on the cocoon's other side - never closer in, which put
	# helpers on top of the cocoon - else where it already is
	# its whole body must be in the open: it faces the cocoon, so its gaster reaches back away from it
	var mirror := Vector3(2.0 * toward.x - goal.x, goal.y, 2.0 * toward.z - goal.z)
	var cands := [goal, mirror]
	var r := Vector2(goal.x - toward.x, goal.z - toward.z)
	for k in range(1, 6):
		for sgn in [1.0, -1.0]:
			var v := r.rotated(sgn * k * 0.5)
			cands.append(Vector3(toward.x + v.x, goal.y, toward.z + v.y))
	for g in cands:
		var fl := _floor_cached(g)
		var p := Vector3(g.x, fl + 0.45, g.z)
		var back: Vector3 = p - toward
		back.y = 0.0
		var tail: Vector3 = p + back.normalized() * 1.3 if back.length() > 0.01 else p
		var tfl := _floor_cached(tail)
		if _density_at(p) < 0.5 and _density_at(p + Vector3(0, 0.3, 0)) < 0.5 and absf(fl - toward.y) < 1.2 				and _density_at(Vector3(tail.x, tfl + 0.45, tail.z)) < 0.5 and absf(tfl - fl) < 0.9 				and _floor_solid(p) and _floor_solid(tail):
			return p
	return fallback


func _start_pupate(s: float) -> void:
	if _spots.larvae.is_empty():
		return
	_collect_freed_larvae()
	var p: Vector3 = _pile_xf(_spots.larvae, sim.larvae.size() + _pending("pupate"), 1.0).origin
	if not _freed.larvae.is_empty():
		p = _freed.larvae[-1]                # where that larva lay: it spins its cocoon there ...
	# ... or as near as there is room for a cocoon (it is much bigger than the larva: it lay in its neighbours)
	var yaw := randf() * TAU
	for off in _BORN_OFFS:
		var q: Vector3 = p + off
		q.y = _floor_cached(q)
		if _density_at(q + Vector3(0, 0.3, 0)) < 0.5 and _shape_lift(q, Basis(Vector3.UP, yaw), s, "pupae") <= 0.02 				and (_queen_mm.instance_count == 0 or _queen_keep(q) > 0.95 * s + 0.5):
			p = q
			break
	if not _freed.larvae.is_empty():
		_freed.larvae[-1] = p                # (the cocoon is then laid where it was spun)
	var a := {"k": "pupate", "t": 0.0, "d": 7.0 * _anim_k(), "p": p, "s": s, "helper": null, "carried": false, "yaw": yaw}
	var hs := _helpers(p, 1)
	if not hs.is_empty():
		a.helper = hs[0]
		_hire(a.helper, _beside(p, a.helper), p, ACT_TEND)
	_anims.append(a)


func _start_eclose(s: float) -> void:
	if _spots.pupae.is_empty():
		return
	var shown: int = sim.pupae.size() - _pending("pupate")
	var p: Vector3 = _pile_xf(_spots.pupae, maxi(0, shown + _pending("eclose")), s).origin
	var yaw := randf() * TAU
	var freed := _take_freed_pupa()
	if not freed.is_empty():
		# the very cocoon that hatched, where it lies (its pile entry is gone: drawn here from now on)
		p = freed[0]
		var bx: Vector3 = (freed[1] as Basis).x
		yaw = atan2(-bx.z, bx.x)
	else:
		p.y = _floor_cached(p)
	# the callow comes out at the head end and is drawn ~2.5 bodies along: that way must be open chamber floor
	# (a cocoon at the edge of the pile is turned round for it - its head end facing into the chamber)
	if _open_run(p, yaw, s) < _open_run(p, yaw + PI, s):
		yaw += PI
	var a := {"k": "eclose", "t": 0.0, "d": 22.0 * _anim_k(), "p": p, "s": s, "helpers": [], "yaw": yaw,
		"queen": false}
	# nurses right beside it step over; one from farther off is called and comes by the tunnels (_call_nurse) -
	# hired helpers walk straight to their place, which from farther away went through the soil
	for m in _helpers(p, 2, 3.5):
		a.helpers.append(m)
		_hire(m, _beside(p, m, 1.6 + 0.3 * a.helpers.size()), p, ACT_TEND)
	if a.helpers.is_empty() and sim.queen.alive and _spots.queen != Vector3.ZERO and _spots.queen.distance_to(p) < 8.0:
		a.queen = true           # a founding queen opens her first cocoons herself
	_anims.append(a)


## Where the parts of an eclosion are at progress u: the cocoon's head end, how far the callow has
## been pulled out, and the callow's own transform.
func _eclose_parts(a: Dictionary, u: float) -> Dictionary:
	var s: float = a.s
	var b := Basis(Vector3.UP, a.yaw)
	var bx: Vector3 = b.x
	var head: Vector3 = a.p + Vector3(0, 0.6 * s, 0) + bx * 1.3 * s
	# pulled out in tugs (each tug a little way, a pause while the helper takes a new grip), not drawn out
	# at an even speed
	var raw := clampf((u - 0.5) / 0.26, 0.0, 1.0) * 5.0
	var pull := (floorf(raw) + smoothstep(0.0, 0.55, raw - floorf(raw))) / 5.0 if raw < 5.0 else 1.0
	var roll := lerpf(1.3, 0.0, clampf((u - 0.85) / 0.13, 0.0, 1.0))
	var origin: Vector3 = a.p + bx * (pull * 2.5 * s - 0.4 * s)
	# on the floor where it is pulled to (a chamber floor curves), and up over any brood lying there - it is
	# drawn out over its neighbours, not through them
	var rise := 0.0
	if pull > 0.0:
		for k in [-0.8, 0.0, 0.8]:
			var q: Vector3 = origin + bx * k * s
			for o in _brood_near(q):
				var d := _brood_offset(q, o)
				var half: float = float(o[3] if o.size() > 3 else o[1])
				if Vector2(d.x, d.z).length() < half + 0.3 * s:
					rise = maxf(rise, float(o[0].y) + half - _floor_cached(q))
	var fl: float = _floor_cached(origin) if pull > 0.0 else float(a.p.y)
	origin.y = fl + 0.15 + 0.25 * roll + rise
	var callow := Transform3D((b * Basis(Vector3.RIGHT, roll)).scaled(Vector3.ONE * s), origin)
	return {"bx": bx, "head": head, "pull": pull, "callow": callow, "side": b.z}


func _step_anims(adt: float) -> void:
	_queen_act = -1
	_queen_turn_t = _queen_rest_turn
	_queen_step_t = Vector3.ZERO
	var walk := 3.5 / _anim_k()                   # voxels per second for hired helpers
	var fresh := []
	for m in _mates:
		if m.has("script"):
			var sp: Vector3 = (m.script.pos as Vector3).move_toward(m.script.goal, walk * adt)
			# on the floor under it all the way (a chamber floor curves: a straight line would dip into it)
			var fl := _floor_cached(sp)
			if absf(fl + 0.45 - sp.y) < 1.2:
				sp.y = fl + 0.45
			m.script.pos = sp
	# a queen on her own goes to her brood every so often (never in the middle of another moment)
	if sim.workers.is_empty() and _queen_mm.instance_count > 0 and adt > 0.0:
		_care_left -= adt
		if _care_left <= 0.0:
			_care_left = randf_range(12.0, 40.0)
			if _anims.filter(func(a): return a.k == "egg" or a.k == "care" or (a.k == "eclose" and a.queen)).is_empty():
				_start_care()
	for a in _anims:
		a.t += adt
		var u: float = a.t / a.d
		match a.k:
			"care":
				if not a.has("turn0"):
					a.turn0 = _queen_turn
					# (from where she stands, worked out afresh: her drawn transform may not be set yet)
					var to: Vector3 = (a.at as Vector3) - (_spots.queen + Vector3.UP * QUEEN_LIFT + _queen_step)
					a.turn1 = atan2(-to.z, to.x)
					a.step0 = _queen_step
				if u < 0.82:
					_queen_turn_t = a.turn1
					if not a.has("step"):
						# up to it, once she has turned to it: her mouthparts on the item (worked out from the
						# heading she turns to, not the one she is still turning from)
						var face := Transform3D(Basis(Vector3.UP, a.turn1).scaled(Vector3.ONE * QUEEN_SCALE), _spots.queen + Vector3.UP * QUEEN_LIFT + _queen_step)
						var reach: Vector3 = ((a.at as Vector3) - face * TIP_LICK) * Vector3(1, 0, 1)
						var stop: float = a.get("contact", 0.3)
						reach -= reach.normalized() * stop if reach.length() > stop else reach
						a.step = _queen_step + reach.limit_length(4.0)
						# not so far that her feet would stand in the chamber wall: step back until they are on its floor
						for k in 8:
							if _queen_feet_clear(face.origin + (a.step as Vector3) - _queen_step, a.turn1):
								break
							a.step = _queen_step + ((a.step as Vector3) - _queen_step) * 0.85
					var turned := absf(wrapf(a.turn1 - _queen_turn, -PI, PI)) < 0.15
					if turned:
						a.stepping = true
					_queen_step_t = a.step if a.get("stepping", false) else a.step0
					var there: bool = a.get("stepping", false) and (_queen_step - (a.step as Vector3)).length() < 0.1
					_queen_act = ACT_TEND if there else ACT_WALK
				else:
					_queen_turn_t = a.turn0
					_queen_step_t = a.step0
					_queen_act = ACT_WALK if u < 0.97 else ACT_REST
				if u >= 1.0:
					a.done = true
			"egg":
				var h = a.helper
				if h != null and not _mates.has(h):
					a.helper = null
					h = null
				if u < 0.22:
					_queen_act = ACT_LAY
				elif h == null:
					# a founding queen tends her eggs herself: she curls her gaster forward under her body and
					# takes the egg in her mandibles, turns (slowly) to face her egg packet, and once facing it
					# steps up and sets the egg down on it; then she turns back to her place
					_queen_egg_moment(a, u)
				elif u < 0.4:
					h.script.act = ACT_TEND
				elif u < 0.85:
					h.script.goal = a.pile + Vector3(0, 0.45, 0) + (Vector3(h.cell) - a.pile).normalized() * 1.0
					h.script.face = a.pile
					h.script.act = ACT_CARRY
				else:
					h.script.act = ACT_TEND
				if (h != null and u >= 1.0) or a.t > a.d * 1.8:
					a.done = true
					if h != null:
						_release(h)
			"pupate":
				var h = a.helper
				if h != null and not _mates.has(h):
					a.helper = null
					h = null
				if u >= 0.6 and not a.carried and h != null:
					# the nurse lifts the fresh cocoon and carries it up to the pupa chamber
					a.carried = true
					_release(h)
					h.deliver = a
					h.carry = true
					h.item = "cocoon"
					h.goal = _upper[0] if not _upper.is_empty() else _queen_room()
					h.rest = 0
					h.wander = 0
				if a.carried:
					if h == null or not h.has("deliver") or a.t > a.d + 25.0:
						a.done = true
						if h != null and h.has("deliver"):
							h.erase("deliver")
							h.carry = false
							h.item = ""
				elif u >= 1.0:
					a.done = true
					if h != null:
						_release(h)
			"eclose":
				u = _ecl_u(u)
				var hs: Array = a.helpers.filter(func(m): return _mates.has(m))
				a.helpers = hs
				if hs.is_empty() and not a.queen and float(a.get("wait", 0.0)) < 90.0:     # (a callow cannot get out alone)
					a.wait = float(a.get("wait", 0.0)) + adt
					_call_nurse(a)
					if a.has("called") and u > 0.15:
						a.t = 0.15 * a.d                  # the callow waits in its cocoon until a nurse comes to open it
						u = 0.15
				var ep := _eclose_parts(a, u)
				var callow_head: Vector3 = (ep.callow as Transform3D) * MOUTH
				for i in hs.size():
					var m: Dictionary = hs[i]
					var lift := Vector3(0, 0.45, 0)
					var before: Vector3 = m.script.goal
					if i == 0:
						# at the head end: bites through the silk, then backs away pulling the callow out
						m.script.goal = (ep.head as Vector3) + (ep.bx as Vector3) * (1.3 * a.s + ep.pull * 2.5 * a.s) + lift - Vector3(0, 0.3, 0)
						m.script.face = ep.head if u < 0.5 else callow_head
					else:
						# alongside: helps with the silk, then peels the pupal skin off the callow's body
						var along: float = -0.2 + ep.pull * 1.6
						m.script.goal = a.p + (ep.side as Vector3) * (1.7 * a.s) + (ep.bx as Vector3) * along * a.s + lift
						m.script.face = (ep.callow as Transform3D).origin if u > 0.5 else ep.head
					m.script.goal = _open_floor_goal(m.script.goal, a.p, before)
					if u < 0.18:
						m.script.act = ACT_TEND           # checking the cocoon
					elif u < 0.72:
						m.script.act = ACT_DIG            # biting the silk open / pulling
					elif u < 0.86 or i > 0:
						m.script.act = ACT_TEND           # peeling and licking the newcomer clean
					else:
						m.script.act = ACT_FEED           # the first meal, mouth to mouth
				if a.queen and sim.queen.alive:
					_queen_eclose(a, u, ep, callow_head)
				if u >= 1.0:
					a.done = true
					for m in hs:
						_release(m)
					var o: Vector3 = (ep.callow as Transform3D).origin
					_add_mate(Vector3i(roundi(o.x), roundi(a.p.y + 0.45), roundi(o.z)), "nurse", sim.tick, a.s)
					var newborn: Dictionary = _mates[-1]
					# it carries on from exactly where and how it stands (no jump as it joins the others)
					var cx: Transform3D = ep.callow
					newborn.vp = cx.origin
					var fx: Vector3 = cx.basis.x
					fx.y = 0.0
					newborn.vf = fx.normalized() if fx.length() > 0.01 else Vector3.RIGHT
					newborn.vu = Vector3.UP
					newborn.gait = randf() * TAU
					newborn.mv = 0.0
					newborn.xf = cx
					newborn.weak_until = sim.tick + int(sim.TPD * 0.25)   # unsteady for the first hours
					newborn.rest = randi_range(40, 90)
					if not hs.is_empty():
						# a helper carries the empty cocoon and the shed skin out to the refuse pile
						var h: Dictionary = hs[0]
						var shell := {"k": "shell", "t": 0.0, "d": 1e9, "helper": h}
						h.deliver = shell
						h.carry = true
						h.item = "shell"
						h.goal = -1
						h.rest = 0
						h.wander = 0
						fresh.append(shell)
					else:
						# nobody to take it yet: the empty cocoon lies where it was until a nurse comes for it
						# (brood and its leftovers move only when an ant carries them)
						fresh.append({"k": "husk", "t": 0.0, "d": 1e9, "p": a.p, "yaw": a.yaw, "s": a.s})
			"feed":
				var g = a.giver
				var r = a.taker
				if not _mates.has(g) or not _mates.has(r) or not g.has("script") or not r.has("script"):
					a.done = true
					for m in [g, r]:
						m.erase("partner")
						if _mates.has(m):
							_release(m)
				else:
					# the giver steps in until the two mouths meet (heads ~2 mandible-lengths apart, not overlapping)
					var rp: Vector3 = r.script.pos
					g.script.goal = a.spot
					g.script.face = rp
					r.script.face = g.script.pos
					var met: bool = (g.script.pos as Vector3).distance_to(g.script.goal) < 0.08
					if u < 0.12 or not met:
						g.script.act = ACT_ANTENNATE
						r.script.act = ACT_ANTENNATE
						if not met:
							a.t = minf(a.t, 0.12 * a.d)    # (the exchange starts once they are face to face)
					elif u < 0.9:
						g.script.act = ACT_FEED
						r.script.act = ACT_TAKE
					else:
						g.script.act = ACT_ANTENNATE
						r.script.act = ACT_ANTENNATE
					if u >= 1.0:
						a.done = true
						g.fed = false                       # its crop shared out
						g.erase("partner")
						r.erase("partner")
						_release(g)
						_release(r)
						r.cool = randf_range(8.0, 14.0)
						g.cool = randf_range(8.0, 14.0)
						a.p = rp
			"groom":
				# a nestmate licked clean (nest_duties._start_groom): the groomer steps up beside it, licks along its body
				# (the tending pose, its head turning from thorax to gaster), the other stands still
				var g = a.giver
				var r = a.taker
				if not _mates.has(g) or not _mates.has(r) or not g.has("script") or not r.has("script") or u >= 1.0:
					a.done = true
					for m in [g, r]:
						if _mates.has(m):
							m.erase("partner")
							_release(m)
							m.cool = randf_range(6.0, 12.0)
				else:
					g.script.goal = a.spot
					var along: Vector3 = (r.xf as Transform3D).basis.x * (0.35 * sin(a.t * 0.9)) if r.has("xf") else Vector3.ZERO
					g.script.face = (r.script.pos as Vector3) + along
					var met: bool = (g.script.pos as Vector3).distance_to(g.script.goal) < 0.08
					g.script.act = ACT_TEND if met else ACT_WALK
					r.script.act = ACT_REST
			"husk":
				var h = a.get("helper")
				if h != null and not _mates.has(h):
					a.erase("helper")
					h = null
				if h == null and int(a.t * 2.0) % 6 == 0:
					var hs2 := _helpers(a.p, 1, 9.0)
					if not hs2.is_empty():
						a.helper = hs2[0]
						_hire(a.helper, _beside(a.p, a.helper, 1.4), a.p, ACT_WALK)
				elif h != null and (h.script.pos as Vector3).distance_to(h.script.goal) < 0.2:
					_release(h)
					var shell := {"k": "shell", "t": 0.0, "d": 1e9, "helper": h}
					h.deliver = shell
					h.carry = true
					h.item = "shell"
					h.goal = -1
					h.rest = 0
					h.wander = 0
					fresh.append(shell)
					a.done = true
			"shell":
				var h = a.helper
				if not _mates.has(h) or not h.has("deliver") or a.t > 45.0:
					a.done = true
					if _mates.has(h) and h.has("deliver"):
						h.erase("deliver")
						h.carry = false
						h.item = ""
	_anims = _anims.filter(func(a): return not a.get("done", false))
	_anims.append_array(fresh)
	_queen_walk(adt)
	# she turns as a heavy queen does, stepping round at most ~1 rad/s and easing out at the end
	# her turning speeds up and slows down gradually (a heavy body: no snapping into or out of a turn), at
	# most ~0.75 rad/s, braking in time to stop facing where she means to
	var dturn := wrapf(_queen_turn_t - _queen_turn, -PI, PI)
	var want_v := signf(dturn) * minf(0.75, sqrt(2.0 * 1.0 * absf(dturn)))
	_queen_turn_v = move_toward(_queen_turn_v, want_v, 1.4 * adt)
	var dt_turn := _queen_turn_v * adt
	if absf(dt_turn) > absf(dturn) and signf(dt_turn) == signf(dturn):
		dt_turn = dturn
		_queen_turn_v = 0.0
	_queen_turn += dt_turn
	# and walks (slowly: ~1.5 units a second) where a moment needs her, back to her spot afterwards
	var to_step := _queen_step_t - _queen_step
	var want_w := to_step.normalized() * minf(1.2, sqrt(2.0 * 1.5 * to_step.length())) if to_step.length() > 0.001 else Vector3.ZERO
	_queen_step_v = _queen_step_v.move_toward(want_w, 2.0 * adt)       # (eases into and out of her steps too)
	var ds := _queen_step_v * adt
	if ds.length() > to_step.length():
		ds = to_step
		_queen_step_v = Vector3.ZERO
	_queen_step += ds


## The queen on her way to another chamber (nest_brood._path_to): slowly, heavy, turning to face her way before she
## steps on (QUEEN_WALK: ~4 mm a second at 1x, a fifth of a worker's pace) [inference: no measurement found]. Not while a lifecycle moment
## has her (laying, tending the first brood), and none starts while she walks (see _start_egg / _start_care).
const QUEEN_WALK := 2.5          # voxels a second


func _queen_walk(adt: float) -> void:
	if _queen_path.is_empty() or adt <= 0.0 or _queen_busy():
		return
	var to: Vector3 = _queen_path[0]
	var d: Vector3 = to - (_spots.queen as Vector3)
	if d.length() < 0.15:
		_spots.queen = to
		_queen_path.pop_front()
		if _queen_path.is_empty():
			_refresh_egg_spots()
		return
	# (her body is turned along her way in nest_brood._queen_pose)
	_spots.queen = (_spots.queen as Vector3) + d.normalized() * minf(d.length(), QUEEN_WALK * adt)


func _queen_busy() -> bool:
	for a in _anims:
		if a.k in ["egg", "care"] or (a.k == "eclose" and a.get("queen", false)):
			return true
	return false


## Ants still being born are drawn here: pulled head first out of the cocoon still wrapped in the
## pupal skin, legs folded; once the skin is peeled off it rolls upright and unfolds, then joins _mates.
func _emerging(xs: Array, cols: Array, cus: Array, young: Color) -> void:
	for a in _anims:
		if a.k != "eclose":
			continue
		var u: float = _ecl_u(a.t / a.d)
		if u < 0.5:
			continue
		var tr: Transform3D = _eclose_parts(a, u).callow
		if _visible(tr.origin):
			xs.append(tr)
			cols.append(young.lightened(0.3))
			cus.append(Color(0.0, ACT_EMERGE, maxf(0.0, (u - 0.82) * a.d), 0.0))


func _draw_anims() -> void:
	var drops_fx := []
	var eggs := []
	var larvae := []
	var silk := []
	var cocoons := []
	var soil := []
	for a in _anims:
		var u: float = a.t / a.d
		match a.k:
			"egg":
				var tip: Vector3 = _queen_xf * GASTER_TIP
				var p := tip
				var h = a.helper
				var sc := clampf(0.25 + u / 0.22 * 0.75, 0.25, 1.0)
				if h == null:
					# with her gaster curled forward the tip comes up under her head: the egg goes from one
					# to the other there, then rides in her mandibles until she lays it on the packet
					var take: Vector3 = _queen_xf * MOUTH_TAKE
					var carry: Vector3 = _queen_xf * MOUTH_CARRY
					var under: Vector3 = _queen_xf * TIP_CURLED
					if u > 0.22:
						p = tip.lerp(under, smoothstep(0.22, 0.27, u))
					if u > 0.28:
						p = under.lerp(take, smoothstep(0.28, 0.32, u))
					if u > 0.34:
						p = take.lerp(carry, smoothstep(0.34, 0.38, u))        # head comes up with it (pose easing)
					if a.has("down_at"):
						# set down exactly where it will lie in the packet (no jump when the moment ends)
						p = carry.lerp(a.pile, smoothstep(0.0, 1.2, a.t - a.down_at))
				elif u > 0.3 and h.has("xf"):
					var mouth: Vector3 = h.xf * MOUTH
					p = tip.lerp(mouth, clampf((u - 0.3) / 0.1, 0.0, 1.0))
					if u > 0.85:
						p = mouth.lerp(a.pile, clampf((u - 0.85) / 0.1, 0.0, 1.0))
				if _visible(p):
					eggs.append(Transform3D(Basis.from_scale(Vector3.ONE * sc), p))
			"pupate":
				if a.carried:
					continue                       # drawn in the nurse's mandibles
				var s: float = a.s
				if _visible(a.p):
					var lb := Basis(Vector3.UP, float(a.get("yaw", 0.0)) + a.t * 0.05).scaled(Vector3.ONE * s)
					if u < 0.62:
						# Lasius larvae need a covering of soil particles to spin against
						var shown := int(clampf(u / 0.25, 0.0, 1.0) * 8.0)
						var gone := clampf((u - 0.52) / 0.1, 0.0, 1.0)
						for g in shown:
							var ga: float = g * 0.785
							var gp: Vector3 = a.p + Vector3(cos(ga) * 0.7 * s, 0.35 + 0.35 * float(g % 2), sin(ga) * 0.7 * s)
							soil.append(Transform3D(Basis.from_scale(Vector3.ONE * (1.0 - gone)), gp))
					if u < 0.6:
						larvae.append(Transform3D(lb.scaled(Vector3(1.0, 1.0 - 0.15 * sin(a.t * 6.0), 1.0)), a.p + Vector3(0, 0.3, 0)))
						var cover := clampf(u / 0.6, 0.0, 1.0)
						silk.append([Transform3D(lb.scaled(Vector3.ONE * (0.55 + 0.5 * cover)), a.p + Vector3(0, 0.3, 0)), 0.15 + 0.7 * cover])
					else:
						cocoons.append(Transform3D(lb, a.p + Vector3(0, 0.3, 0)))
			"feed":
				var g = a.giver
				var r = a.taker
				if u > 0.12 and u < 0.9 and _mates.has(g) and _mates.has(r) and g.has("xf") and r.has("xf") and g.act == ACT_FEED:
					# one droplet held between the two mouths, shrinking as it is taken
					var mid: Vector3 = ((g.xf as Transform3D) * MOUTH + (r.xf as Transform3D) * MOUTH) * 0.5
					var left := 1.0 - (u - 0.12) / 0.78
					if _visible(mid):
						drops_fx.append(Transform3D(Basis.from_scale(Vector3.ONE * (0.35 + 0.45 * left) * (1.0 + 0.08 * sin(a.t * 6.0))), mid))
			"husk":
				if _visible(a.p):
					var hb := Basis(Vector3.UP, a.yaw)
					var hs3: Vector3 = Vector3(0.92, 0.78, 1.0) * a.s
					cocoons.append([Transform3D(hb.scaled(hs3), a.p + Vector3(0, 0.6 * a.s * 0.78, 0)), Color(0.95, 0.95, 0.95)])
			"eclose":
				if not _visible(a.p):
					continue
				u = _ecl_u(u)
				var ep := _eclose_parts(a, u)
				var wig := sin(a.t * 9.0) * 0.16 * clampf((u - 0.06) / 0.1, 0.0, 1.0) if u < 0.55 else 0.0
				var b := Basis(Vector3.UP, a.yaw) * Basis(Vector3.RIGHT, wig)
				var open := clampf((u - 0.45) / 0.1, 0.0, 1.0)
				# once empty the shell slumps a little; the silk is torn at the head end
				var sc: Vector3 = Vector3(1.0 - 0.08 * open, 1.0 - 0.22 * clampf((u - 0.7) / 0.2, 0.0, 1.0), 1.0) * a.s
				var tone := lerpf(1.0, 0.72, clampf(u / 0.2, 0.0, 1.0)) if u < 0.6 else lerpf(0.72, 0.95, clampf((u - 0.6) / 0.15, 0.0, 1.0))
				cocoons.append([Transform3D(b.scaled(sc), a.p + Vector3(0, 0.6 * a.s, 0)), Color(tone, tone, tone)])
				var peel := clampf((u - 0.72) / 0.13, 0.0, 1.0)
				if u > 0.5 and peel < 1.0:
					var skin := (ep.callow as Transform3D) * Transform3D(Basis.from_scale(Vector3(1.15, 0.75, 0.8)), Vector3(-0.15, 0.4, 0))
					silk.append([skin, 0.5 * (1.0 - peel)])
				if peel > 0.0:
					# the shed pupal skin, a crumpled pale scrap beside the cocoon
					silk.append([Transform3D(Basis.from_scale(Vector3(0.32, 0.18, 0.28) * a.s * peel), a.p + (ep.side as Vector3) * 0.9 * a.s + Vector3(0, 0.2, 0)), 0.85])
	_anim_drops = drops_fx
	_fill(_fx_egg_mm, eggs)
	_fill(_fx_larva_mm, larvae)
	_fx_cocoon_mm.instance_count = cocoons.size()
	for i in cocoons.size():
		var c = cocoons[i]
		_fx_cocoon_mm.set_instance_transform(i, c[0] if c is Array else c)
		_fx_cocoon_mm.set_instance_color(i, c[1] if c is Array else Color.WHITE)
	_fill(_fx_soil_mm, soil)
	_fx_silk_mm.instance_count = silk.size()
	for i in silk.size():
		_fx_silk_mm.set_instance_transform(i, silk[i][0])
		_fx_silk_mm.set_instance_color(i, Color(1, 1, 1, silk[i][1]))


func _add_mate(c: Vector3i, role: String, born: int, size: float) -> void:
	var goal := _random_room()
	match role:
		"nurse": goal = _brood_room(_larva_group)
		"attend": goal = _queen_room()
		"traffic": goal = -1
	_mates.append({"cell": c, "prev": c, "from": Vector3(c), "to": Vector3(c), "t": 1.0, "rest": randi_range(0, 30),
		"up": _up_at(c), "born": born, "role": role, "goal": goal,
		"wander": 0, "carry": false, "item": "", "size": size, "act": ACT_WALK, "act_left": 0.0, "cool": randf() * 4.0,
		"anim": randf() * 100.0, "fed": false})


## Callows are pale and darken over their first days as the cuticle hardens.
func _mate_color(m: Dictionary, body: Color, young: Color) -> Color:
	var days: float = float(sim.tick - int(m.get("born", -1000000000))) / sim.TPD
	return young.lerp(body, clampf(days / float(sim.sp["callow_days"]), 0.0, 1.0))
