extends RefCounted
## How each enemy in the box is drawn this frame (moved out of parts/outworld_creatures.gd in v0.13.3): where it is
## (glided between simulation steps), its gait, how far into a strike (eased in and out - it snapped before), and from
## v0.13.3 the struggle (the keeper, 2026-11-12: "not so stiff - the abdomen and the head moving"): held by ants its
## body rocks a little; on its back (sim_enemies.flip_over, its death throes) it is rolled over onto its back and
## kicks (the shaders' INSTANCE_CUSTOM.y = 3 + how hard).

const CreatureRig := preload("res://scripts/view/outworld/creature_rig.gd")

## model units from the ground to the top of the back: lifted this much, a body rolled over lies on its back
const BACK_LIFT := {"wolf_spider": 3.9, "ground_beetle": 5.25, "centipede": 0.85}
## mm from the ground to the belly of a body on its back (where ants holding its back are then): the model's top less
## its underside (tools/dev/grip_fit.py's numbers)
const BACK_TOP_MM := {"wolf_spider": 4.6, "ground_beetle": 5.6, "centipede": 1.0}
const DYING_TICKS := 600.0       # sim_enemies.DYING_TICKS


static func update(o, delta: float) -> void:
	_frame += 1
	if _frame % 120 == 0:
		for id in _grab.keys():
			if int(_grab[id][2]) < _frame - 2:
				_grab.erase(id)
	var by_kind := {}
	for c in o.sim.creatures:
		if o._creature_views.has(c.kind):
			if not by_kind.has(c.kind):
				by_kind[c.kind] = []
			by_kind[c.kind].append(c)
	var seen := {}
	for kind in o._creature_views:
		var cv: Dictionary = o._creature_views[kind]
		var list: Array = by_kind.get(kind, [])
		var mm: MultiMesh = cv.mm
		mm.instance_count = list.size()
		for i in list.size():
			var s: Dictionary = list[i]
			seen[s.id] = true
			if not o._creature_vis.has(s.id):
				o._creature_vis[s.id] = {"p": s.pos, "a": s.ang, "mv": 0.0, "sk": 0.0, "roll": 0.0, "agit": 0.0}
			var v: Dictionary = o._creature_vis[s.id]
			var step: Vector2 = s.pos - v.p
			v.p += step * (1.0 - exp(-15.0 * delta))
			var was_a: float = v.a
			v.a = lerp_angle(v.a, s.ang, 1.0 - exp(-8.0 * delta))
			# how fast it is turning, for the centipede's body to curve round as it turns (not swing round stiff)
			var tr_rate := wrapf(v.a - was_a, -PI, PI) / maxf(delta, 0.001)
			v.bend = lerpf(float(v.get("bend", 0.0)), clampf(tr_rate / 1.5, -1.0, 1.0), minf(1.0, 4.0 * delta))
			v.mv = lerpf(v.mv, 1.0 if step.length_squared() > 0.0004 else 0.0, minf(1.0, 6.0 * delta))
			var held := int(s.get("held", 0)) > 0
			var back: bool = int(s.get("flip", 0)) > 0 or s.has("dying")
			# eased: a strike (up fast, down slower), the roll onto its back and off it, how hard it struggles
			var sk_to := 1.0 if int(s.get("strike", 0)) > 0 else 0.0
			v.sk = lerpf(float(v.get("sk", 0.0)), sk_to, minf(1.0, (14.0 if sk_to > v.get("sk", 0.0) else 6.0) * delta))
			v.roll = move_toward(float(v.get("roll", 0.0)), 1.0 if back else 0.0, delta * 0.9)      # (~1.1 s over: 0.7 s looked a snap)
			v.agit = lerpf(float(v.get("agit", 0.0)), 1.0 if held or back else 0.0, minf(1.0, 3.0 * delta))
			var p: Vector2 = v.p * o.U
			var up: Vector3 = o.ground_n(p.x, p.y)
			var f := Vector3(cos(v.a), 0, sin(v.a))
			f = (f - up * f.dot(up)).normalized()
			# out beyond the box (arriving or leaving) it is not drawn
			var inside: bool = Rect2(Vector2.ZERO, o.sim.WORLD).grow(-2.0).has_point(v.p)
			var sc: float = cv.scale if inside else 0.0
			var b := Basis(f, up, f.cross(up))
			var t: float = o._t + float(s.id) * 1.37
			# rocking as it struggles: a little roll and yaw (the shaders twist the head and abdomen besides)
			var ag: float = v.agit * (1.0 - v.roll)
			var rock := Basis(Vector3.RIGHT, ag * (0.07 * sin(t * 6.1) + 0.03 * sin(t * 13.0))) \
				* Basis(Vector3.UP, ag * 0.07 * sin(t * 4.3))
			# rolled over about its long axis, lifted by its back's height so that lies on the floor; on its back
			# it rocks from side to side as it kicks
			var r: float = smoothstep(0.0, 1.0, v.roll)
			var turn := PI * r + (0.22 * sin(t * 3.4) + 0.1 * sin(t * 7.9)) * r * _kick(s)
			var roll_b := Basis(Vector3.RIGHT, turn)
			var hc: float = float(BACK_LIFT.get(kind, 2.0)) * 0.5
			var lift: Vector3 = Vector3(0, hc, 0) - roll_b * Vector3(0, hc, 0)
			var lb: Basis = b * roll_b * rock
			# (a heave as it goes over: the body thrown up a little mid-roll, as a struggling animal kicks itself over)
			var heave: float = sin(PI * r) * hc * 0.7 * sc
			var origin := Vector3(p.x, o.ground_h(p.x, p.y), p.y) + b * (lift * sc) + up * heave
			mm.set_instance_transform(i, Transform3D(lb.scaled_local(Vector3.ONE * sc), origin))
			# (turning on the spot takes steps too: the feet round its body go ~18 px for each radian - v0.13.7)
			var gait: float = CreatureRig.gait(cv, v, s, step.length() * (1.0 - exp(-15.0 * delta)) + absf(wrapf(v.a - was_a, -PI, PI)) * 18.0, delta)
			# y: 0..1 into a strike, or 3 + how hard it kicks once it is over on its back, 5 feeding on prey held before its
			# fangs / 6 shaking a bitten one (the spider: enemies/spider_prey.gd); w: how much it is walking, + 2 while ants
			# are holding it down (it writhes)
			# (its legs start kicking as it begins to go over, and walk again only once nearly upright: no snap mid-roll)
			var y: float = (3.0 + _kick(s)) if (v.roll > 0.15 and back) or v.roll > 0.85 else float(v.sk)
			if s.has("prey") and v.roll <= 0.15:
				y = 6.0 if String(s.prey.get("mode", "")) == "shake" else 5.0
			var w: float = v.mv + (2.0 if held or back else 0.0)
			if kind == "centipede":
				w += 4.0 * floor((float(v.bend) + 1.0) * 50.0)      # (its turn packed above: centipede.gdshader)
			mm.set_instance_custom_data(i, Color(gait, y, o._t, w))
			v.xf = mm.get_instance_transform(i)
			v.kind = kind
			v.gait = gait
			v.held = 1.0 if held or back else 0.0          # (the centipede writhes on its back too: _writhe_offset)
	for id in o._creature_vis.keys():
		if not seen.has(id):
			o._creature_vis.erase(id)


