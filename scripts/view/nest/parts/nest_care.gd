extends "res://scripts/view/nest/parts/nest_duties.gd"
## Nest view, layer 15 of 17 (new in v0.13.24, PART 0.13): care the simulation does that the nestmates act out here
## beside their duties - the queen fed mouth to mouth by an attendant (from sim.queen_given) and the nest's toilets
## (sim.toilets: the dark patches in chamber corners, and nestmates going there now and then).

# ---------------------------------------------------------------- the queen fed mouth to mouth (v0.13.24)
# The simulation has her attendants feed her from their crops every duty round (R8, sim_duties._feed_queen); drawn, they
# only licked her (BACKLOG, v0.13.23). Now, after a round in which she was really given something (sim.queen_given), one
# of her attendants by her - the one that gave it if it is there - steps up to her head, face to face, and holds a droplet
# out between its mandibles; she bows her head to it and laps (the taking pose, ACT_TAKE) while its gaster goes down a
# little. Rounds where nobody had anything to spare show none. A round is a second or two here, so not every one is drawn:
# a drop, then a break (QFEED_REST). [Lasius: the queen is fed by trophallaxis like any nestmate - Hölldobler & Wilson
# 1990; her pose, the time at her mouth and the break between drops chosen to look like the workers' own exchange.]
const QFEED_MIN := 0.001               # units given in the round (most rounds one attendant gives her ~0.01: what she ate)
const QFEED_S := Vector2(6.0, 10.0)    # seconds at her mouth (as long as a worker's exchange)
const QFEED_REST := Vector2(6.0, 14.0)    # seconds (at 1x) after one before the next is drawn [chosen]
const QFEED_GAP := 0.3                 # between its mandible tips and hers: the droplet
const QMOUTH := Vector3(1.18, 0.25, 0.0)   # her mandible tips taking a drop (act 21: head nodded -0.12 rad from MOUTH)
var _q_round := -1                     # the simulation's duty round last looked at
var _q_owed := false                   # she was given something since the last drop drawn
var _q_rest := 0.0                     # seconds until the next drop may be drawn
var _q_dev := "--qfeed" in OS.get_cmdline_user_args()   # dev (--qfeed): one after another, every round given or not (pose checks)


## Her mandible tips (bowed to take the drop: the pose she takes it in) and the way she faces, level.
func _queen_mouth() -> Array:
	var f: Vector3 = _queen_xf.basis.x * Vector3(1, 0, 1)
	return [_queen_xf * QMOUTH, f.normalized() if f.length() > 0.001 else Vector3.RIGHT]


## One of her attendants by her goes to her mouth: the one that gave her the drop first, if it is there.
func _queen_feed_now() -> bool:
	if not sim.queen.alive or _queen_busy() or not _queen_path.is_empty() or _queen_mm.instance_count == 0:
		return false
	for a in _anims:
		if a.get("qfeed", false):
			return false                               # (one at a time at her mouth)
	# her attendants: those the simulation has at her this round (Ant.D_QUEEN), whatever the drawn ant is doing between
	# its own duties, and the drawn ones still on that duty
	var at_her := {}
	for w in sim.workers:
		if w.duty == Ant.D_QUEEN:
			at_her[w.id] = true
	var near := []
	for m in _mates:
		var wid := int(m.get("wid", -1))
		# (one standing low on the chamber wall by her steps down to the floor: they are often there, round the brood)
		if (m.role == "attend" or at_her.has(wid) or sim.queen_given.has(wid)) and not m.has("script") and not m.carry \
				and not m.has("deliver") and m.has("vp") and (m.vu as Vector3).y > 0.5 and (m.vp as Vector3).distance_to(_spots.queen) < 14.0 \
				and absf((m.vp as Vector3).y - _spots.queen.y) < 1.6:
			near.append([0 if sim.queen_given.has(wid) else 1, (m.vp as Vector3).distance_to(_spots.queen), m])
	near.sort_custom(func(x, y): return x[0] < y[0] or x[0] == y[0] and x[1] < y[1])
	for e in near:
		if _start_queen_feed(e[2]):
			return true
	return false


