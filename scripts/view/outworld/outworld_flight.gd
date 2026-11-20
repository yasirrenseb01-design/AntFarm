extends RefCounted
## The nuptial flight seen on the wild plot (PART 0.14 step 3): when the colony's alates fly (sim stats "flight", made
## by sim/alates.gd on a warm, calm afternoon), they come out of the entrance, run about on the ground a little, climb
## up a stalk and take off - wings swung out and beating (shader act 30) - rising and drifting away downwind.
## [A9 keepers, BWARS: alates swarm out of the nest and climb grass stems and walls to take off; workers rush about
## the entrance] - the timings and heights chosen. A view of its own: drawn from the colony's numbers, its own random
## draws (not the simulation's), nothing saved. Made by outworld_view.setup, updated each frame.
## At most DRAW_MOST of each drawn (a colony of 2,000 sends ~400); the rest are counted, not shown.
## Also (step 4) the mated queens come down on the plot (sim.ground_queens, sim/wild_queens.gd): wingless, walking about,
## then digging in - the keeper clicks one to catch her into a founding tube (ui/ant_tip.gd -> outworld_view.catch_queen).

const AntModel := preload("res://scripts/view/common/ant_model3d.gd")
const DRAW_MOST := {"g": 12, "m": 40}
const MALE_SCALE := 1.07                    # x a worker (sim/alates.gd SIZE)
const ACT_FLY := 30                         # (shaders/ants/ant_core.gdshaderinc: wings out and beating)
const ACT_GROOM := 4
const STALK := 1.0                          # units (~3 mm) of plant over the ground: something to climb
const ACT_ANTENNATE := 3

var _mm := {}
var _seen_day := -1
var _actors: Array = []                     # {k, t, t0, from, to, stalk, up, drift, yaw, s}
var _clock := 0.0
var _qmm: MultiMesh = null                  # the queens on the ground
var _qxf := {}                              # their id -> transform drawn (picking)
var _qgait := {}


func setup(v, ant_mat: ShaderMaterial, queen_scale: float, queen_limbs: Vector3) -> void:
	var gyne := AntModel.load_antmesh("res://assets/models/ants/gyne_hi.antmesh")
	var male := AntModel.load_antmesh("res://assets/models/ants/male_hi.antmesh")
	if gyne == null or male == null:
		return
	var qm: ShaderMaterial = ant_mat.duplicate()
	qm.set_shader_parameter("limb_gain", queen_limbs)
	qm.set_shader_parameter("gaster_back", 0.5)              # (a queen's longer thorax: tools/blender/ant/body.py GBACK)
	_mm["g"] = v._multimesh(gyne, qm, true, true)
	_mm["m"] = v._multimesh(male, ant_mat, true, true)
	for k in _mm:
		_mm[k].use_custom_data = true
	_mm["qs"] = queen_scale
	_qmm = v._multimesh(AntModel.make(0.0, true, true, v.sim.sp.look), qm, true, true)
	var f = v.sim.stats.get("flight", {})
	_seen_day = int(f.get("day", -1)) if f is Dictionary else -1      # (a flight before this view opened: not shown again)


## Whether any are flying now (the HUD / camera may follow it).
func busy() -> bool:
	return not _actors.is_empty()


## Where the flight is (the nest's entrance while it goes on; Vector3.INF: none).
func where(v) -> Vector3:
	return Vector3(v._nest_xz.x, 0.0, v._nest_xz.y) if busy() else Vector3.INF