## How hard it kicks on its back: in full when just turned over, fading through its death throes.
static func _kick(s: Dictionary) -> float:
	if s.has("dying"):
		return 0.15 + 0.85 * clampf(float(s.dying) / DYING_TICKS, 0.0, 1.0)
	return 1.0


## An ant holding spot height h (mm) on this creature: on its back the body is lower - the ant is on its belly then.
static func grip_h(o, foe_id: int, h: float) -> float:
	var v: Dictionary = o._creature_vis.get(foe_id, {})
	var r: float = float(v.get("roll", 0.0))
	if r <= 0.0:
		return h
	return lerpf(h, minf(h, float(BACK_TOP_MM.get(String(v.get("kind", "")), h))), smoothstep(0.0, 1.0, r))


## where the prey is held, in each model (the spider's fangs, the beetle's mandibles, the centipede's venom claws)
const PREY_AT := {"wolf_spider": Vector3(5.75, 1.3, 0.0), "ground_beetle": Vector3(9.7, 2.6, 0.0), "centipede": Vector3(10.4, 0.7, 0.0)}


## An ant in a spider's fangs (enemies/spider_prey.gd): held up across them, belly to the fangs, head down a little,
## the palps and front legs closed on it (spider.gdshader); shaken from side to side when it is to be dropped.
static func prey_xf(o, a, tr: Transform3D) -> Transform3D:
	var v: Dictionary = o._creature_vis.get(a.foe, {})
	if not v.has("xf"):
		return tr
	var shake := 0.0
	for c in o.sim.creatures:
		if c.id == a.foe and c.has("prey") and String(c.prey.get("mode", "")) == "shake":
			shake = 1.0
	var xf: Transform3D = v.xf
	var t: float = o._t
	var held_at: Vector3 = PREY_AT.get(String(v.get("kind", "")), PREY_AT.wolf_spider)
	var at: Vector3 = xf * (held_at + Vector3(0.0, 0.08 * sin(t * 5.0), 0.38 * shake * sin(t * 19.0)))
	at += o._writhe_offset(v, at)            # (the centipede's head swings with its body)
	var fwd: Vector3 = xf.basis.x.normalized()
	var side: Vector3 = xf.basis.z.normalized()
	var s: float = tr.basis.get_scale().x
	var b := Basis(side, fwd, side.cross(fwd)).rotated(side, -0.35 + 0.12 * sin(t * 3.1)).rotated(fwd, 0.25 * shake * sin(t * 19.0))
	return Transform3D(b.scaled(Vector3.ONE * s), at)


