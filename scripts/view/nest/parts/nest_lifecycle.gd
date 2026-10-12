extends "res://scripts/view/nest/parts/nest_brood.gd"
## Nest view, layer 4 of 7: life-cycle moments acted out from sim.events (egg laying, pupation,
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
			cands.append([d, m])
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
	if nest.walkable(c):
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
	if not sim.queen.alive or _spots.queen == Vector3.ZERO:
		return
	var idx := maxi(0, sim.eggs.size() - 1 - _pending("egg"))
	var pile: Vector3 = _egg_xf(idx).origin if not _spots.eggs.is_empty() else _spots.queen
	var a := {"k": "egg", "t": 0.0, "d": 5.0 * _anim_k(), "pile": pile, "helper": null}
	var hs := _helpers(_spots.queen, 1, 7.0)
	if not hs.is_empty():
		a.helper = hs[0]
		_hire(a.helper, _beside(_queen_xf * GASTER_TIP, a.helper, 1.2), _queen_xf * GASTER_TIP, ACT_TEND)
	_anims.append(a)


func _start_pupate(s: float) -> void:
	if _spots.larvae.is_empty():
		return
	var p: Vector3 = _pile_xf(_spots.larvae, sim.larvae.size() + _pending("pupate"), 1.0).origin
	var a := {"k": "pupate", "t": 0.0, "d": 7.0 * _anim_k(), "p": p, "s": s, "helper": null, "carried": false}
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
	var a := {"k": "eclose", "t": 0.0, "d": 13.0 * _anim_k(), "p": p, "s": s, "helpers": [], "yaw": randf() * TAU,
		"queen": false}
	for m in _helpers(p, 2):
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
	var head: Vector3 = a.p + Vector3(0, 0.3, 0) + bx * 1.3 * s
	var pull := clampf((u - 0.5) / 0.22, 0.0, 1.0)
	var roll := lerpf(1.3, 0.0, clampf((u - 0.85) / 0.13, 0.0, 1.0))
	var origin: Vector3 = a.p + Vector3(0, 0.15 + 0.25 * roll, 0) + bx * (pull * 2.5 * s - 0.4 * s)
	var callow := Transform3D((b * Basis(Vector3.RIGHT, roll)).scaled(Vector3.ONE * s), origin)
	return {"bx": bx, "head": head, "pull": pull, "callow": callow, "side": b.z}


func _step_anims(adt: float) -> void:
	_queen_act = -1
	_queen_turn_t = 0.0
	var walk := 3.5 / _anim_k()                   # voxels per second for hired helpers
	var fresh := []
	for m in _mates:
		if m.has("script"):
			m.script.pos = (m.script.pos as Vector3).move_toward(m.script.goal, walk * adt)
	for a in _anims:
		a.t += adt
		var u: float = a.t / a.d
		match a.k:
			"egg":
				var h = a.helper
				if h != null and not _mates.has(h):
					a.helper = null
					h = null
				if u < 0.3:
					_queen_act = ACT_LAY
				elif h == null:
					# a founding queen tends her eggs herself: she curls her gaster forward under her body and
					# takes the egg in her mandibles, turns to face her egg packet, sets it down, turns back
					if not a.has("turn0"):
						a.turn0 = _queen_turn
						var to: Vector3 = (a.pile as Vector3) - _queen_xf.origin
						a.turn1 = atan2(-to.z, to.x)
					if u < 0.5:
						_queen_act = ACT_TAKE_EGG
						_queen_turn_t = a.turn0
					elif u < 0.9:
						_queen_act = ACT_TEND
						_queen_turn_t = a.turn1
					else:
						_queen_act = ACT_REST
						_queen_turn_t = a.turn0
				elif u < 0.4:
					h.script.act = ACT_TEND
				elif u < 0.85:
					h.script.goal = a.pile + Vector3(0, 0.45, 0) + (Vector3(h.cell) - a.pile).normalized() * 1.0
					h.script.face = a.pile
					h.script.act = ACT_CARRY
				else:
					h.script.act = ACT_TEND
				if u >= 1.0:
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
				var hs: Array = a.helpers.filter(func(m): return _mates.has(m))
				a.helpers = hs
				var ep := _eclose_parts(a, u)
				var callow_head: Vector3 = (ep.callow as Transform3D) * MOUTH
				for i in hs.size():
					var m: Dictionary = hs[i]
					var lift := Vector3(0, 0.45, 0)
					if i == 0:
						# at the head end: bites through the silk, then backs away pulling the callow out
						m.script.goal = (ep.head as Vector3) + (ep.bx as Vector3) * (1.3 * a.s + ep.pull * 2.5 * a.s) + lift - Vector3(0, 0.3, 0)
						m.script.face = ep.head if u < 0.5 else callow_head
					else:
						# alongside: helps with the silk, then peels the pupal skin off the callow's body
						var along: float = -0.2 + ep.pull * 1.6
						m.script.goal = a.p + (ep.side as Vector3) * (1.7 * a.s) + (ep.bx as Vector3) * along * a.s + lift
						m.script.face = (ep.callow as Transform3D).origin if u > 0.5 else ep.head
					if u < 0.18:
						m.script.act = ACT_TEND           # checking the cocoon
					elif u < 0.72:
						m.script.act = ACT_DIG            # biting the silk open / pulling
					elif u < 0.86 or i > 0:
						m.script.act = ACT_TEND           # peeling and licking the newcomer clean
					else:
						m.script.act = ACT_FEED           # the first meal, mouth to mouth
				if a.queen and sim.queen.alive:
					var d: Vector3 = ep.head - _spots.queen
					_queen_turn_t = atan2(-d.z, d.x)
					_queen_act = ACT_DIG if (u > 0.18 and u < 0.72) else ACT_TEND
				if u >= 1.0:
					a.done = true
					for m in hs:
						_release(m)
					var o: Vector3 = (ep.callow as Transform3D).origin
					_add_mate(Vector3i(roundi(o.x), roundi(a.p.y + 0.45), roundi(o.z)), "nurse", sim.tick, a.s)
					var newborn: Dictionary = _mates[-1]
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
	_queen_turn = lerp_angle(_queen_turn, _queen_turn_t, minf(1.0, 3.0 * adt))


