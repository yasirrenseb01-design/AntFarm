extends "res://scripts/view/nest/parts/nest_contact.gd"
## Nest view, layer 12 of 14 (PART EA3a round 2): the nestmates act out the duties the simulation gave their workers
## (sim/parts/sim_duties.gd) - feeding the larvae, attending the queen, giving honeydew to the nestmate it was paired with,
## cleaning itself or licking a nestmate, standing still, walking about. A duty round is half an hour of colony time,
## only a second or two here (the colony's clock runs ~1,400 times faster than an ant walks): so a drawn ant takes the
## duty its worker has, acts it out at an ant's pace (HOLD_S), and only then takes the one its worker has by then.
## Every act it is seen in is one its worker really had; not every duty is seen. (The tallies count them all.)

const HOLD_S := Vector2(10.0, 20.0)    # seconds (at 1×) a drawn ant keeps to a duty before taking its worker's latest
const MEET_D := 3.0                    # voxels: near enough to step in head to head and give the drop, or to lick
const NEAR_D := 7.0                    # voxels: near enough to walk straight up to it (farther: the tunnels to its room)
const GROOM_S := Vector2(6.0, 11.0)    # seconds licking a nestmate
const PAIR_S := 4.0                    # seconds to reach its partner before a nestmate nearer to hand stands in

var duty_stats := {}                   # dev (--live summary): drops given, nestmates licked


## The duty's role (overrides nest_rest._role_for): "nurse" at the brood, "attend" the queen, "giver" / "groomer" going
## to its partner, "wander", or "idle" (standing still, cleaning itself, waiting to be given a drop or licked).
func _role_for(m: Dictionary, w, attends: bool) -> String:
	if _walking_in(m, w):
		return "traffic"
	if float(m.get("wait_until", -1.0)) > _t:
		return "idle"                                 # (a nestmate is on its way to feed or lick it: it stands still)
	if float(m.get("vd_until", -1.0)) <= _t or not m.has("vd"):
		if int(w.duty) < 0:
			return super(m, w, attends)               # (no duty yet: just loaded, or in from outside since the round)
		_take_duty(m, w)
	match int(m.vd):
		Ant.D_QUEEN:
			return "attend"
		Ant.D_FEED_LARVAE:
			return "nurse"
		Ant.D_FEED_MATE:
			return "giver" if not (m.get("give_to", []) as Array).is_empty() else "idle"
		Ant.D_GROOM:
			return "groomer" if not (m.get("give_to", []) as Array).is_empty() else "idle"
		Ant.D_IDLE:
			return "wander"
	return "idle"


## The worker's duty now, kept for HOLD_S (shorter at a faster speed: the duties come round faster too).
func _take_duty(m: Dictionary, w) -> void:
	m.vd = int(w.duty)
	m.vd_until = _t + randf_range(HOLD_S.x, HOLD_S.y) / maxf(1.0, speed)
	m.give_to = []
	if m.vd == Ant.D_FEED_MATE:
		for o in sim.workers:                         # the nestmates it gives a drop to this round, in turn
			if o.duty == Ant.D_FED and o.partner == w.id:
				m.give_to.append(o.id)
	elif m.vd == Ant.D_GROOM and w.partner > 0:
		m.give_to = [w.partner]                       # the nestmate it licks clean


func _mate_of(wid: int):
	for o in _mates:
		if int(o.get("wid", -1)) == wid:
			return o
	return null


## The givers and the groomers: to the room of the one they were paired with, straight up to it once near, then the
## drop given head to head (nest_lifecycle._start_feed) or the licking (_start_groom). Called every frame.
func _duty_pairs() -> void:
	for m in _mates:
		if not (m.role == "giver" or m.role == "groomer") or m.has("script") or m.carry or not m.has("vp"):
			continue
		var list: Array = m.get("give_to", [])
		var t = _mate_of(int(list[0])) if not list.is_empty() else null
		if t == null:
			duty_stats["gone"] = int(duty_stats.get("gone", 0)) + 1
			list.pop_front()                          # (gone out or died: the next one)
			if list.is_empty():
				m.vd_until = _t                       # (done: its worker's next duty)
			continue
		if t.has("script") or t.carry or not t.has("vp"):
			continue                                  # (busy for now - in a moment it is free; the duty ends anyway)
		var d: float = (m.vp as Vector3).distance_to(t.vp)
		if int(m.get("pair_for", -1)) != int(list[0]):
			m.pair_for = int(list[0])
			m.pair_t = _t
		if d >= MEET_D and (_t - float(m.pair_t) > PAIR_S or d > 15.0):
			# its partner is out of reach in a crowded nest: the drop goes to (or it licks) a nestmate resting near it
			# instead - the one doing it is still the one the simulation chose (the tallies are its)
			var near = _stand_in(m)
			if near != null:
				list[0] = int(near.wid)
				m.pair_for = int(near.wid)
				m.pair_t = _t
				continue
		# the one it is going to waits for it, as its worker does (the simulation set it to be fed / to stand still)
		# (stopped only where it stands still already: one on its way through a tunnel goes on to its resting spot first -
		# stopped mid-tunnel, it rested in the wall)
		t.wait_until = _t + 4.0
		if t.from == t.to and (t.get("settle", []) as Array).is_empty():
			t.rest = maxi(int(t.rest), 40)
			t.wander = 0
		if d < MEET_D:
			var ok: bool = _start_feed(m, t) if m.role == "giver" else _start_groom(m, t)
			if ok:
				duty_stats[m.role] = int(duty_stats.get(m.role, 0)) + 1
				list.pop_front()
				t.rest = maxi(int(t.rest), 20)
			else:
				duty_stats["no room"] = int(duty_stats.get("no room", 0)) + 1
				_close_in(m, t)                   # (not quite there: a step along the tunnels nearer, as below)
		elif d < 15.0:
			_close_in(m, t)
		else:
			var r := _room_near(Vector3(t.cell))
			m.rest = 0
			if r >= 0 and m.goal != r:
				m.goal = r
				m.wander = 0


