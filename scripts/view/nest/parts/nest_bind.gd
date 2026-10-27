extends "res://scripts/view/nest/parts/nest_rest.gd"
## Nest view, layer 9 of 14 (split from parts/nest_rest.gd in v0.11.44): the one drawn nestmate per real worker
## inside - bound to it by id (`wid`), its role from the worker's, walked in from the entrance when it has just come
## in and up to the entrance when it goes out (from near the way out: _leave_from_near).


## The nestmates drawn in the nest are the real workers inside, one each, so each keeps its own size, age and
## job: nurses (and the queen's attendants) by the brood and the queen, the reserve resting about, a forager
## just back walking in from the entrance, one going out walking up to it first. Diggers are drawn at the dig
## face (_dig_vis), and workers still climbing out of their cocoons by their eclosion.
var io := {}                     # dev (--io): ants in and out of the nest as the nest view drew them, counted
var _io_was := {}                 # (dev --io: worker id -> in the nest at the last bind)

func _bind_workers() -> void:
	var all := {}
	var inside := []
	for w in sim.workers:
		all[w.id] = w
	_pair_diggers(all)
	for w in sim.workers:
		if w.state == Ant.IN_NEST and not _dug_by.has(w.id):      # (a worker at the dig face is drawn as its digger)
			inside.append(w)
	inside.sort_custom(func(a, b): return a.age < b.age or (a.age == b.age and a.id < b.id))
	if not _io_was.is_empty():
		for w in sim.workers:
			var now_in: bool = w.state == Ant.IN_NEST
			if _io_was.has(w.id) and _io_was[w.id] != now_in:
				var k := "sim_in" if now_in else "sim_out"
				io[k] = int(io.get(k, 0)) + 1
	_io_was.clear()
	for w in sim.workers:
		_io_was[w.id] = w.state == Ant.IN_NEST
	var by_id := {}
	for i in range(_pending("eclose"), inside.size()):      # the youngest are still being born
		if by_id.size() >= 250:
			break
		by_id[inside[i].id] = inside[i]
	# the queen's retinue: the nurses most drawn to her
	var attend := {}
	if sim.queen.alive:
		var nurses: Array = by_id.values().filter(func(w): return w.task == Ant.TASK_NURSE)
		nurses.sort_custom(func(a, b): return a.threshold(Ant.TH_ATTEND) < b.threshold(Ant.TH_ATTEND))
		for i in mini(mini(3, by_id.size() / 6), nurses.size()):
			attend[nurses[i].id] = true
	_leave_from_near(all, by_id)
	var keep := []
	var free := []
	var bound := {}
	for m in _mates:
		var wid: int = m.get("wid", -1)
		if m.get("gone", false):
			io.out_reached = int(io.get("out_reached", 0)) + 1
			continue                                   # walked out through the entrance
		if wid >= 0 and by_id.has(wid) and not m.get("leaving", false):
			bound[wid] = m
			keep.append(m)
		elif wid >= 0 and not m.has("script") and not m.has("deliver"):
			var w = all.get(wid)
			if (w == null or w.dead) and not m.get("leaving", false):
				_lay_corpse(m)                         # died in the nest: it lies where it fell until it is carried out
				continue
			if w != null and w.state != Ant.IN_NEST and not m.get("leaving", false):
				# it has gone out: walk it up to the entrance first
				m.leaving = true
				m.left_at = _t
				m.role = "traffic"
				m.goal = -1
				m.rest = 0
				m.wander = 0
				m.settle = []
				m.carry = false
				m.item = ""
				io.out_started = int(io.get("out_started", 0)) + 1
				if _undertaker.has(w.id):
					# an undertaker: to the body first, then out with it
					m.fetch = _undertaker[w.id]
					m.goal = _corpse_key(m.fetch)
					_undertaker.erase(w.id)
				elif w.carry == Ant.CORPSE:
					m.carry = true                     # (no body seen in the nest: it goes out with one all the same)
					m.item = "corpse"
					io.undertaker_unseen = int(io.get("undertaker_unseen", 0)) + 1
			if m.get("leaving", false) and _still_leaving(m):
				keep.append(m)
			elif m.get("leaving", false):
				io.out_dropped = int(io.get("out_dropped", 0)) + 1      # (never got to the entrance: gone mid-tunnel)
				io.out_dropped_d = float(io.get("out_dropped_d", 0.0)) + (m.to as Vector3).distance_to(Vector3(nest.entrance))
		elif wid < 0:
			free.append(m)                             # a newborn from an eclosion: takes the youngest worker
		else:
			keep.append(m)                             # busy in a life-cycle moment: let it finish
	for w in by_id.values():
		if bound.has(w.id):
			continue
		var m: Dictionary
		if not free.is_empty():
			m = free.pop_front()
		else:
			var walking_in: bool = sim.tick - int(w.came_in) < int(sim.TPD * 0.05)
			var c := _entrance_cell() if walking_in else _any_spot()
			var from_dig := false
			if _back_at.has(w.id):
				# back from the dig face: its body goes on from where its digger was
				var bc: Vector3i = _back_at[w.id]
				_back_at.erase(w.id)
				if _walkable(bc):
					c = bc
					walking_in = false
					from_dig = true
					io.dig_back = int(io.get("dig_back", 0)) + 1
			if c.x < 0:
				continue
			_add_mate(c, "traffic" if walking_in else "idle", -1000000000, w.size)
			var k := "in_entrance" if walking_in else ("in_anywhere_recent" if sim.tick - int(w.came_in) < int(sim.TPD * 0.5) else "placed")
			io[k] = int(io.get(k, 0)) + 1
			m = _mates.pop_back()
			m.fed = walking_in and w.brought == Ant.SUGAR       # back from the aphids: its crop is full
			if not walking_in and not from_dig:
				_settle(m)
		m.wid = w.id
		bound[w.id] = m
		keep.append(m)
	_mates = keep
	# each one's job follows its worker's (unless it is in the middle of carrying or a life-cycle moment)
	for wid in bound:
		var m: Dictionary = bound[wid]
		var w = by_id[wid]
		m.size = w.size
		m.born = sim.tick - int(w.age * sim.TPD)
		if m.carry or m.has("script") or m.has("deliver") or m.role == "carry":
			continue
		var want := "todig" if _dig_pending(wid) else _role_for(m, w, attend.has(wid))
		if want != m.role:
			m.role = want
			m.goal = -2 if want == "todig" else (_queen_room() if want == "attend" else (_brood_room(_larva_group) if want == "nurse" else _random_room()))
			m.wander = 0
			m.rest = mini(m.rest, 5)
			if want == "wander":
				m.wander = 0                            # (walking about the nest: chamber to chamber along the tunnels)
	_meet_diggers(bound, all)
	for wid in _out_from:
		var w = all.get(wid)
		var c: Vector3i = _out_from[wid]
		if w != null and _walkable(c):
			_add_mate(c, "traffic", -1000000000, w.size)
			var m: Dictionary = _mates[-1]
			m.wid = wid
			m.leaving = true
			m.left_at = _t
			m.goal = -1
			io.dig_out = int(io.get("dig_out", 0)) + 1
			if w.carry == Ant.CORPSE:
				var ci := _free_corpse(m)        # (sent to take a body out: to it first)
				if ci >= 0:
					_corpses_by_id(ci).taken = true
					_corpse_field(ci)
					m.fetch = ci
					m.goal = _corpse_key(ci)
				else:
					m.carry = true
					m.item = "corpse"
	_out_from.clear()
	_bound_once = true