func _start_queen_feed(m: Dictionary) -> bool:
	var vp: Vector3 = m.vp
	# she may turn her head toward it first, as she turns on the spot between other things (up to ~60 degrees; her head
	# swinging toward the side it comes from first): a crowded chamber has brood heaped all round her head
	var toward := signf(Vector3(cos(_queen_turn + 0.5), 0, -sin(_queen_turn + 0.5)).dot(vp - _queen_xf.origin) \
			- Vector3(cos(_queen_turn - 0.5), 0, -sin(_queen_turn - 0.5)).dot(vp - _queen_xf.origin))
	for turn in [0.0, 0.5 * toward, -0.5 * toward, 1.0 * toward, -1.0 * toward]:
		if _start_queen_feed_turned(m, vp, turn):
			return true
	return false


func _start_queen_feed_turned(m: Dictionary, vp: Vector3, turn: float) -> bool:
	var qxf := Transform3D(Basis(Vector3.UP, turn) * _queen_xf.basis, _queen_xf.origin)
	var f: Vector3 = (qxf.basis.x * Vector3(1, 0, 1)).normalized()
	var head: Vector3 = qxf * QMOUTH
	var reach: float = QFEED_GAP + MOUTH.x * float(m.size)
	var side: Vector3 = f.cross(Vector3.UP)
	if side.dot(vp - head) < 0.0:
		side = -side                                   # (its own side of her)
	for k in 9:
		# in front of her head, else round to either side of it (its own side first): her head is often among the brood
		var ang: float = (k + 1) / 2 * 0.35 * (1.0 if k % 2 == 1 else -1.0)
		var dir: Vector3 = (f * cos(ang) + side * sin(ang)).normalized()
		var spot: Vector3 = head + dir * reach
		var fl := _floor_cached(spot)
		spot.y = fl + 0.45
		if absf(spot.y - head.y) > 1.5 or _density_at(spot) > 0.35 or not _floor_solid(spot):
			continue
		# its thorax and gaster clear of the brood (its head reaches in over it to her mouth)
		var back: Vector3 = Vector3(spot.x, fl, spot.z) + dir * 0.6 * float(m.size)
		if not _brood_free(Vector3(spot.x, fl, spot.z), 0.2 * float(m.size)) or not _brood_free(back, 0.25 * float(m.size)):
			continue
		var via = _queen_way(vp, spot, side, f, head)
		if via == null:
			continue
		var a := {"k": "lick", "t": 0.0, "d": randf_range(QFEED_S.x, QFEED_S.y) * _anim_k(), "m": m, "spot": spot, "at": head,
			"p": head, "feeds": false, "queen": false, "r": QFEED_GAP, "qfeed": true, "walk": 0.0}
		if via != spot:
			a.via = via
		if turn != 0.0:
			_queen_rest_turn = _queen_turn + turn       # (and she stays so, as after any turn on the spot)
			a.qturn = true
		_hire(m, vp - Vector3(0, 0.45, 0), head, ACT_WALK)
		m.script.k = "lick"
		m.script.qfeed = true
		m.script.pos = vp
		m.script.goal = via
		duty_stats["queen fed"] = int(duty_stats.get("queen fed", 0)) + 1
		_anims.append(a)
		return true
	return false


