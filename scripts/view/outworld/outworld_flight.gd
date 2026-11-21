extends RefCounted
## The nuptial flight seen on the wild plot (PART 0.14 step 3): when the colony's alates fly (sim stats "flight", made
## by sim/alates.gd on a warm, calm afternoon), they come out of the entrance, run about on the ground a little, climb
## up a stalk and take off - wings swung out and beating (shader act 30) - rising and drifting away downwind.
## [A9 keepers, BWARS: alates swarm out of the nest and climb grass stems and walls to take off; workers rush about
## the entrance] - the timings and heights chosen. A view of its own: drawn from the colony's numbers, its own random
## draws (not the simulation's), nothing saved. Made by outworld_view.setup, updated each frame.
## At most DRAW_MOST of each drawn (a colony of 2,000 sends ~400); the rest are counted, not shown.
## Also (step 4) the mated queens come down on the plot (sim.ground_queens, sim/wild_queens.gd): walking about, then
## digging in - the keeper clicks one to catch her into a founding tube (ui/ant_tip.gd -> outworld_view.catch_queen).
## Step 11 (the keeper, 2026-11-21, v0.14.11): seen coming down (wings beating, FALL_S), walking a while with her wings
## on, then shedding them - left lying where she was - and on without [A8: a mated queen sheds her wings and founds
## at once; keepers: the queens seen on paths after a flight are mostly wingless already - not at the first touch of
## the ground, each in her own time: SHED_H chosen]. The flight and the queens play at the game's pace below 1x and
## stop when it is paused (they ran on in real time); calm, the alates scatter every way, in wind mostly downwind.

const AntModel := preload("res://scripts/view/common/ant_model3d.gd")
const Glass := preload("res://scripts/view/nest/nest_alates.gd")
const DRAW_MOST := {"g": 12, "m": 40}
const MALE_SCALE := 1.07                    # x a worker (sim/alates.gd SIZE)
const ACT_FLY := 30                         # (shaders/ants/ant_core.gdshaderinc: wings out and beating)
const ACT_GROOM := 4
const STALK := 1.0                          # units (~3 mm) of plant over the ground: something to climb
const ACT_ANTENNATE := 3
const FALL_S := 4.5                         # s (at 1x) a landing queen is seen coming down
const FALL_H := 28.0                        # units (~4 cm) above the ground she is first seen
const SHED_H := Vector2(0.3, 1.4)           # game hours after landing she sheds her wings (each her own) [chosen]

var _mm := {}
var _seen_day := -1
var _actors: Array = []                     # {k, t, t0, from, to, stalk, up, drift, yaw, s}
var _clock := 0.0
var _qmm: MultiMesh = null                  # the queens on the ground
var _qxf := {}                              # their id -> transform drawn (picking)
var _qgait := {}
var _qwmm: MultiMesh = null                 # the queens on the ground (or coming down) still winged
var _wingmm := {}                           # "l" / "r": her shed wings (each side's pair, as they lay on her), on the ground
var _qst := {}                              # queen id -> {"fall": s left coming down, "shed": where she shed them, "yaw"}