## What a drawn nestmate does, from its worker: queen's retinue, nurse at the brood, walking in, or resting. (The nest
## view's duties layer, nest_duties.gd, gives it the duty the simulation set instead - this is what is left without one.)
func _role_for(m: Dictionary, w, attends: bool) -> String:
	if attends:
		return "attend"
	if (w.task == Ant.TASK_NURSE or w.task == Ant.TASK_CALLOW) and w.threshold(Ant.TH_ATTEND) < 1.15:
		return "nurse"                             # (the rest of the nurses rest nearby, off the brood pile)
	if _walking_in(m, w):
		return "traffic"                           # still walking in from the entrance
	return "idle"


func _walking_in(m: Dictionary, w) -> bool:
	return m.role == "traffic" and m.goal != -1 and sim.tick - int(w.came_in) < int(sim.TPD * 0.05)


## A worker the simulation has just sent out leaves from near the entrance: the inside nestmate drawn nearest the way
## out (much nearer than its own body, of much the same size and age) takes it over, and its own body takes that
## nestmate's worker. Each worker's body used to walk out from wherever it was - from the deepest chamber of a big
## nest that took longer than the 25 s allowed, and half of them vanished in the tunnels (the keeper's colony, 1 min:
## 22 out, 8 reached the entrance, 9 gone mid-tunnel ~36 cells from it). An ant the keeper has selected, follows or
## named keeps its own body.
const LEAVE_NEAR := 6             # cells from the entrance: near enough to walk out as it is
const SWAP_SIZE := 0.04           # the most two bodies that change workers may differ in size