## How it gets from vp to spot by her head without walking through her: straight (spot) if that way keeps clear of her
## body, else by a point off her head on its side (that point), else null. Over open floor all the way (_open_walk).
func _queen_way(vp: Vector3, spot: Vector3, side: Vector3, f: Vector3, head: Vector3):
	if vp.distance_to(spot) < 14.0 and _clear_of_queen(vp, spot) and _open_walk(vp, spot):
		return spot
	for out in [1.8, 2.4, 3.0]:
		for fwd in [0.8, 0.0, 1.6]:
			var via: Vector3 = head + side * out + f * fwd
			via.y = _floor_cached(via) + 0.45
			if _density_at(via) > 0.35 or not _floor_solid(via) or vp.distance_to(via) > 14.0 or via.distance_to(spot) > 5.0:
				continue
			if _clear_of_queen(vp, via) and _clear_of_queen(via, spot) and _open_walk(vp, via) and _open_walk(via, spot):
				return via
	return null


## Whether the straight way from a to b keeps an ant's body clear of the queen's (her body: the line from her head to her
## gaster's end, QUEEN_R round it; the last stretch at her mouth is allowed in to her head).
func _clear_of_queen(a: Vector3, b: Vector3) -> bool:
	var h: Vector3 = _queen_xf * QUEEN_HEAD
	var tail: Vector3 = _queen_xf * QUEEN_TAIL
	var ax := tail - h
	var n := maxi(1, int(a.distance_to(b) / 0.4))
	var start := INF
	for k in range(0, n + 1):
		var q := a.lerp(b, float(k) / n)
		var t := clampf((q - h).dot(ax) / maxf(ax.length_squared(), 0.0001), 0.0, 1.0)
		var r := QUEEN_R + 0.4 if t > 0.08 else 0.5         # (round her head itself the mouth comes in close)
		var d := (h + ax * t).distance_to(q)
		if k == 0:
			start = d                                      # (one resting close beside her may go, never closer in)
		elif d < minf(r, start - 0.1):
			return false
	return true


## After the life-cycle moments: the one at the queen's mouth (a "lick" moment marked qfeed) gives its drop the whole time
## it is there, she takes it; it is over if she moved off (turned, walked, another moment took her).
func _step_anims(adt: float) -> void:
	super(adt)
	_step_toilets(adt)
	var r: int = sim.tick / sim.DUTY_EVERY
	if r != _q_round:
		_q_round = r
		for id in sim.queen_given:
			if float(sim.queen_given[id]) >= QFEED_MIN:
				_q_owed = true
	_q_rest -= adt
	if _q_dev:
		_q_owed = true
		_q_rest = minf(_q_rest, 1.0)
	if _q_owed and _q_rest <= 0.0 and adt > 0.0:
		_q_rest = 0.5                                  # (tried every half second until one can go)
		if _queen_feed_now():
			_q_owed = false
			_q_rest = randf_range(QFEED_REST.x, QFEED_REST.y)
	for a in _anims:
		if not a.get("qfeed", false) or a.get("done", false) or a.t >= a.d:
			continue
		var lm = a.m
		var qm: Array = _queen_mouth()
		var turning: bool = a.has("qturn") and absf(wrapf(_queen_rest_turn - _queen_turn, -PI, PI)) > 0.04
		if not _mates.has(lm) or not lm.has("script") or not sim.queen.alive or _queen_busy() \
				or not turning and (qm[0] as Vector3).distance_to(a.at) > 0.5:
			a.t = a.d                                  # (ended by the moment itself next frame: released, a rest)
			if _mates.has(lm):
				lm.erase("fill")
			continue
		a.walk = float(a.get("walk", 0.0)) + adt
		if not a.get("there", false) and float(a.walk) > 10.0:
			a.t = a.d                                  # (could not get to her mouth: pushed aside, the way blocked)
			continue
		if a.has("via"):
			# round her head first, facing where it goes; then on to her mouth
			if (lm.script.pos as Vector3).distance_to(a.via) < 0.15:
				a.erase("via")
			else:
				lm.script.goal = a.via
				lm.script.face = a.via
				lm.script.act = ACT_WALK
				a.t = minf(a.t, 0.1 * a.d)
				continue
		lm.script.face = qm[0]
		# there once it has stepped onto its spot (and stays there: the lick's own test - its mouth on the thing - flickered
		# as her body kept its head a little off, and it walked on the spot for good)
		var sp: Vector3 = lm.script.pos
		if not a.get("there", false) and (turning or Vector2(sp.x - a.spot.x, sp.z - a.spot.z).length() > 0.15):
			lm.script.act = ACT_WALK
			a.t = minf(a.t, 0.1 * a.d)                 # (the drop is given once it is there)
			continue
		var u: float = a.t / a.d
		lm.script.act = ACT_FEED
		if _queen_act < 0:
			_queen_act = ACT_TAKE
		var cf := float(lm.get("cf", 0.0))
		lm.fill = lerpf(minf(1.0, cf + 0.15), cf, smoothstep(0.1, 0.95, u))
		a.there = true
		if u >= 0.98:
			lm.erase("fill")