## Ants still being born are drawn here: pulled head first out of the cocoon still wrapped in the
## pupal skin, legs folded; once the skin is peeled off it rolls upright and unfolds, then joins _mates.
func _emerging(xs: Array, cols: Array, cus: Array, young: Color) -> void:
	for a in _anims:
		if a.k != "eclose":
			continue
		var u: float = a.t / a.d
		if u < 0.5:
			continue
		var tr: Transform3D = _eclose_parts(a, u).callow
		if _visible(tr.origin):
			xs.append(tr)
			cols.append(young.lightened(0.3))
			cus.append(Color(0.0, ACT_EMERGE, maxf(0.0, (u - 0.82) * a.d), 0.0))


func _draw_anims() -> void:
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
				var sc := clampf(0.25 + u / 0.3 * 0.75, 0.25, 1.0)
				if h == null:
					# with her gaster curled forward the tip comes up under her head: the egg goes from one
					# to the other there, then rides in her mandibles until she lays it on the packet
					var mouth: Vector3 = _queen_xf * MOUTH_LOW
					var under: Vector3 = _queen_xf * TIP_CURLED
					if u > 0.3:
						p = tip.lerp(under, clampf((u - 0.3) / 0.1, 0.0, 1.0))
					if u > 0.42:
						p = under.lerp(mouth, clampf((u - 0.42) / 0.06, 0.0, 1.0))
					if u > 0.8:
						p = mouth.lerp(a.pile + Vector3(0, 0.25, 0), clampf((u - 0.8) / 0.1, 0.0, 1.0))
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
					var lb := Basis(Vector3.UP, a.t * 0.3).scaled(Vector3.ONE * s)
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
			"eclose":
				if not _visible(a.p):
					continue
				var ep := _eclose_parts(a, u)
				var wig := sin(a.t * 9.0) * 0.16 * clampf((u - 0.06) / 0.1, 0.0, 1.0) if u < 0.55 else 0.0
				var b := Basis(Vector3.UP, a.yaw) * Basis(Vector3.RIGHT, wig)
				var open := clampf((u - 0.45) / 0.1, 0.0, 1.0)
				# once empty the shell slumps a little; the silk is torn at the head end
				var sc: Vector3 = Vector3(1.0 - 0.08 * open, 1.0 - 0.22 * clampf((u - 0.7) / 0.2, 0.0, 1.0), 1.0) * a.s
				var tone := lerpf(1.0, 0.72, clampf(u / 0.2, 0.0, 1.0)) if u < 0.6 else lerpf(0.72, 0.95, clampf((u - 0.6) / 0.15, 0.0, 1.0))
				cocoons.append([Transform3D(b.scaled(sc), a.p + Vector3(0, 0.3, 0)), Color(tone, tone, tone)])
				var peel := clampf((u - 0.72) / 0.13, 0.0, 1.0)
				if u > 0.5 and peel < 1.0:
					var skin := (ep.callow as Transform3D) * Transform3D(Basis.from_scale(Vector3(1.15, 0.75, 0.8)), Vector3(-0.15, 0.4, 0))
					silk.append([skin, 0.5 * (1.0 - peel)])
				if peel > 0.0:
					# the shed pupal skin, a crumpled pale scrap beside the cocoon
					silk.append([Transform3D(Basis.from_scale(Vector3(0.32, 0.18, 0.28) * a.s * peel), a.p + (ep.side as Vector3) * 0.9 * a.s + Vector3(0, 0.2, 0)), 0.85])
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