## Along the tunnels to a free spot beside its partner (nest_rest._settle, scored by how near it is to the partner),
## once a second at most; there it waits (not on to the middle of the chamber it was heading for).
func _close_in(m: Dictionary, t: Dictionary) -> void:
	if (m.get("settle", []) as Array).is_empty() and float(m.get("next_try", 0.0)) <= _t:
		m.near_to = t.vp
		m.next_try = _t + 1.0
		_settle(m)
		m.rest = 30


## Hired walkers that were only going up to a partner: once there, back on their own legs (the meeting starts next frame).
func _end_approaches() -> void:
	for m in _mates:
		if m.has("script") and m.script.get("approach", false):
			if (m.script.pos as Vector3).distance_to(m.script.goal) < 0.1:
				_release(m)
				m.rest = 0


## The nearest nestmate standing still on the floor within reach (not busy, not going to another): or null.
func _stand_in(m: Dictionary):
	var best = null
	var bd := 6.0
	for o in _mates:
		if is_same(o, m) or o.role != "idle" or o.has("script") or o.carry or not o.has("vp") or (o.vu as Vector3).y < 0.85:
			continue
		if not (o.get("settle", []) as Array).is_empty() or o.from != o.to:
			continue
		var d := (o.vp as Vector3).distance_to(m.vp)
		if d < bd:
			bd = d
			best = o
	return best


func _room_near(p: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in _rooms.size():
		var d := Vector3(_rooms[i].cell).distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## A nestmate licking another clean: standing beside it, head to its body (the tending pose, as at the brood), the other
## standing still. Like the feeding: false if there is no room beside it.
func _start_groom(g: Dictionary, r: Dictionary) -> bool:
	# (both on a floor: a groomer up a wall had no floor under it on its way, see nest_lifecycle._step_anims)
	if g.has("script") or r.has("script") or not g.has("vp") or not r.has("vp") or (r.vu as Vector3).y < 0.85 or (g.vu as Vector3).y < 0.85:
		return false
	var rp: Vector3 = r.vp
	# its middle about half a body length plus the other's width from the other's middle: its head at the other's side
	var reach := 1.9 * (float(g.size) + float(r.size)) * 0.5
	# at its side (the side nearer the groomer): coming at its head or its gaster end, its body is half a length long there
	var spot := _beside(rp, g, reach)
	if r.has("xf"):
		var side: Vector3 = (r.xf as Transform3D).basis.z
		side.y = 0.0
		if side.length() > 0.01:
			side = side.normalized()
			if side.dot((g.vp as Vector3) - rp) < 0.0:
				side = -side
			spot = rp + side * reach
	spot.y = _floor_cached(spot) + 0.45
	# only a step or two from where it is, on open floor all the way (it walks there straight: a longer way went through
	# the tunnel walls)
	var mid := ((g.vp as Vector3) + spot) * 0.5
	if (g.vp as Vector3).distance_to(spot) > 1.8 or _density_at(spot) > 0.35 or _density_at(mid) > 0.35 or absf(spot.y - rp.y) > 0.6 or not _open_walk(g.vp, spot):
		return false
	var a := {"k": "groom", "t": 0.0, "d": randf_range(GROOM_S.x, GROOM_S.y) * _anim_k(), "giver": g, "taker": r, "spot": spot, "p": rp}
	g.partner = r
	r.partner = g
	_hire(r, rp - Vector3(0, 0.45, 0), rp + (r.xf as Transform3D).basis.x if r.has("xf") else rp, ACT_REST)
	r.script.pos = rp
	r.script.goal = rp
	_hire(g, g.vp - Vector3(0, 0.45, 0), rp, ACT_WALK)
	g.script.pos = g.vp
	g.script.goal = spot
	_anims.append(a)
	return true


## Dev (--duty-log): where each giver and groomer is with its partner.
func duty_trace() -> String:
	var out := []
	for m in _mates:
		if m.role in ["giver", "groomer"] and m.has("vp"):
			var list: Array = m.get("give_to", [])
			var t = _mate_of(int(list[0])) if not list.is_empty() else null
			if t == null:
				out.append("%s#%d no partner drawn (%s)" % [m.role, int(m.wid), str(list)])
				continue
			out.append("%s#%d d%.1f settle%d goal%d rest%d moving%s | partner#%d script%s role %s up%.2f cell_room%d" % [m.role, int(m.wid),
				(m.vp as Vector3).distance_to(t.vp), (m.get("settle", []) as Array).size(), int(m.goal), int(m.rest), str(m.from != m.to),
				int(t.wid), str(t.has("script")), t.role, (t.vu as Vector3).y if t.has("vu") else -9.0, _room_near(Vector3(t.cell))])
	return "
".join(out)