func setup(v, ant_mat: ShaderMaterial, queen_scale: float, queen_limbs: Vector3) -> void:
	var gyne := AntModel.load_antmesh("res://assets/models/ants/gyne_hi.antmesh")
	var male := AntModel.load_antmesh("res://assets/models/ants/male_hi.antmesh")
	if gyne == null or male == null:
		return
	var qm: ShaderMaterial = ant_mat.duplicate()
	qm.set_shader_parameter("limb_gain", queen_limbs)
	qm.set_shader_parameter("gaster_back", 0.5)              # (a queen's longer thorax: tools/blender/ant/body.py GBACK)
	var qg: ShaderMaterial = Glass.glass(qm)                 # (their wings see-through: nest_alates.glass, step 11)
	_mm["g"] = v._multimesh(gyne, qg, true, true)
	_mm["m"] = v._multimesh(male, Glass.glass(ant_mat), true, true)
	for k in _mm:
		_mm[k].use_custom_data = true
	_mm["qs"] = queen_scale
	_qmm = v._multimesh(AntModel.make(0.0, true, true, v.sim.sp.look), qm, true, true)
	_qwmm = v._multimesh(gyne, qg, true, true)
	# her shed wings: the gyne model's own (part 12), each side's pair as one piece laid flat (v0.14.11: plain ovals
	# until then - "not like real ones")
	var wmat := ShaderMaterial.new()
	wmat.shader = preload("res://shaders/ants/wing_shed.gdshader")
	var halves := _wing_halves(gyne)
	for side in halves:
		_wingmm[side] = v._multimesh(halves[side], wmat, false)
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
	delta = delta * minf(v.speed, 1.0) if v.speed > 0.0 else 0.0     # (paused: still; below 1x, slower - as the enemies' poses)
	# (the wings' clock runs whether or not a flight is on: a queen coming down beat no wings until v0.14.11 - "lowered
	# on a rope", the keeper)
	_clock = fmod(_clock + delta, 600.0)
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
	# (each one's way off: calm, any way at all; the windier, the more of them downwind - v0.14.11, all went one way)
	var spread: float = lerpf(PI, 0.45, clampf(wind / 6.0, 0.0, 1.0))
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
				"drift": wdir.rotated(randf_range(-spread, spread)) * (1.0 + wind * 0.8) + Vector2.from_angle(randf() * TAU) * 0.5,
				"yaw": ang, "s": s})
			idx += 1


## The mated queens on the ground: coming down (wings beating), walking with her wings on, shedding them, walking on
## (where sim/wild_queens.gd says she is), then still, head down, digging. Her wings lie where she shed them.
func _ground_queens(v, delta: float) -> void:
	var sim = v.sim
	var qs: Array = sim.ground_queens
	var keep := {}
	var plain := []
	var winged := []
	var wings := []
	for i in qs.size():
		var q: Dictionary = qs[i]
		var hours: float = float(int(sim.tick) - int(q.t0)) / sim.TPD * 24.0
		if not _qst.has(q.id):
			# (just landed: seen coming down; one already on the plot when the view opened is simply there)
			_qst[q.id] = {"fall": FALL_S if hours < 0.25 else 0.0, "yaw": float(q.a)}
		var st: Dictionary = _qst[q.id]
		st.fall = maxf(0.0, float(st.fall) - delta)
		var p2: Vector2 = sim.WildQueens.pos_of(sim, q) * v.U
		var walking: bool = sim.WildQueens.walking(sim, q)
		var shed_at: float = minf(lerpf(SHED_H.x, SHED_H.y, _h01(int(q.id))), float(q.walk) * 0.7)
		var has_wings: bool = hours < shed_at or float(st.fall) > 0.0
		var was: Transform3D = _qxf.get(q.id, Transform3D())
		var dir := Vector2(p2.x - was.origin.x, p2.y - was.origin.z)
		var f := Vector3(cos(q.a), 0, sin(q.a))
		if _qxf.has(q.id):
			f = Vector3(dir.x, 0, dir.y).normalized() if dir.length() > 0.001 else was.basis.x.normalized()
		var s: float = v.ANT_SCALE * _mm.qs * float(q.w) ** (1.0 / 3.0)          # (a heavier queen a little bigger)
		var ground: float = v.ground_top(p2.x, p2.y)
		var k: float = float(st.fall) / FALL_S                                      # 1 high up .. 0 landed
		var at := Vector3(p2.x, ground, p2.y)
		var face := _facing(f, Vector3.UP)
		if k > 0.0:
			# coming down in a widening-to-narrowing spiral, bobbing with her wingbeats, nose a little up; slowing as
			# she nears the ground (v0.14.11: a straight drop "on a rope")
			var turn: float = float(st.yaw) + (1.0 - k) * TAU * 1.3
			var r: float = 9.0 * k * (0.6 + 0.4 * sin(k * PI))
			var h: float = FALL_H * pow(k, 1.6) + 0.35 * sin(_clock * 28.0) * smoothstep(0.0, 0.3, k)
			at += Vector3(cos(turn), 0, sin(turn)) * r + Vector3(0, h, 0)
			var head := Vector3(-sin(turn), 0, cos(turn))                          # (along the spiral)
			face = _facing(head + Vector3(0, 0.25 * k, 0), Vector3.UP).rotated(head, 0.25 * sin(_clock * 3.1) * k)
		var xf := Transform3D(face.scaled(Vector3.ONE * s), at)
		var g: float = _qgait.get(q.id, 0.0) + (dir.length() / maxf(0.01, 0.3 * s) if walking and k <= 0.0 else 0.0)
		_qgait[q.id] = fmod(g, TAU * 64.0)
		keep[q.id] = xf
		var act: float = float(ACT_FLY) if k > 0.0 else (0.0 if walking else 2.0)
		var cd := Color(_qgait[q.id], act, fmod(_clock + i * 3.1, 600.0), AntModel.gait_w(0.8 if walking and k <= 0.0 else 0.0, s / v.ANT_SCALE))
		if has_wings:
			winged.append([xf, cd])
		else:
			plain.append([xf, cd])
			if not st.has("shed"):
				st["shed"] = Vector3(p2.x, ground + 0.02, p2.y)          # (where she was when they came off)
				st["s"] = s
			wings.append(st)
	for pair in [[_qmm, plain], [_qwmm, winged]]:
		var mm: MultiMesh = pair[0]
		var list: Array = pair[1]
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j][0])
			mm.set_instance_color(j, AntModel.body_linear(Color(0.07, 0.055, 0.047)))
			mm.set_instance_custom_data(j, list[j][1])
	# her wings where she shed them, lying flat, the two sides a little apart (each side's pair as it lay on her back)
	for side in _wingmm:
		var mm: MultiMesh = _wingmm[side]
		mm.instance_count = wings.size()
		for j in wings.size():
			var at0: Vector3 = wings[j].shed
			var y0: float = float(wings[j].yaw) + (0.5 if side == "l" else -0.4)
			var sc: float = float(wings[j].s)
			var off := Vector3(cos(y0 + 1.7), 0, sin(y0 + 1.7)) * (0.8 if side == "l" else -0.8) * sc
			mm.set_instance_transform(j, Transform3D(Basis(Vector3.UP, -y0).scaled(Vector3.ONE * sc), at0 + off))
	_qxf = keep
	for id in _qgait.keys():
		if not keep.has(id):
			_qgait.erase(id)
	for id in _qst.keys():
		if not keep.has(id):
			_qst.erase(id)


