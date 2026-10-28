extends RefCounted
## The garden plot's scenery laid out the way a patch of ground looks, not scattered evenly (wild scenario; the
## keeper's box keeps the even scatter in ground_data.gd): big stones by the corners as the main points, moss on
## their shaded side and gravel washed out round their feet, dry leaves caught in drifts on the sheltered side of
## stones and at the edge of the grass, the grass in one thick clump (and a smaller one) with broad-leaved weeds in
## it, and the ground round the nest entrance left bare. (The keeper, 2026-10-24, from a reference picture.)
## Only looks: a generator of its own from the plot's seed, never sim.rng. The big stones lie just outside the plot,
## where the foragers never go, so nothing they do changes. The simulation's own stones (sim.rocks) are dressed
## with draws of their own (seeded by where each lies), so a stone the keeper adds never reshuffles the rest.
## Which side moss grows on and where leaves pile up: [inference: moss keeps to the damp, shaded foot of a stone;
## litter settles where the wind is broken - general field observation, not from a study].

const MARGIN := 330.0                  # px of garden drawn past the plot all round (outworld_scene GARDEN_MARGIN 110 units)
const NEST_CLEAR := 70.0               # px (3.5 cm) of bare ground round the entrance, outside the crater of pellets
const SHADE := Vector2(-0.47, -0.88)   # the side of a stone away from the sun (outworld_view _sun, seen from above)
const LEAF_COLS := ["a0602a", "b8733a", "8f5a2a", "7a4a24", "c4813f", "6b4a2c", "5a3d24", "9a4f22"]