func update(v, delta: float) -> void:
	if _mm.is_empty():
		return
	var sim = v.sim
	_ground_queens(v, delta)
	var f = sim.stats.get("flight", {})
	if f is Dictionary and int(f.get("day", -1)) != _seen_day:
		_seen_day = int(f.get("day", -1))
		if _seen_day == sim.day():
			_start(v, int(f.get("g", 0)), int(f.get("m", 0)))
	if _actors.is_empty():
		for k in ["g", "m"]:
			_mm[k].instance_count = 0
		return
	# (in real time, whatever the game's speed: a flight takes ~half a minute to watch)
	_clock = fmod(_clock + delta, 600.0)
	var xs := {"g": [], "m": []}
	var cs := {"g": [], "m": []}
	for i in range(_actors.size() - 1, -1, -1):
		var a: Dictionary = _actors[i]
		a.t += delta
		var t: float = a.t - a.t0
		if t < 0.0:
			continue
		var s: float = a.s
		var p: Vector3
		var basis: Basis
		var act := ACT_ANTENNATE
		var gait := 0.0
		var mv := 0.0
		if t < a.walk:
			# out of the entrance and across the ground to the foot of a stalk
			var u: float = t / a.walk
			var q: Vector2 = a.from.lerp(a.to, u)
			p = Vector3(q.x, v.ground_top(q.x, q.y), q.y)
			var dir: Vector2 = (a.to - a.from).normalized()
			basis = _facing(Vector3(dir.x, 0, dir.y), Vector3.UP)
			act = 0
			mv = 0.9
			gait = fmod(t * 9.0, TAU * 64.0)
		elif t < a.walk + a.climb:
			# up the stalk, head up
			var u: float = (t - a.walk) / a.climb
			var g: float = v.ground_h(a.to.x, a.to.y)       # (from the soil up the stem to its top: ground_top)
			p = Vector3(a.to.x, lerpf(g, v.ground_top(a.to.x, a.to.y) + a.up, u), a.to.y)
			basis = _facing(Vector3.UP, -Vector3(cos(a.yaw), 0, sin(a.yaw)))
			act = 0
			mv = 0.8
			gait = fmod(t * 9.0, TAU * 64.0)
		elif t < a.walk + a.climb + a.wait:
			# at the top (or on the ground, nothing to climb near): a moment, antennae waving, then the wings open
			var g: float = v.ground_top(a.to.x, a.to.y)
			p = Vector3(a.to.x, g + (a.up if a.stalk else 0.0), a.to.y)
			basis = _facing(Vector3.UP, -Vector3(cos(a.yaw), 0, sin(a.yaw))) if a.stalk else _facing(Vector3(cos(a.yaw), 0, sin(a.yaw)), Vector3.UP)
			act = ACT_FLY if t > a.walk + a.climb + a.wait * 0.6 else ACT_ANTENNATE
		else:
			# away: rising, drifting downwind, the body level
			var u: float = t - a.walk - a.climb - a.wait
			var g: float = v.ground_top(a.to.x, a.to.y)
			var d: Vector2 = a.drift * u
			p = Vector3(a.to.x + d.x, g + (a.up if a.stalk else 0.0) + u * a.rise + 0.4 * sin(u * 3.0 + a.yaw), a.to.y + d.y)
			var head := Vector3(a.drift.x, a.rise * 0.6, a.drift.y).normalized()
			basis = _facing(head, Vector3.UP)
			act = ACT_FLY
			if u > 9.0:
				_actors.remove_at(i)
				continue
		var xf := Transform3D(basis.scaled(Vector3.ONE * s), p)
		xs[a.k].append(xf)
		cs[a.k].append(Color(gait, float(act), fmod(_clock + a.yaw * 10.0, 600.0), AntModel.gait_w(mv, s / v.ANT_SCALE)))
	var body := {"g": AntModel.body_linear(Color(0.07, 0.055, 0.047)), "m": AntModel.body_linear(Color(0.085, 0.062, 0.05))}
	for k in ["g", "m"]:
		var mm: MultiMesh = _mm[k]
		mm.instance_count = xs[k].size()
		for j in xs[k].size():
			mm.set_instance_transform(j, xs[k][j])
			mm.set_instance_color(j, body[k])
			mm.set_instance_custom_data(j, cs[k][j])


## A basis with the body's forward along `fwd` and its back toward `up`.
func _facing(fwd: Vector3, up: Vector3) -> Basis:
	var f := fwd.normalized()
	var u := (up - f * f.dot(up)).normalized()
	if u.length() < 0.5:
		u = Vector3.UP if absf(f.y) < 0.9 else Vector3.FORWARD
		u = (u - f * f.dot(u)).normalized()
	return Basis(f, u, f.cross(u))