## model units from the ground up to the underside of the body at rest (tools/dev/grip_fit.py's bodies): on its back,
## the ants hold on there - the belly is up
## (the underside under the middle of the body: the spider's sternum and abdomen ~1.0, not its waist's 0.37 - v0.13.6,
## the ants stood off it in the air)
const BELLY := {"wolf_spider": 1.0, "ground_beetle": 1.6, "centipede": 0.25}
## the belly's extent in the model (x from, x to, half width): on its back the ants stay on it (v0.13.6: those from the
## legs were drawn in only part way and stood in the air beyond the body)
const BELLY_BOX := {"wolf_spider": Vector3(-6.0, 4.2, 1.6), "ground_beetle": Vector3(-7.0, 7.5, 2.8), "centipede": Vector3(-7.5, 8.0, 0.9)}
static var _hold := {}          # ant id -> [position, facing] of an ant holding a leg from the ground, eased


## Where an ant holding on to an enemy is drawn (v0.13.5, the keeper 2026-11-13: "the ants on the ground swing round
## with the spider as if locked to it; the ones on its body do not shake with it; on its back they float or stand
## round it in layers"):
##  - on the body: carried with the body as drawn - its rocking, its roll onto its back (creature_pose.update);
##  - holding a leg from the ground: led by it, easing after it over a fraction of a second and pulling back on it;
##  - once it is over on its back: all of them on its belly, nearer the middle (its legs are up in the air).
## spot: grip_spots.spots()[i % n]; layer: i / n (stood on the nestmate under it); s: the ant's scale.
static var _grab := {}          # ant id -> [time it took hold, its transform then, frame last seen holding]
static var _frame := 0


## (v0.13.7, the keeper: "the ants on it look too orderly; and they float, then dart on - not walking up onto it"):
## each one a little off its spot and turned its own way; and from where it was when it took hold it climbs onto the
## spot over ~0.6 s, in an arc up the body, instead of being there the next frame.
static func held_xf(o, a, foe: Dictionary, spot: Dictionary, layer: int, s: float, delta: float) -> Transform3D:
	var j := func(k: int) -> float: return fposmod(sin(float(a.id) * 12.9898 + k * 78.233) * 43758.5453, 1.0) * 2.0 - 1.0
	var messy := {"p": (spot.p as Vector2) + Vector2(j.call(1), j.call(2)) * 2.2, "h": spot.h,
		"pitch": float(spot.pitch) + 0.18 * j.call(3), "face": float(spot.face) + 0.65 * j.call(4)}
	var target := _held_target(o, a, foe, messy, layer, s, delta)
	var g: Array = _grab.get(a.id, [])
	if g.is_empty() or int(g[2]) < _frame - 2:
		var from: Transform3D = a.vxf if a.vxf is Transform3D else target
		g = [float(o._t), from, _frame]
	g[2] = _frame
	_grab[a.id] = g
	var u := clampf((float(o._t) - float(g[0])) / 0.6, 0.0, 1.0)
	if u >= 1.0:
		return target
	var e := smoothstep(0.0, 1.0, u)
	var from_xf: Transform3D = g[1]
	var out := from_xf.interpolate_with(target, e)
	var up: Vector3 = target.basis.y.normalized()
	out.origin += up * sin(PI * u) * 0.6 * s * float(spot.h > 0.6)       # (up the side, not through it)
	return out


