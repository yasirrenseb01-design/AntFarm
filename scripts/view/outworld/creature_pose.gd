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
			v.a = lerp_angle(v.a, s.ang, 1.0 - exp(-8.0 * delta))
			v.mv = lerpf(v.mv, 1.0 if step.length_squared() > 0.0004 else 0.0, minf(1.0, 6.0 * delta))
			var held := int(s.get("held", 0)) > 0
			var back: bool = int(s.get("flip", 0)) > 0 or s.has("dying")
			# eased: a strike (up fast, down slower), the roll onto its back and off it, how hard it struggles
			var sk_to := 1.0 if int(s.get("strike", 0)) > 0 else 0.0
			v.sk = lerpf(float(v.get("sk", 0.0)), sk_to, minf(1.0, (14.0 if sk_to > v.get("sk", 0.0) else 6.0) * delta))
			v.roll = move_toward(float(v.get("roll", 0.0)), 1.0 if back else 0.0, delta * 2.2)
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
			var origin := Vector3(p.x, o.ground_h(p.x, p.y), p.y) + b * (lift * sc)
			mm.set_instance_transform(i, Transform3D(lb.scaled_local(Vector3.ONE * sc), origin))
			var gait: float = CreatureRig.gait(cv, v, s, step.length() * (1.0 - exp(-15.0 * delta)), delta)
			# y: 0..1 into a strike, or 3 + how hard it kicks once it is over on its back; w: how much it is walking,
			# + 2 while ants are holding it down (it writhes)
			var y: float = (3.0 + _kick(s)) if v.roll > 0.5 else float(v.sk)
			mm.set_instance_custom_data(i, Color(gait, y, o._t, v.mv + (2.0 if held or back else 0.0)))
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