static func build(g, sim, r: RandomNumberGenerator) -> void:
	var size: Vector2 = sim.WORLD
	var lo := Vector2(-MARGIN, -MARGIN) + Vector2(20, 20)
	var hi := size + Vector2(MARGIN, MARGIN) - Vector2(20, 20)
	var wind := Vector2.from_angle(r.randf() * TAU)            # the way the leaves were blown
	var corners := [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]
	var meadow := r.randi() % 4
	# ---- big stones just outside the plot, by its corners (and now and then one along an edge)
	for k in 4:
		var c: Vector2 = corners[k]
		var out := Vector2(-1 if c.x == 0 else 1, -1 if c.y == 0 else 1)
		var rad := r.randf_range(45.0, 90.0)
		var side := r.randf() < 0.5
		var along := r.randf_range(-0.3, 1.6) * rad
		var gap := r.randf_range(4.0, 30.0)
		var skip := r.randf() < (0.55 if k == meadow else 0.12)
		var p := c + (Vector2(out.x * (rad + gap), -out.y * along) if side else Vector2(-out.x * along, out.y * (rad + gap)))
		if not skip:
			_add_boulder(g, r, p, rad)
			# a smaller stone or two against it (inside the plot only small enough to climb, as sim CLIMB_R)
			for j in r.randi_range(0, 2):
				var r2 := r.randf_range(10.0, 30.0)
				var q := p + Vector2.from_angle(r.randf() * TAU) * (rad + r2 * r.randf_range(0.7, 1.1))
				if _rect_dist(q, size) < r2 + 2.0:
					r2 = minf(r2, 13.0)
				_add_boulder(g, r, q, r2)
	if r.randf() < 0.5:
		var e := r.randi() % 4
		var t := r.randf_range(0.25, 0.75)
		var rad := r.randf_range(35.0, 60.0)
		var gap := rad + r.randf_range(4.0, 25.0)
		_add_boulder(g, r, [Vector2(t * size.x, -gap), Vector2(size.x + gap, t * size.y), Vector2(t * size.x, size.y + gap),
			Vector2(-gap, t * size.y)][e], rad)
	# a few more out in the garden round about
	for i in r.randi_range(3, 6):
		for attempt in 20:
			var p := Vector2(r.randf_range(lo.x, hi.x), r.randf_range(lo.y, hi.y))
			var rad := r.randf_range(18.0, 45.0)
			if _rect_dist(p, size) > rad + 4.0:
				_add_boulder(g, r, p, rad)
				break
	# ---- each stone dressed: moss, gravel, leaves, a tuft at its foot
	for b in g.boulders:
		var a := RandomNumberGenerator.new()
		a.seed = int(b.seed)
		_dress(g, a, b.p, b.r, wind)
	for rk in sim.rocks:
		var a := RandomNumberGenerator.new()
		a.seed = (int(rk.pos.x * 7919.0 + rk.pos.y * 104729.0) ^ int(sim.plot_seed)) & 0x7fffffff | 1
		_dress(g, a, rk.pos, float(rk.r), wind)
	# ---- the grass: one thick clump by a corner, spilling out of the plot, and often a smaller one across from it
	var inward := Vector2(1 if corners[meadow].x == 0 else -1, 1 if corners[meadow].y == 0 else -1)
	var mc: Vector2 = corners[meadow] + inward * Vector2(r.randf_range(30.0, 170.0), r.randf_range(20.0, 110.0))
	_clump(g, r, mc, Vector2(r.randf_range(200.0, 320.0), r.randf_range(110.0, 180.0)), r.randf_range(-0.35, 0.35), 120, wind)
	if r.randf() < 0.75:
		var o: Vector2 = corners[(meadow + 2) % 4]
		var oc := o.lerp(size * 0.5, r.randf_range(0.0, 0.25)) + Vector2(r.randfn(0, 60), r.randfn(0, 40))
		_clump(g, r, oc, Vector2(r.randf_range(90.0, 160.0), r.randf_range(60.0, 100.0)), r.randf() * TAU, 40, wind)
	# single tufts and weeds about the garden (fewer in the open middle of the plot)
	for i in 14:
		var p := Vector2(r.randf_range(lo.x, hi.x), r.randf_range(lo.y, hi.y))
		var keep := _rect_dist(p, size) > 0.0 or r.randf() < 0.4
		for k in r.randi_range(1, 4):
			var t := _tuft(r, p + Vector2(r.randfn(0.0, 9.0), r.randfn(0.0, 9.0)), r.randf_range(0.8, 1.2))
			if keep:
				g.tufts.append(t)
	for i in 10:
		var p := Vector2(r.randf_range(lo.x, hi.x), r.randf_range(lo.y, hi.y))
		var w := _rosette(r, p, r.randf_range(0.6, 1.0))
		if _rect_dist(p, size) > 0.0 or i < 4:
			g.rosettes.append(w)
	# ---- dry leaves: drifts in the open, a few strays, a few twigs
	for i in r.randi_range(4, 7):
		var c := Vector2(r.randf_range(0.0, size.x), r.randf_range(0.0, size.y)).lerp(
			Vector2(r.randf_range(lo.x, hi.x), r.randf_range(lo.y, hi.y)), 0.35)
		_drift(g, r, c, r.randi_range(4, 10), wind, 1.0)
	for i in 24:
		var sl := _leaf(r, Vector2(r.randf_range(lo.x, hi.x), r.randf_range(lo.y, hi.y)), r.randf() * TAU)
		if i % 2 == 0:
			g.litter.append(sl)               # (as many drawn as before - the rest of the garden stays where it was -
			                                  # half of them kept: they are bigger now)
	for i in r.randi_range(6, 10):
		var l := _leaf(r, Vector2(r.randf_range(lo.x, hi.x), r.randf_range(lo.y, hi.y)), r.randf() * TAU)
		l.twig = true
		g.litter.append(l)
	# ---- gravel washed into streaks across the open ground, and fine grit everywhere
	for i in r.randi_range(2, 4):
		var p := Vector2(r.randf_range(0.0, size.x), r.randf_range(0.0, size.y))
		_streak(g, r, p, Vector2.from_angle(r.randf() * TAU), r.randf_range(90.0, 220.0), 60)
	for i in 500:
		var p := Vector2(r.randf_range(lo.x, hi.x), r.randf_range(lo.y, hi.y))
		g.pebbles.append(_pebble(r, p, r.randf_range(0.6, 1.4)))
	_clear(g, sim, lo, hi)


## A big stone (px): the same kind of lumpy outline as the simulation's stones (sim_base add_rock).
static func _add_boulder(g, r: RandomNumberGenerator, p: Vector2, rad: float) -> void:
	# a rounded, slightly long outline (smooth bulges, not the points of a star)
	var poly := PackedVector2Array()
	var ph := [r.randf() * TAU, r.randf() * TAU, r.randf() * TAU]
	var flat := r.randf_range(0.7, 0.95)
	var turn := r.randf() * TAU
	for k in 22:
		var a := TAU * k / 22.0
		var rr := rad * (1.0 + 0.09 * sin(2.0 * a + ph[0]) + 0.06 * sin(3.0 * a + ph[1]) + 0.03 * sin(5.0 * a + ph[2]))
		poly.append((Vector2.from_angle(a) * rr * Vector2(1.0, flat)).rotated(turn))
	g.boulders.append({"p": p, "r": rad, "poly": poly, "tone": r.randf(), "seed": r.randi() & 0x7fffffff | 1})