static func _held_target(o, a, foe: Dictionary, spot: Dictionary, layer: int, s: float, delta: float) -> Transform3D:
	var v: Dictionary = o._creature_vis.get(a.foe, {})
	var xf: Transform3D = v.get("xf", Transform3D())
	var sc: float = maxf(0.01, xf.basis.get_scale().x)
	var xb: Basis = xf.basis.orthonormalized()
	var px_to_model: float = o.U / sc
	var mm_to_model: float = 1.0 / (1.5 * sc)
	var t: float = o._t + a.id * 0.61
	var p: Vector2 = spot.p
	var face: float = float(spot.face)          # (grip_spots.spots(): already in the creature's own frame - v0.13.5 took
	                                            # its angle off again, and the ants faced every which way)
	var f := Vector3(cos(face), 0.0, sin(face))
	var on_ground: bool = float(spot.h) <= 0.6
	if not on_ground or float(v.get("roll", 0.0)) >= 0.5:
		_hold.erase(a.id)
	if float(v.get("roll", 0.0)) >= 0.5:
		# on its back: on the belly (which is up), the ground ones drawn in toward the middle
		var box: Vector3 = BELLY_BOX.get(String(foe.kind), Vector3(-4, 4, 1))
		var lx: float = clampf(p.x * px_to_model * (0.55 if on_ground else 1.0), box.x, box.y)
		var lz: float = clampf(p.y * px_to_model * (0.4 if on_ground else 0.8), -box.z, box.z)
		var local := Vector3(lx, float(BELLY.get(String(foe.kind), 0.5)) - layer * 1.3 * mm_to_model, lz)
		var lb := Basis(f, Vector3.DOWN, f.cross(Vector3.DOWN))
		return Transform3D((xb * lb).scaled(Vector3.ONE * s), xf * local)
	if not on_ground:
		# on the body: with it, rocking and twisting as it does; tilted head-up as the spot says
		var local := Vector3(p.x * px_to_model, (float(spot.h) + layer * 1.3) * mm_to_model, p.y * px_to_model)
		var lb := Basis(f, Vector3.UP, f.cross(Vector3.UP))
		lb = Basis(lb.z, float(spot.pitch)) * lb
		return Transform3D((xb * lb).scaled(Vector3.ONE * s), xf * local)
	# from the ground: where its leg is now, eased (dragged after it, not locked to it), pulling back in short tugs
	var cp: Vector2 = v.get("p", foe.pos)
	var ca: float = float(v.get("a", foe.ang))
	var at2: Vector2 = cp + p.rotated(ca)
	var gx: float = at2.x * o.U
	var gz: float = at2.y * o.U
	var target := Vector3(gx, o.ground_top(gx, gz) + layer * 1.3 / 1.5, gz)
	var ang: float = ca + face
	var h: Array = _hold.get(a.id, [target, ang])
	var k := 1.0 - exp(-5.0 * delta)
	h[0] = (h[0] as Vector3).lerp(target, k)
	h[1] = lerp_angle(float(h[1]), ang, 1.0 - exp(-4.0 * delta))
	_hold[a.id] = h
	var fw := Vector3(cos(h[1]), 0.0, sin(h[1]))
	var up: Vector3 = o.ground_top_n(gx, gz)
	fw = (fw - up * fw.dot(up)).normalized()
	var b := Basis(fw, up, fw.cross(up))
	b = Basis(b.z, float(spot.pitch) + 0.08 * sin(t * 6.0)) * b                 # (rearing at the leg, heaving)
	var tug := fw * (-0.12 * s * maxf(0.0, sin(t * 5.0)))                       # (pulling back on it)
	return Transform3D(b.scaled(Vector3.ONE * s), (h[0] as Vector3) + tug)