func _leave_from_near(all: Dictionary, by_id: Dictionary) -> void:
	var ef: Dictionary = _fields.get(-1, {})
	if ef.is_empty():
		return
	for m in _mates:
		var wid: int = m.get("wid", -1)
		if wid < 0 or not _free_body(m):
			continue
		var w = all.get(wid)
		if w == null or w.state == Ant.IN_NEST:
			continue
		var f := ef
		if w.carry == Ant.CORPSE:
			# an undertaker: the body nearest the dead nestmate goes for it (the nearest one lying there not yet taken)
			var ci := _free_corpse(m)
			if ci >= 0:
				_undertaker[wid] = ci
				_corpses_by_id(ci).taken = true
				f = _corpse_field(ci)
		if _own_body(w):
			continue
		var dm: int = f.get(m.cell, 1 << 20)
		if dm <= LEAVE_NEAR:
			continue
		var best = null
		var bd: int = dm - LEAVE_NEAR
		for c in _mates:
			var cw: int = c.get("wid", -1)
			if cw < 0 or not by_id.has(cw) or not _free_body(c) or _own_body(by_id[cw]):
				continue
			var o = by_id[cw]
			if absf(float(o.size) - float(w.size)) > SWAP_SIZE or (minf(o.age, w.age) < float(sim.sp["callow_days"]) and absf(o.age - w.age) > 1.0):
				continue                     # (a callow's pale body is not a dark one's)
			var d: int = f.get(c.cell, 1 << 20)
			if d < bd:
				best = c
				bd = d
		if best != null:
			io.swapped = int(io.get("swapped", 0)) + 1
			m.wid = best.wid
			best.wid = wid


func _free_body(m: Dictionary) -> bool:
	return not (m.get("leaving", false) or m.get("gone", false) or m.has("script") or m.has("deliver") or m.carry
		or m.role == "carry" or m.role == "todig")


func _own_body(w) -> bool:
	return (sel_kind == "worker" and sel_id == w.id) or follow_wid == w.id or String(w.name) != ""


## A body walking out keeps going while it still gets nearer the entrance (or the clock is stopped); one that has not
## for 8 s is held up for good, and goes (it was 25 s in all, however far it had to walk).
func _still_leaving(m: Dictionary) -> bool:
	if speed <= 0.0:
		return true
	var d: int = _field_of(m.goal).get(m.cell, 1 << 20)       # (the entrance, or first the body it goes to fetch)
	if m.get("out_goal", -1) != m.goal:
		m.out_goal = m.goal
		m.out_best = 1 << 20                     # (a new way: progress counted afresh)
	if d < int(m.get("out_best", 1 << 20)):
		m.out_best = d
		m.out_best_t = _t
	return _t - float(m.get("out_best_t", m.get("left_at", _t))) < 8.0


# ---------------------------------------------------------------- diggers: the worker's own body (v0.11.45)

## The simulation keeps who digs (workers with TASK_DIG) apart from the diggers walking the tunnels (nest.diggers), and
## the view paired them by order of id: the bodies changed workers whenever the crew changed (274 times in 120 days of a
## young colony), a worker set to dig vanished where it stood and a digger of no size of its own appeared mid-chamber.
## Now each digger keeps its worker (_dig_wid); a worker newly set to dig walks its own body to the dig face (role
## "todig") and takes the digger over where they meet (or after DIG_WAIT s); taken off, its body goes on from where its
## digger was (_back_at). A digger with no worker is not drawn.
const DIG_MEET := 3.0             # cells between the worker's body and its digger to take it over
const DIG_WAIT := 30.0            # seconds (view time) before it takes it over wherever they are
var _dig_wid := {}                # digger id -> worker id
var _dig_live := {}               # digger id -> true: the worker's body is the digger now
var _dig_since := {}              # digger id -> _t paired
var _dug_by := {}                 # worker id -> digger id, for the live ones (drawn as the digger, not as a nestmate)
var _back_at := {}                # worker id -> the cell its digger was on when it stopped digging
var _xfields := {}                # more distance fields: -2 the dig face, _corpse_key(id) a body to fetch
var _xfield_at := {}              # key -> the cell its field was made from
var _out_from := {}               # worker id -> the cell its digger was on when it was sent out
var _bound_once := false          # the nestmates have been bound once since the view was set up


func _field_of(key: int) -> Dictionary:
	return _fields.get(key, _xfields.get(key, {}))