## Moss on the shaded side of a stone, gravel round its foot running off one way, leaves on its sheltered side.
static func _dress(g, a: RandomNumberGenerator, p: Vector2, rad: float, wind: Vector2) -> void:
	var mid := SHADE.angle() + a.randf_range(-0.8, 0.8)
	var span := a.randf_range(0.5, 1.1)
	var blobs := []
	var grow := clampf(rad / 40.0, 0.8, 1.9)          # bigger stones carry bigger cushions
	for i in int(clampf(rad * 1.4, 14.0, 130.0)):
		var ang := mid + a.randfn(0.0, span)
		var d := rad * a.randf_range(0.8, 0.98) + absf(a.randfn(0.0, 1.5 + rad * 0.07))
		blobs.append([p + Vector2.from_angle(ang) * d, a.randf_range(1.4, 3.6) * grow, a.randf()])
	if a.randf() < 0.85:
		g.moss.append(blobs)
	var flow := Vector2.from_angle(a.randf() * TAU)
	for i in int(rad * 1.6):
		var ang := flow.angle() + a.randfn(0.0, 1.1)
		var d := rad * (0.95 + absf(a.randfn(0.0, 0.2)))
		g.pebbles.append(_pebble(a, p + Vector2.from_angle(ang) * d, a.randf_range(1.2, 3.2) * clampf(rad / 40.0, 0.7, 1.5)))
	_streak(g, a, p + flow * rad, flow, rad * a.randf_range(1.2, 3.0), int(rad * 0.9))
	var n := a.randi_range(1, 6) if rad > 30.0 else a.randi_range(0, 3)
	_drift(g, a, p + wind * rad * 1.15, n, wind, 0.6)
	for i in a.randi_range(0, 3 if rad > 30.0 else 1):
		g.tufts.append(_tuft(a, p + Vector2.from_angle(a.randf() * TAU) * rad * a.randf_range(0.95, 1.2), a.randf_range(0.8, 1.15)))


## A clump of grass (ellipse half-axes `ax` px, turned `ang`): tall thick tufts in the middle, thinner at the edge,
## weeds among them, moss in its damp edge and leaves caught along its downwind side.
static func _clump(g, r: RandomNumberGenerator, c: Vector2, ax: Vector2, ang: float, n: int, wind: Vector2) -> void:
	for i in n:
		var o := Vector2(r.randfn(0.0, 0.42) * ax.x, r.randfn(0.0, 0.42) * ax.y)
		var edge := clampf(o.length() / ax.length(), 0.0, 1.0)
		g.tufts.append(_tuft(r, c + o.rotated(ang), lerpf(1.7, 1.0, edge)))
	for i in int(n / 9):
		var o := Vector2(r.randfn(0.0, 0.55) * ax.x, r.randfn(0.0, 0.55) * ax.y)
		g.rosettes.append(_rosette(r, c + o.rotated(ang), r.randf_range(0.8, 1.3)))
	for i in r.randi_range(1, 3):
		var o := Vector2.from_angle(r.randf() * TAU) * ax * 0.85
		var blobs := []
		var mc := c + o.rotated(ang)
		for k in 60:
			blobs.append([mc + Vector2(r.randfn(0, 8), r.randfn(0, 5.5)), r.randf_range(2.0, 4.2), r.randf()])
		g.moss.append(blobs)
	var down := wind.rotated(-ang)
	_drift(g, r, c + (down * ax).rotated(ang) * 0.8, r.randi_range(5, 10), wind, 1.3)


## A tuft of grass; `big` scales its height and how many blades it has.
static func _tuft(r: RandomNumberGenerator, p: Vector2, big: float) -> Dictionary:
	return {"p": p, "n": int(r.randi_range(9, 16) * big), "h": big, "s": r.randf_range(1.8, 2.8) * sqrt(big)}


## A low broad-leaved weed (a plantain-like rosette): `n` leaves from one point, lifted a little.
static func _rosette(r: RandomNumberGenerator, p: Vector2, big: float) -> Dictionary:
	# (x1.8 since v0.11.72, leaves 1.4-2.5 cm: the keeper, "the plants a little bigger" - real ones are bigger still)
	return {"p": p, "n": r.randi_range(5, 8), "l": r.randf_range(16.0, 28.0) * big * 1.8, "w": r.randf_range(4.5, 7.5) * big * 1.8,
		"a": r.randf() * TAU, "tilt": r.randf_range(0.35, 0.8),
		"c": Color(0.2, 0.36, 0.11).lerp(Color(0.36, 0.5, 0.17), r.randf())}


