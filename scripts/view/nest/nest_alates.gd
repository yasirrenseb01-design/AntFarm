extends RefCounted
## The winged gynes and males in the nest (PART 0.14 step 2): the simulation's sim.alates, drawn standing in a group
## on the floor of the nest's highest chamber - gyne larvae are reared in the topmost chamber [A1: 11 of 14 nests]
## and the alates gather near the surface before the flight [inference: keepers' reports of alates crowding the top
## chambers and the entrance on flight days; docs/biology/alates.md]. Not a layer of the nest view: made by
## nest_view.setup, updated each frame after the queen (nest_view.refresh). Only reads the simulation.
## Each has its own spot (worked out from its id: the same each time it is laid out) and, since v0.14.12 (the keeper,
## 2026-11-21: "they only stand still - give them more to do, as the ants in the game"), wanders a little about it now
## and then - a few steps to another spot on the same floor, clear of the others - and between walks grooms, feels
## about with its antennae, rests, and now and then buzzes its wings a moment (act 30) [keepers: alates restless in the
## nest before a flight, fanning their wings - inference; how often: chosen]. Their wings see-through (glass()).
## The workers do not walk round them yet (docs/roadmap/BACKLOG.md).
const WALK := 0.9                           # units a second walking (~1.4 mm/s: slower than a worker going somewhere)
const WANDER := 4.5                         # units from its own spot at most

const AntModel := preload("res://scripts/view/common/ant_model3d.gd")
const DRAW_MOST := {"g": 30, "m": 60}       # at most this many of each drawn (a colony of 2,000 makes ~140; chosen)
const MALE_SCALE := 1.07                    # a male ~4.5 mm against a 4.2 mm worker [A1] (sim/alates.gd SIZE)

var _mm := {}                               # "g" / "m" -> MultiMesh
var _sig := []
var _xf := {"g": [], "m": []}               # the transforms last laid out
var _clock := 0.0
var _ids := {"g": [], "m": []}              # the alates' ids, in the order drawn (pick)
var _lmm := {}                              # "g" / "m" -> the MultiMesh of their larvae (brood())
var _st := {"g": [], "m": []}               # each one drawn: {"home", "p", "yaw", "to", "wait", "gait", "spots", "n"}
# A gyne's larva as it pupates is ~7.3-7.8 mm long, a male's ~4.4-4.6, a worker's ~2.9-3.6 [A1]: drawn 2.0 and 1.35
# times a worker's larva at the same growth (nest_piles._update_brood: the size of those in the workers' pile too)


func setup(v, queen_mat: ShaderMaterial, ant_mat: ShaderMaterial, larva_mat: Material) -> void:
	for k in ["g", "m"]:
		_lmm[k] = v._multimesh(v._larva_mm.mesh, larva_mat, false)
	var gyne := AntModel.load_antmesh("res://assets/models/ants/gyne_hi.antmesh")
	var male := AntModel.load_antmesh("res://assets/models/ants/male_hi.antmesh")
	if gyne == null or male == null:
		return
	_mm["g"] = v._multimesh(gyne, glass(queen_mat), true)
	_mm["m"] = v._multimesh(male, glass(ant_mat), true)
	for k in _mm:
		_mm[k].use_custom_data = true


## A copy of an ant material drawing the wings truly see-through (shaders/ants/ant_alate.gdshader, step 11): the
## workers' and the queen's stay opaque - only the alates' few take the transparent pass.
static func glass(m: ShaderMaterial) -> ShaderMaterial:
	var g: ShaderMaterial = m.duplicate()
	g.shader = preload("res://shaders/ants/ant_alate.gdshader")
	return g


## Where they stand (the middle of the first group; Vector3.INF: none drawn) - the camera's "alates" (nest_camera.focus).
func middle() -> Vector3:
	var all: Array = _xf.g + _xf.m
	if all.is_empty():
		return Vector3.INF
	var first: Vector3 = all[0].origin               # (the first chamber's: those near the first laid out)
	var sum := Vector3.ZERO
	var n := 0
	for x: Transform3D in all:
		if x.origin.distance_to(first) < 8.0:
			sum += x.origin
			n += 1
	return sum / n