func _pair_diggers(all: Dictionary) -> void:
	var ds := {}
	for d in nest.diggers:
		ds[d.id] = d
	for id in _dig_wid.keys():
		var w = all.get(_dig_wid[id])
		var keep: bool = ds.has(id) and w != null and not w.dead and w.state == Ant.IN_NEST \
			and (w.task == Ant.TASK_DIG or ds[id].carry)          # (taken off: it still carries its last pellet out)
		if keep:
			continue
		var v: Dictionary = _dig_vis.get(id, {})
		if _dig_live.has(id) and v.has("xf"):
			if w == null or w.dead:
				_corpses_add(v.xf)                                 # died at the dig face
			elif w.state != Ant.IN_NEST:
				_out_from[w.id] = Vector3i((v.to as Vector3).round())    # sent out: walks up from the dig face
			else:
				_back_at[w.id] = Vector3i((v.to as Vector3).round())
		_dig_wid.erase(id)
		_dig_live.erase(id)
		_dig_since.erase(id)
	var taken := {}
	for id in _dig_wid:
		taken[_dig_wid[id]] = true
	var free_ws: Array = sim.workers.filter(func(x): return x.task == Ant.TASK_DIG and x.state == Ant.IN_NEST and not x.dead and not taken.has(x.id))
	free_ws.sort_custom(func(a, b): return a.id < b.id)
	var ids: Array = ds.keys()
	ids.sort()
	for id in ids:
		if free_ws.is_empty():
			break
		if _dig_wid.has(id):
			continue
		var w = free_ws.pop_front()
		_dig_wid[id] = w.id
		_dig_since[id] = _t
		# the nest view just opened (no bodies yet): it is the digger straight away; else its body (or the one it gets
		# walking in from the entrance) walks to the dig face first
		if not _bound_once:
			_dig_live[id] = true
	_dug_by.clear()
	for id in _dig_live:
		_dug_by[_dig_wid[id]] = id
	# the face they make for
	var face: Vector3i = nest.work_at if nest.work_at.x >= 0 else (Vector3i(nest.diggers[0].cell) if not nest.diggers.is_empty() else Vector3i(-1, 0, 0))
	if face.x >= 0 and _xfield_at.get(-2, Vector3i(-9, -9, -9)) != face and _dig_wid.size() > _dig_live.size():
		_xfields[-2] = _field_from(face)
		_xfield_at[-2] = face


func _dig_pending(wid: int) -> bool:
	for id in _dig_wid:
		if _dig_wid[id] == wid:
			return not _dig_live.has(id)
	return false


## A worker walking to the dig face takes its digger over once they are close (or it has waited long enough): the
## digger is drawn on from where the body was, and the body goes.
func _meet_diggers(bound: Dictionary, all: Dictionary) -> void:
	var by_dig := {}
	for d in nest.diggers:
		by_dig[d.id] = d
	var drop := {}
	for id in _dig_wid:
		if _dig_live.has(id) or not by_dig.has(id):
			continue
		var wid: int = _dig_wid[id]
		var m = bound.get(wid)
		var cell := Vector3(call("_on_soil", by_dig[id].cell))      # (nest_mates)
		var late: bool = _t - float(_dig_since.get(id, _t)) > DIG_WAIT
		var here: Vector3 = (m.from as Vector3).lerp(m.to, clampf(float(m.t), 0.0, 1.0)) if m != null else cell
		if m == null or here.distance_to(cell) <= DIG_MEET or late:
			var k := "dig_late" if late else "dig_meet"
			io[k] = int(io.get(k, 0)) + 1
			_dig_live[id] = true
			_dig_vis[id] = {"from": here, "to": cell, "t": 0.0, "up": _up_at(Vector3i(cell)), "still": 0.0,
				"anim": float(m.anim) if m != null else 0.0}
			if m != null:
				drop[m] = true
	if not drop.is_empty():
		_mates = _mates.filter(func(x): return not drop.has(x))
	_dug_by.clear()
	for id in _dig_live:
		_dug_by[_dig_wid[id]] = id
	# a live digger's body is its worker's: size and age
	for id in _dig_live:
		var v: Dictionary = _dig_vis.get(id, {})
		var w = all.get(int(_dig_wid[id]))
		if not v.is_empty() and w != null:
			v.size = w.size
			v.born = sim.tick - int(w.age * sim.TPD)


func _worker(wid: int):
	for w in sim.workers:
		if w.id == wid:
			return w
	return null