## The gyne model's wings (part 12: vertex colour alpha x 16), cut out as two pieces - her left pair and her right -
## each laid flat about its own middle, at the ground (y 0) - the shed wings' meshes.
static func _wing_halves(gyne: ArrayMesh) -> Dictionary:
	var a := gyne.surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var cs: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var out := {}
	for side in ["l", "r"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var tris := []
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for t in range(0, idx.size(), 3):
			var ok := true
			for q in 3:
				var c: Color = cs[idx[t + q]]
				if absf(c.a * 16.0 - 12.0) > 0.4 or ((vs[idx[t + q]].z < 0.0) != (side == "l")):
					ok = false
			if ok:
				tris.append(t)
				for q in 3:
					lo = lo.min(vs[idx[t + q]])
					hi = hi.max(vs[idx[t + q]])
		# (folded on her they stand at a slant, roof-like: turned so their own plane lies on the soil, they show their whole
		# shape - squashed flat instead they were thin slivers)
		var nsum := Vector3.ZERO
		for t in tris:
			var e := (vs[idx[t + 1]] - vs[idx[t]]).cross(vs[idx[t + 2]] - vs[idx[t]])
			nsum += e if e.y >= 0.0 else -e
		var flat := Basis(Quaternion(nsum.normalized(), Vector3.UP)) if nsum.length() > 0.0 else Basis.IDENTITY
		var mid := (lo + hi) * 0.5
		var low := INF
		for t in tris:
			for q in 3:
				low = minf(low, (flat * (vs[idx[t + q]] - mid)).y)
		for t in tris:
			for q in 3:
				var vi: int = idx[t + q]
				st.set_normal(flat * ns[vi])
				st.set_color(cs[vi])
				st.set_uv(uvs[vi] if uvs.size() > vi else Vector2.ZERO)
				var p: Vector3 = flat * (vs[vi] - mid)
				st.add_vertex(Vector3(p.x, (p.y - low) * 0.3, p.z))     # (the fore wing over the hind, a hair apart)
		out[side] = st.commit()
	return out


static func _h01(n: int) -> float:
	var x := sin(float(n) * 12.9898 + 78.233) * 43758.5453
	return x - floorf(x)


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