## The droplet between its mandibles and hers, shrinking as she takes it.
func _draw_anims() -> void:
	super()
	_draw_toilets()
	for a in _anims:
		if not a.get("qfeed", false) or a.get("done", false) or not a.get("there", false):
			continue
		var lm = a.m
		if not _mates.has(lm) or not lm.has("xf") or lm.act != ACT_FEED:
			continue
		var mid: Vector3 = (((lm.xf as Transform3D) * MOUTH) + (_queen_mouth()[0] as Vector3)) * 0.5
		if _q_dev:
			print("QFEED u%.2f mouths %.2f" % [a.t / a.d, ((lm.xf as Transform3D) * MOUTH).distance_to(_queen_mouth()[0])])
		var left := 1.0 - clampf(a.t / a.d, 0.0, 1.0)
		if _visible(mid):
			_anim_drops.append(Transform3D(Basis.from_scale(Vector3.ONE * (0.35 + 0.45 * left) * (1.0 + 0.08 * sin(a.t * 6.0))), mid))


# ---------------------------------------------------------------- the toilets (v0.13.24, sim/toilets.gd)
# Each toilet the simulation keeps (a chamber-corner floor cell and the waste it has had) is drawn as a stain on the floor:
# a few overlapping soft dark patches, wider as the waste mounts (to ~1 cm across), with a darker wet middle once it has
# grown [Ln, Czaczkes et al. 2015: well-defined dark patches, "a dark, mud-like substance" in the middle of the bigger
# ones; the size and the colours here chosen]. Every so often a nestmate standing about near one walks over, turns its
# back to the corner and stands with its gaster over the patch a few seconds, leaving a fresh dark drop [inference: the
# paper did not see them defecate - it inferred it from the colour; the ants did not avoid the patches and often
# clustered on them].
const TOILET_RIM := Color(0.17, 0.11, 0.065, 0.5)     # the soil stained round it [chosen]
const TOILET_MUD := Color(0.055, 0.035, 0.022, 0.92)  # the dark mud-like middle [chosen colour]
const TOILET_R := Vector2(0.45, 3.2)                  # voxels: its radius, from a first drop to a big old one (~1 cm across)
const TVISIT_S := Vector2(8.0, 18.0)                  # seconds (at 1x) between visits drawn [chosen]
const FRESH_S := 40.0                                 # seconds a fresh drop shows before it is part of the patch
var _toilet_mm: MultiMesh = null
var _t_visit := 3.0
var _t_fresh: Array = []                              # [floor point, seconds left]
var _t_dev := "--look-toilet" in OS.get_cmdline_user_args()   # dev (--look-toilet): the camera on the first toilet


func _toilet_setup() -> void:
	var sh := Shader.new()
	sh.code = TOILET_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	# (the soil's volume, as the ants' feet read it: none of a patch is drawn in the soil - one in a corner reached into
	# the chamber wall and showed where the cut opened the soil)
	mat.set_shader_parameter("vol", _foot_vol)
	mat.set_shader_parameter("vol_size", Vector3(nest.wx(), nest.hy(), nest.wz()))
	mat.set_shader_parameter("vol_org", Vector3(nest.x_lo, nest.y_lo, nest.z_lo))
	_vol_mats.append(mat)
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	_toilet_mm = _multimesh(pm, mat, true, false)