func update(v, delta: float) -> void:
	if _mm.is_empty():
		return
	var sim = v.sim
	_clock = fmod(_clock + (delta * minf(v.speed, 1.0) if v.speed > 0.0 else 0.0), 600.0)     # (paused: they pause too)
	var n := {"g": 0, "m": 0}
	_ids = {"g": [], "m": []}
	for al in sim.alates:
		if n[al.x] < DRAW_MOST[al.x]:
			_ids[al.x].append(int(al.id))
		n[al.x] = mini(n[al.x] + 1, DRAW_MOST[al.x])
	var rooms := _rooms_up(v)
	var sig := [n.g, n.m, rooms, v.nest.excavated / 8]
	if sig != _sig:
		_sig = sig
		_lay_out(v, rooms, n)
	var dt: float = delta * minf(v.speed, 1.0) if v.speed > 0.0 else 0.0      # (paused: still; slower below 1x)
	if Engine.get_process_frames() % 120 == 0 and OS.get_cmdline_user_args().has("--trace-alates"):
		_trace()
	for k in ["g", "m"]:
		var mm: MultiMesh = _mm[k]
		var sts: Array = _st[k]
		mm.instance_count = sts.size()
		var body := AntModel.body_linear(Color(0.07, 0.055, 0.047) if k == "g" else Color(0.085, 0.062, 0.05))
		var s: float = v.queen_scale if k == "g" else MALE_SCALE
		for i in sts.size():
			var st: Dictionary = sts[i]
			var t := _clock + float(i) * 7.3
			var act: int = v.ACT_REST
			var mv := 0.0
			if st.to == null:
				st.wait -= dt
				# standing: grooming or feeling about with the antennae, each on its own clock; now and then a buzz of the wings
				act = v.ACT_GROOM if fmod(t, 23.0) < 5.0 else (v.ACT_ANTENNATE if fmod(t, 11.0) < 4.0 else v.ACT_REST)
				if fmod(t + float(i % 5) * 3.0, 41.0) < 1.3:
					act = 30
				if st.wait <= 0.0:
					st.to = _next_spot(st, sts, s)
					st.wait = 3.0 + 8.0 * _h01(int(st.n) * 31 + i)
					st.n = int(st.n) + 1
			else:
				var to: Vector3 = st.to
				var d: Vector3 = to - st.p
				d.y = 0.0
				var step: float = WALK * s * dt
				if d.length() <= step:
					st.p = to
					st.to = null
				else:
					st.p += d.normalized() * step
					st.yaw = lerp_angle(float(st.yaw), atan2(-d.z, d.x), minf(1.0, 6.0 * dt))
					st.gait = fmod(float(st.gait) + step / maxf(0.01, 0.3 * s), TAU * 64.0)
					act = 0
					mv = 0.8
			var p: Vector3 = st.p
			var xf := Transform3D(Basis(Vector3.UP, float(st.yaw)).scaled(Vector3.ONE * s), Vector3(p.x, v._floor_cached(p + Vector3(0, 0.45, 0)), p.z))
			_xf[k][i] = xf
			mm.set_instance_transform(i, xf)
			mm.set_instance_color(i, body)
			mm.set_instance_custom_data(i, Color(float(st.gait), float(act), fmod(t, 600.0), AntModel.gait_w(mv, s)))


## (dev --trace-alates) how many are walking, standing, buzzing, and how far from their own spots - every 2 s.
func _trace() -> void:
	var walking := 0
	var far := 0.0
	var n := 0
	for k in _st:
		for st in _st[k]:
			walking += 1 if st.to != null else 0
			far += (st.p as Vector3).distance_to(st.home)
			n += 1
	if n > 0:
		print("alates drawn %d: walking %d, from their spots %.2f units on average" % [n, walking, far / n])


## Where it walks to next: a spot of its own floor, within WANDER of its own spot, clear of the others (where they
## stand or are going); null - it stays - when none is. Drawn from its own count (the same each time).
func _next_spot(st: Dictionary, all: Array, s: float) -> Variant:
	var spots: Array = st.spots
	if spots.is_empty():
		return null
	var gap := 2.4 * s
	for tries in 10:
		var q: Vector3 = spots[int(_h01(int(st.n) * 7 + tries) * spots.size()) % spots.size()]
		if q.distance_to(st.home) > WANDER * s or q.distance_to(st.p) < 0.8:
			continue
		var clear := true
		for o in all:
			if o != st and ((o.p as Vector3).distance_to(q) < gap or (o.to != null and (o.to as Vector3).distance_to(q) < gap)):
				clear = false
				break
		if clear:
			return q
	return null


static func _h01(n: int) -> float:
	var x := sin(float(n) * 12.9898 + 78.233) * 43758.5453
	return x - floorf(x)