## The worker a digger body is (null: none - it is not drawn).
func digger_worker(id: int):
	return _worker(int(_dig_wid[id])) if _dig_live.has(id) else null


# ---------------------------------------------------------------- the dead in the nest (v0.11.45)

## A nestmate that dies in the nest lies there on its back, legs curled, until an undertaker carries it out (the
## simulation counts it, corpses_inside, and sends one out with it - before, the body just vanished and the undertaker
## left empty-handed while outside it came out carrying one). Bodies no one comes for go after CORPSE_KEEP s.
const CORPSE_KEEP := 120.0
const CORPSE_CARRY := Transform3D(Basis(Vector3(0.9, 0, 0), Vector3(0, -0.9, 0), Vector3(0, 0, -0.9)), Vector3(2.3, 0.95, 0))      # (turned over, 0.9 big: as in the outworld)
var _corpses := []                # {"id", "xf", "cell", "t", "taken"}
var _corpse_n := 0
var _undertaker := {}             # worker id -> the body it goes for
var _corpse_mm: MultiMesh


func _corpse_key(id: int) -> int:
	return -10 - id


func _lay_corpse(m: Dictionary) -> void:
	if m.has("xf"):
		_corpses_add(m.xf)


func _corpses_add(xf: Transform3D) -> void:
	# on its back: turned over along its length, resting on its upper side
	var tr := Transform3D(xf.basis * Basis(Vector3.RIGHT, PI), xf.origin + xf.basis.y * 0.5)
	_corpse_n += 1
	_corpses.append({"id": _corpse_n, "xf": tr, "cell": Vector3i(xf.origin.round()), "t": _t, "taken": false})
	io.corpse_laid = int(io.get("corpse_laid", 0)) + 1


func _corpses_by_id(id: int) -> Dictionary:
	for c in _corpses:
		if c.id == id:
			return c
	return {}


## The nearest body no undertaker has come for yet, to a body at m (-1: none).
func _free_corpse(m: Dictionary) -> int:
	var best := -1
	var bd := INF
	for c in _corpses:
		if not c.taken:
			var d := Vector3(c.cell).distance_to(m.to)
			if d < bd:
				bd = d
				best = c.id
	return best


func _corpse_field(id: int) -> Dictionary:
	var key := _corpse_key(id)
	if not _xfields.has(key):
		var c := _corpses_by_id(id)
		var at: Vector3i = c.cell
		for k in 4:
			if _walkable(at):
				break
			at.y -= 1
		_xfields[key] = _field_from(at)
	return _xfields[key]


## An undertaker that has reached the body picks it up and goes on out with it.
func _pick_corpse(m: Dictionary) -> void:
	var id: int = m.fetch
	m.erase("fetch")
	_xfields.erase(_corpse_key(id))
	_corpses = _corpses.filter(func(c): return c.id != id)
	m.carry = true
	m.item = "corpse"
	m.goal = -1
	io.corpse_taken = int(io.get("corpse_taken", 0)) + 1


## The bodies lying in the nest and those being carried out (carried: the carriers' transforms), drawn with the ant
## model in its dead pose.
func _draw_corpses(carried: Array) -> void:
	for c in _corpses:
		if not c.taken and _t - float(c.t) > CORPSE_KEEP:
			io.corpse_expired = int(io.get("corpse_expired", 0)) + 1
	_corpses = _corpses.filter(func(c): return c.taken or _t - float(c.t) <= CORPSE_KEEP)
	if _corpses.is_empty() and carried.is_empty() and _corpse_mm == null:
		return
	if _corpse_mm == null:
		var mat: ShaderMaterial = _ant_shader_mat.duplicate()
		mat.set_shader_parameter("feet_on", false)
		_corpse_mm = _multimesh(_ant_meshes.lo, mat, true)
		_corpse_mm.use_custom_data = true
	var xs := []
	for c in _corpses:
		if _shown(c.xf):
			xs.append(c.xf)
	for tr in carried:
		xs.append(tr * CORPSE_CARRY)
	if not carried.is_empty():
		io.corpse_carried_frames = int(io.get("corpse_carried_frames", 0)) + 1
	_corpse_mm.instance_count = xs.size()
	var dead: Color = AntModel.body_linear(sim.sp["body_color"]).lerp(Color(0.05, 0.035, 0.025), 0.4)     # (a little duller than the living)
	for i in xs.size():
		_corpse_mm.set_instance_transform(i, xs[i])
		_corpse_mm.set_instance_color(i, dead)
		_corpse_mm.set_instance_custom_data(i, Color(0, 11, 0, 0))