# soft-edged, ragged, wet in the middle; the colour (and how dark) per patch
const TOILET_SHADER := "shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform sampler3D vol : filter_linear;
uniform vec3 vol_size = vec3(64.0);
uniform vec3 vol_org = vec3(0.0);
varying vec4 col;
varying vec3 wp;
void vertex() { col = COLOR; wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// (raw voxels read straight: just over the floor as drawn they read ~0.5, so it looks a little higher)
	if (texture(vol, (wp + vec3(0.0, 0.7, 0.0) - vol_org + 0.5) / vol_size).r >= 0.55) { discard; }
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	float th = atan(q.y, q.x) + col.a * 37.0;
	float edge = 0.8 + 0.06 * sin(th * 3.0) + 0.05 * sin(th * 7.0 + 1.3) + 0.03 * sin(th * 13.0 + 0.4);
	ALBEDO = col.rgb;
	ROUGHNESS = mix(0.3, 0.85, d);
	ALPHA = col.a * (1.0 - smoothstep(edge - 0.25, edge, d));
}
"


## The floor under a toilet's cell.
func _toilet_floor(c: Vector3i) -> Vector3:
	var p := Vector3(c)
	p.y = _floor_cached(p + Vector3(0, 0.3, 0))
	return p


## Where a toilet is drawn: its corner as the soil is shown - from the corner cell out into the chamber to the first
## floor that is open as drawn (the soil drawn smooth closes the nook a corner cell is in: the patch lay under the wall).
func _toilet_at(t: Dictionary) -> Vector3:
	var start := _toilet_floor(t.c)
	var out := _toilet_out(t)
	for k in 17:
		var q: Vector3 = start + out * (0.25 * k)
		var fl := _floor_cached(Vector3(q.x, start.y + 0.6, q.z))
		if absf(fl - start.y) < 0.8 and _density_at(Vector3(q.x, fl + 0.35, q.z)) < 0.5 and _density_at(Vector3(q.x, fl + 1.0, q.z)) < 0.5:
			return Vector3(q.x, fl, q.z)
	return start


## The way out of a toilet's corner into its chamber, level.
func _toilet_out(t: Dictionary) -> Vector3:
	var ch: int = int(t.ch)
	var c0 := Vector3(t.c as Vector3i)
	var mid: Vector3 = sim.nest.chambers[ch].c if ch >= 0 and ch < sim.nest.chambers.size() else c0
	var dir := (mid - c0) * Vector3(1, 0, 1)
	return dir.normalized() if dir.length() > 0.1 else Vector3.ZERO


## A point `off` from c0 on the same floor, drawn back toward c0 if that is in the chamber wall or off the floor.
func _on_floor_near(c0: Vector3, off: Vector3) -> Vector3:
	for k in 4:
		var q: Vector3 = c0 + off * pow(0.55, k)
		var fl := _floor_cached(Vector3(q.x, c0.y + 0.4, q.z))
		if absf(fl - c0.y) < 0.45 and _density_at(Vector3(q.x, fl + 0.3, q.z)) < 0.5:
			return Vector3(q.x, fl, q.z)
	return c0