## Leaves dropped in a drift round `c`, strung out along the wind.
static func _drift(g, r: RandomNumberGenerator, c: Vector2, n: int, wind: Vector2, spread: float) -> void:
	for i in n:
		var o := Vector2(r.randfn(0.0, 20.0), r.randfn(0.0, 10.0)) * spread
		var l := _leaf(r, c + o.rotated(wind.angle()), wind.angle() + r.randfn(0.0, 1.2))
		l.twig = r.randf() < 0.08
		if l.twig or i % 2 == 0:
			g.litter.append(l)


static func _leaf(r: RandomNumberGenerator, p: Vector2, ang: float) -> Dictionary:
	var base := Color(LEAF_COLS[r.randi() % LEAF_COLS.size()])
	# fallen birch leaves (Betula pendula, a common garden tree: the blade 3-7 cm long, 2-5 cm wide - docs/BIOLOGY.md);
	# 4-7 cm here, half width ~0.35 of the length. (The keeper, 2026-10-29: "what leaves are these, why so small" - they
	# were 1.2-2.6 cm, no tree's in particular)
	var l := r.randf_range(80.0, 140.0)                # (4-7 cm since v0.11.72 - the keeper: "a little bigger")
	return {"p": p, "a": ang, "l": l, "w": l * (0.3 + 0.08 * r.randf()),
		"c": base.lerp(Color("3d2a1b"), r.randf() * 0.35), "twig": false, "curl": r.randf_range(-0.2, 0.3)}


## Gravel washed out in a streak from `p` along `dir`, wider and thinner toward its end.
static func _streak(g, r: RandomNumberGenerator, p: Vector2, dir: Vector2, length: float, n: int) -> void:
	var bend := r.randf_range(-0.5, 0.5)
	var side := dir.orthogonal()
	for i in n:
		var t := pow(r.randf(), 1.4)
		var q := p + dir.rotated(bend * t) * t * length + side * r.randfn(0.0, 3.0 + 9.0 * t)
		g.pebbles.append(_pebble(r, q, lerpf(2.2, 1.0, t) * r.randf_range(0.5, 1.0)))


static func _pebble(r: RandomNumberGenerator, p: Vector2, size: float) -> Dictionary:
	var tone := r.randf()
	var col := Color(0.45, 0.42, 0.38).lerp(Color(0.74, 0.7, 0.62), tone)
	if r.randf() < 0.2:
		col = Color(0.3, 0.22, 0.15).lerp(Color(0.5, 0.36, 0.24), tone)
	return {"p": p, "r": Vector2(size, size * r.randf_range(0.65, 1.0)), "a": r.randf() * TAU, "c": col}


## How far p lies outside the plot (0 inside).
static func _rect_dist(p: Vector2, size: Vector2) -> float:
	return Vector2(maxf(0.0, maxf(-p.x, p.x - size.x)), maxf(0.0, maxf(-p.y, p.y - size.y))).length()


## Nothing on the bare ground round the entrance or the refuse pile, under a stone, or past the drawn garden.
static func _clear(g, sim, lo: Vector2, hi: Vector2) -> void:
	var stones := []
	for b in g.boulders:
		stones.append([b.p, float(b.r)])
	for rk in sim.rocks:
		stones.append([rk.pos, float(rk.r)])
	var ok := func(p: Vector2, nest: float, under: float) -> bool:
		if p.x < lo.x or p.y < lo.y or p.x > hi.x or p.y > hi.y:
			return false
		if p.distance_to(sim.nest_pos) < nest or p.distance_to(sim.midden_pos) < 30.0:
			return false
		for s in stones:
			if p.distance_to(s[0]) < s[1] * under:
				return false
		return true
	g.pebbles = g.pebbles.filter(func(e): return ok.call(e.p, 45.0 if e.r.x < 1.5 else NEST_CLEAR, 0.92))
	g.litter = g.litter.filter(func(e): return ok.call(e.p, NEST_CLEAR + 10.0, 0.9))
	g.tufts = g.tufts.filter(func(e): return ok.call(e.p, NEST_CLEAR, 0.9))
	g.rosettes = g.rosettes.filter(func(e): return ok.call(e.p, NEST_CLEAR + 10.0, 1.0))
	var moss := []
	for m in g.moss:
		var kept: Array = m.filter(func(b): return ok.call(b[0], NEST_CLEAR, 0.78))
		if not kept.is_empty():
			moss.append(kept)
	g.moss = moss