## The chambers with a floor, highest first - those that are not the queen's nor the brood's before those that are
## (indices into v._rooms).
func _rooms_up(v) -> Array:
	var sim = v.sim
	var busy := [int(sim.brood_at.get("larvae", -2)), int(sim.brood_at.get("pupae", -2))]
	var free := func(r: Dictionary) -> bool: return not r.queen and not int(r.ch) in busy      # (r.queen: hers, nest_brood)
	var order: Array = range(v._rooms.size())
	order.sort_custom(func(a, b):
		var fa: bool = free.call(v._rooms[a])
		var fb: bool = free.call(v._rooms[b])
		return fa and not fb if fa != fb else v._rooms[a].y > v._rooms[b].y)
	return order


func _lay_out(v, rooms: Array, n: Dictionary) -> void:
	_xf = {"g": [], "m": []}
	_st = {"g": [], "m": []}
	var used: Array = []
	var ri := 0
	var order: Array = []
	var k := 0
	for kind in ["g", "m"]:
		# a spot clear of the others by about a body length (a gyne ~5 voxels long and her wings past her, a male ~3: the models x their scale)
		var gap := 4.6 if kind == "g" else 2.8
		var s: float = v.queen_scale if kind == "g" else MALE_SCALE
		for j in n[kind]:
			var at = null
			while at == null:
				if k >= order.size():
					# this chamber's floor is full: the next one down (from its middle out)
					if ri >= rooms.size():
						break
					order = _spots_out(v._rooms[rooms[ri]].spots)
					ri += 1
					k = 0
					continue
				var p: Vector3 = order[k]
				k += 1
				var ok := true
				for u in used:
					if p.distance_to(u.p) < (gap + u.gap) * 0.5:
						ok = false
						break
				if ok:
					at = p
			if at == null:
				break
			used.append({"p": at, "gap": gap})
			var yaw := fmod(float(j) * 2.399 + (0.7 if kind == "m" else 0.0), TAU)       # (each its own way, not at random)
			var floor_y: float = v._floor_cached(at + Vector3(0, 0.45, 0))
			_xf[kind].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(at.x, floor_y, at.z)))
			_st[kind].append({"home": at, "p": at, "yaw": yaw, "to": null, "wait": 3.0 + 9.0 * _h01(j * 13 + (5 if kind == "m" else 0)),
				"gait": 0.0, "spots": order, "n": j * 3})


## A floor's spots from its middle out.
func _spots_out(spots: Array) -> Array:
	if spots.is_empty():
		return []
	var mid := Vector3.ZERO
	for p in spots:
		mid += p
	mid /= spots.size()
	var order := spots.duplicate()
	order.sort_custom(func(a, b): return a.distance_squared_to(mid) < b.distance_squared_to(mid))
	return order


## The gynes' and the males' larvae (PART 0.14), each kind in the chamber the colony rears it in (sim brood_at "g" /
## "m": apart, the gynes' in the topmost - sim_warmth._sexual_rooms [A1]); laid out with the other brood
## (nest_view.refresh, after _update_brood: the workers' larvae pile leaves these out).
func brood(v) -> void:
	if _lmm.is_empty():
		return
	var sim = v.sim
	for k in ["g", "m"]:
		var mm: MultiMesh = _lmm[k]
		var ch := int(sim.brood_at.get(k, -1))
		if ch < 0 or not v._room_of.has(ch):
			mm.instance_count = 0
			continue
		var items: Array = sim.larvae.filter(func(l): return l.has("x") and l.x == k)
		var big := 2.0 if k == "g" else 1.35
		v._pile(mm, v._rooms[v._room_of[ch]].spots, items, 150, func(l): return (0.28 + l.p * 0.8) * big, [], 1 << 20,
			Callable(), "larvae", "_%s%d" % [k, ch])
		if OS.get_cmdline_user_args().has("--trace-alates"):
			print("alate larvae %s: %d in chamber %d, %d drawn, %d floor spots" % [k, items.size(), ch, mm.instance_count,
				v._rooms[v._room_of[ch]].spots.size()])


## The alates under the mouse for the nest's pick (nest_bodies.pick_ant): [screen gap, distance to the eye, info].
func pick(v, sp: Vector2, eye: Vector3) -> Array:
	var out: Array = []
	for k in ["g", "m"]:
		var xs: Array = _xf[k]
		var s: float = v.queen_scale if k == "g" else MALE_SCALE
		for i in mini(xs.size(), _ids[k].size()):
			var xf: Transform3D = xs[i]
			if not v._visible(xf.origin):
				continue
			var d: float = AntModel.screen_gap(v._cam, xf, sp)
			if d < 14.0:
				out.append([d, eye.distance_to(xf.origin) - 1.5 * s, {"kind": "alate", "id": _ids[k][i]}])      # (before a worker walking over it: BACKLOG)
	return out