func _draw_toilets() -> void:
	if _toilet_mm == null:
		_toilet_setup()
	var xs := []
	var cols := []
	for t in sim.toilets.patches:
		var amt := float(t.amt)
		if amt < 0.3:
			continue
		var c: Vector3i = t.c
		var r: float = clampf(TOILET_R.x + 0.3 * sqrt(amt), TOILET_R.x, TOILET_R.y)
		# (its middle a little out of the corner, into the chamber: the part in the walls is not drawn)
		var c0 := _on_floor_near(_toilet_at(t), _toilet_out(t) * minf(0.6, 0.3 * r))
		if not _visible(c0):
			continue
		var seed := c.x * 131 + c.z * 71 + c.y * 17
		for j in 4 + mini(6, int(amt / 20.0)):
			var ang := _hash(seed + j, 5) * TAU
			var off := Vector3(cos(ang), 0.0, sin(ang)) * r * 0.55 * _hash(seed + j, 6)
			var rr := r * (0.38 + 0.3 * _hash(seed + j, 7))
			var p := _on_floor_near(c0, off)
			xs.append(Transform3D(Basis(Vector3.UP, ang).scaled(Vector3(rr, 1.0, rr)), p + Vector3(0, 0.03 + 0.002 * j, 0)))
			cols.append(Color(TOILET_RIM.r, TOILET_RIM.g, TOILET_RIM.b, TOILET_RIM.a * (0.8 + 0.2 * _hash(seed + j, 8))))
		if amt > 3.0:
			var mr := r * 0.42
			xs.append(Transform3D(Basis(Vector3.UP, _hash(seed, 9) * TAU).scaled(Vector3(mr, 1.0, mr * 0.8)), c0 + Vector3(0, 0.05, 0)))
			cols.append(Color(TOILET_MUD.r, TOILET_MUD.g, TOILET_MUD.b, TOILET_MUD.a * minf(1.0, amt / 30.0)))
	for f in _t_fresh:
		if _visible(f[0]):
			xs.append(Transform3D(Basis.from_scale(Vector3(0.22, 1.0, 0.2)), (f[0] as Vector3) + Vector3(0, 0.06, 0)))
			cols.append(Color(TOILET_MUD.r, TOILET_MUD.g, TOILET_MUD.b, TOILET_MUD.a * clampf(float(f[1]) / FRESH_S * 1.5, 0.0, 1.0)))
	_toilet_mm.instance_count = xs.size()
	for i in xs.size():
		_toilet_mm.set_instance_transform(i, xs[i])
		_toilet_mm.set_instance_color(i, cols[i])


func _step_toilets(adt: float) -> void:
	if _t_dev:
		for t in sim.toilets.patches:
			if not t.old:
				target_t = _toilet_at(t)
				target = target_t
				if Engine.get_process_frames() % 300 == 0:
					var rr: float = clampf(TOILET_R.x + 0.3 * sqrt(float(t.amt)), TOILET_R.x, TOILET_R.y)
					var cc := _on_floor_near(_toilet_at(t), _toilet_out(t) * minf(0.6, 0.3 * rr))
					var open := 0
					for k in 64:
						var q: Vector3 = cc + Vector3(cos(k * 2.4), 0, sin(k * 2.4)) * rr * sqrt((k + 0.5) / 64.0)
						if _density_at(q + Vector3(0, 0.33, 0)) < 0.5:
							open += 1
					print("TOILET %s at %s centre %s amt %.1f r %.2f open %d/64 d.35 %.2f" % [t.c, target_t, cc, float(t.amt), rr, open, _density_at(cc + Vector3(0, 0.35, 0))])
				break
	for f in _t_fresh:
		f[1] = float(f[1]) - adt
	_t_fresh = _t_fresh.filter(func(f): return float(f[1]) > 0.0)
	# the one on its way or at the toilet: forward to it, then its back to the corner, standing still; a drop at 60%
	for a in _anims:
		if not a.get("toilet", false) or a.get("done", false) or a.t >= a.d:
			continue
		var lm = a.m
		if not _mates.has(lm) or not lm.has("script"):
			continue
		var sp: Vector3 = lm.script.pos
		if not a.get("there", false):
			if Vector2(sp.x - a.spot.x, sp.z - a.spot.z).length() > 0.15:
				lm.script.face = (a.spot as Vector3) + ((a.spot as Vector3) - sp).normalized() * 2.0
				lm.script.act = ACT_WALK
				a.t = minf(a.t, 0.3 * a.d)
				a.walk = float(a.get("walk", 0.0)) + adt
				if float(a.walk) > 10.0:
					a.t = a.d                          # (could not get there)
				continue
			a.there = true
		lm.script.face = a.at
		lm.script.act = ACT_REST
		if not a.get("dropped", false) and a.t > 0.6 * a.d and lm.has("xf"):
			a.dropped = true
			var tip: Vector3 = (lm.xf as Transform3D) * GASTER_TIP
			_t_fresh.append([Vector3(tip.x, _floor_cached(tip + Vector3(0, 0.3, 0)), tip.z), FRESH_S])
			if _t_fresh.size() > 12:
				_t_fresh.pop_front()
	_t_visit -= adt
	if _t_visit <= 0.0 and adt > 0.0:
		_t_visit = 1.0                                 # (tried every second until one can go)
		if _toilet_visit():
			_t_visit = randf_range(TVISIT_S.x, TVISIT_S.y)