func _start(v, g: int, m: int) -> void:
	var sim = v.sim
	var home: Vector2 = v._nest_xz
	var wind: float = sim.wind()
	var wdir := Vector2.from_angle(randf() * TAU)        # (the plot has no wind direction yet: one for this flight)
	var n := {"g": mini(g, DRAW_MOST.g), "m": mini(m, DRAW_MOST.m)}
	var k_all: int = n.g + n.m
	var idx := 0
	for k in ["g", "m"]:
		for j in n[k]:
			# the tallest of a few spots round the entrance (~2-7 cm out): up a grass stem or a plant to its top; with
			# nothing standing there, a short hop up off the ground (the plot's prop heights: outworld_view._props_h)
			var ang := randf() * TAU
			var to: Vector2 = home + Vector2.from_angle(ang) * randf_range(6.0, 16.0)
			var tall := 0.0
			for tries in 10:
				var a2 := randf() * TAU
				var q: Vector2 = home + Vector2.from_angle(a2) * randf_range(6.0, 40.0)
				var h: float = v._props_h.at(q.x, q.y) if v._props_h.w > 0 else 0.0
				if h > tall:
					tall = h
					to = q
					ang = a2
			var s: float = v.ANT_SCALE * (_mm.qs if k == "g" else MALE_SCALE)
			_actors.append({"k": k, "t": 0.0, "t0": float(idx) / maxf(1.0, k_all) * 18.0 + randf() * 1.5,
				"from": home, "to": to, "walk": randf_range(2.0, 4.5) * (1.0 if tall < STALK else 1.6),
				"climb": randf_range(1.2, 2.4) if tall >= STALK else 0.0, "stalk": tall >= STALK,
				"wait": randf_range(0.8, 2.5), "up": randf_range(0.3, 1.0), "rise": randf_range(2.5, 4.5),
				"drift": wdir * (1.0 + wind * 0.8) + Vector2.from_angle(randf() * TAU) * 1.2, "yaw": ang, "s": s})
			idx += 1


## The mated queens on the ground: walking (where sim/wild_queens.gd says she is), then still, head down, digging.
func _ground_queens(v, delta: float) -> void:
	var sim = v.sim
	var qs: Array = sim.ground_queens
	_qmm.instance_count = qs.size()
	var keep := {}
	for i in qs.size():
		var q: Dictionary = qs[i]
		var p2: Vector2 = sim.WildQueens.pos_of(sim, q) * v.U
		var walking: bool = sim.WildQueens.walking(sim, q)
		var was: Transform3D = _qxf.get(q.id, Transform3D())
		var dir := Vector2(p2.x - was.origin.x, p2.y - was.origin.z)
		var f := Vector3(dir.x, 0, dir.y).normalized() if dir.length() > 0.001 and _qxf.has(q.id) else 			(was.basis.x.normalized() if _qxf.has(q.id) else Vector3(cos(q.a), 0, sin(q.a)))
		var s: float = v.ANT_SCALE * _mm.qs * float(q.w) ** (1.0 / 3.0)          # (a heavier queen a little bigger)
		var up := Vector3.UP
		var xf := Transform3D(_facing(f, up).scaled(Vector3.ONE * s), Vector3(p2.x, v.ground_top(p2.x, p2.y), p2.y))
		var g: float = _qgait.get(q.id, 0.0) + (dir.length() / maxf(0.01, 0.3 * s) if walking else 0.0)
		_qgait[q.id] = fmod(g, TAU * 64.0)
		keep[q.id] = xf
		_qmm.set_instance_transform(i, xf)
		_qmm.set_instance_color(i, AntModel.body_linear(Color(0.07, 0.055, 0.047)))
		_qmm.set_instance_custom_data(i, Color(_qgait[q.id], 0.0 if walking else 2.0, fmod(_clock + i * 3.1, 600.0),
			AntModel.gait_w(0.8 if walking else 0.0, s / v.ANT_SCALE)))
	_qxf = keep
	for id in _qgait.keys():
		if not keep.has(id):
			_qgait.erase(id)


## The queen on the ground under the mouse (outworld_creatures.pick_ant), or {}.
func pick(v, sp: Vector2) -> Dictionary:
	var best := {}
	var best_d := 18.0
	for id in _qxf:
		var d: float = AntModel.screen_gap(v._cam, _qxf[id], sp)
		if d < best_d:
			best_d = d
			best = {"kind": "ground_queen", "id": int(id)}
	return best