## A nestmate standing about in a toilet's chamber goes to it (only to one in view; one at a time).
func _toilet_visit() -> bool:
	for a in _anims:
		if a.get("toilet", false):
			return false
	for t in sim.toilets.patches:
		if float(t.amt) < 0.3 or t.old:
			continue                                   # (one left behind as the chamber was widened: not used now)
		var c0 := _toilet_at(t)
		if not _visible(c0):
			continue
		# its back to the corner: facing out into the chamber
		var dir := _toilet_out(t)
		if dir == Vector3.ZERO:
			dir = Vector3.RIGHT
		for m in _mates:
			if not m.role in ["idle", "wander"] or m.has("script") or m.carry or m.has("deliver") or not m.has("vp") \
					or (m.vu as Vector3).y < 0.85:
				continue
			var vp: Vector3 = m.vp
			if Vector2(vp.x - c0.x, vp.z - c0.z).length() > 10.0 or absf(vp.y - 0.45 - c0.y) > 1.6:
				continue
			for k in 5:
				var ang: float = (k + 1) / 2 * 0.4 * (1.0 if k % 2 == 1 else -1.0)
				var d2: Vector3 = Basis(Vector3.UP, ang) * dir
				var spot: Vector3 = c0 + d2 * (absf(GASTER_TIP.x) - 0.25) * float(m.size)
				spot.y = _floor_cached(spot + Vector3(0, 0.4, 0)) + 0.45
				if absf(spot.y - 0.45 - c0.y) > 0.6 or _density_at(spot) > 0.35 or not _floor_solid(spot) or not _open_walk(vp, spot) \
						or not _brood_free(spot - Vector3(0, 0.45, 0), 0.35 * float(m.size)):
					continue
				var a := {"k": "lick", "t": 0.0, "d": randf_range(6.0, 10.0) * _anim_k(), "m": m, "spot": spot, "at": spot + d2 * 3.0,
					"p": c0, "feeds": false, "queen": false, "r": 9.0, "toilet": true}
				_hire(m, vp - Vector3(0, 0.45, 0), spot, ACT_WALK)
				m.script.k = "lick"
				m.script.toilet = true
				m.script.pos = vp
				m.script.goal = spot
				duty_stats["toilet"] = int(duty_stats.get("toilet", 0)) + 1
				_anims.append(a)
				return true
	return false


## What the ant tip says it is doing (nest_bodies._shown_act): at the toilet it stands as resting, and feeding the queen
## it is in the giving pose - said so in words (ant_tip: 25, 26).
func _shown_act(m: Dictionary) -> int:
	if m.has("script"):
		if m.script.get("toilet", false) and int(m.act) != ACT_WALK:
			return 25
		if m.script.get("qfeed", false) and int(m.act) == ACT_FEED:
			return 26
	return super(m)
