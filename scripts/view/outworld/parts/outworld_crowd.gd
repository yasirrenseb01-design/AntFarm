extends "res://scripts/view/outworld/parts/outworld_props.gd"
## Outworld view, between the props and the foragers: foragers kept from being drawn inside one another. The simulation
## steps each forager on its own (it never looks at the others' bodies), so where trails meet, at the entrance and round
## a drop of honey they would be drawn through each other. Each one drawn carries a small offset (Ant.voff, view only)
## that pushes it clear of its neighbours' bodies and eases back to where the simulation has it once there is room;
## one at the food is moved round the food's edge instead (the feeding pose faces the food from where it stands).
## Nothing here reaches the simulation: it stays deterministic.

const CROWD_CELL := 12.0               # px: the grid the neighbours are looked up in (an ant is ~9 px long)
const CROWD_R := 0.4                   # body half-width, model units (the gaster, BodyCheck.ANT_BODY)
const CROWD_BACK := -1.25              # its body from the gaster tip ...
const CROWD_FRONT := 0.8               # ... to the head, model units along its length
const CROWD_GAP := 0.25                # px of room kept between two bodies
const CROWD_MAX := 18.0                # px: never drawn further than this from where it walks (two body lengths)
const CROWD_K := 1.0                   # how much of an overlap is undone in one frame
const CROWD_BACK_RATE := 0.8           # 1/s: how fast the offset eases off when nothing pushes

var crowd := true                      # (dev --no-crowd: off, to compare)
var _frame_n := 0                      # frames drawn (who has which aphid: outworld_creatures._aphid_for)
var _aphids := {}                      # Vector2i(plant seed, aphid) -> [ant id, frame it last had it]


## One pass over every forager drawn last frame (its drawn transform, a.vxf): overlapping bodies are pushed apart.
## Moved: walkers and those at food; not those fighting, thrown, climbing a stem or the glass, or walking off the plot.
func _separate(delta: float) -> void:
	if not crowd:
		return
	var grid := {}
	var list := []
	for a in sim.outside:
		if a.state == Ant.IN_NEST or a.dead or a.vpos.x == INF or not (a.vxf is Transform3D):
			continue
		if a.act == 22 and a.busy > 0:
			continue                                   # (off past the edge of the plot)
		var xf: Transform3D = a.vxf
		if a.vfeed > 0.05 and a.vpose is Dictionary and (a.vpose as Dictionary).get("climb", false):
			continue                                   # up a stem, not on the ground
		var s: float = xf.basis.x.length()
		var o := Vector2(xf.origin.x, xf.origin.z) / U
		var f := Vector2(xf.basis.x.x, xf.basis.x.z).normalized()
		var k := s / U                                 # model units -> px
		var fixed: bool = (a.state == Ant.DEFEND and a.busy > 0) or a.vright > 0.0 or (a.busy > 0 and a.act == sim.ACT_WALL)
		var e := {"a": a, "p": o + f * CROWD_BACK * k, "q": o + f * CROWD_FRONT * k, "r": CROWD_R * k, "o": o,
			"fixed": fixed, "push": Vector2.ZERO}
		list.append(e)
		var cell := Vector2i(floori(o.x / CROWD_CELL), floori(o.y / CROWD_CELL))
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(e)
	for e in list:
		var c := Vector2i(floori(e.o.x / CROWD_CELL), floori(e.o.y / CROWD_CELL))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for g in grid.get(c + Vector2i(dx, dy), []):
					if g.a.id <= e.a.id:
						continue                       # (each pair once)
					var ab := _seg_closest(e.p, e.q, g.p, g.q)
					var d: Vector2 = ab[1] - ab[0]
					var pen: float = e.r + g.r + CROWD_GAP - d.length()
					if pen <= 0.0:
						continue
					var n: Vector2 = d.normalized() if d.length_squared() > 1e-6 else Vector2.from_angle(float(e.a.id - g.a.id))
					var we := 0.0 if e.fixed else 1.0
					var wg := 0.0 if g.fixed else 1.0
					if we + wg == 0.0:
						continue
					e.push -= n * pen * we / (we + wg)
					g.push += n * pen * wg / (we + wg)
	# and out of a drop of honey: one walking up to it is drawn at its edge, not in it (the simulation only knows it is
	# within reach of the centre)
	for f in sim.foods:
		var k := FoodKinds.info(f.kind)
		if k.get("feed_pose", "") != "rim":
			continue
		var fr: float = (3.0 + 7.0 * sqrt(clampf(f.amt / f.cap, 0.0, 1.0))) * 1.1
		var c := Vector2i(floori(f.pos.x / CROWD_CELL), floori(f.pos.y / CROWD_CELL))
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				for g in grid.get(c + Vector2i(dx, dy), []):
					if g.fixed or (g.a.vfood.x != INF and g.a.vfeed > 0.05):
						continue
					var cp := _seg_point(g.p, g.q, f.pos)
					var d: Vector2 = cp - f.pos
					var pen: float = fr + g.r - d.length()
					if pen > 0.0:
						g.push += (d.normalized() if d.length_squared() > 1e-6 else Vector2.RIGHT) * pen
	var ease := exp(-CROWD_BACK_RATE * delta)
	for e in list:
		var a = e.a
		var before: Vector2 = a.voff
		var at_food: bool = a.vfood.x != INF and a.vfeed > 0.05
		if at_food and a.vrim != INF:
			# round the food's edge: the push along it turns the ant about the food's centre
			var rad: Vector2 = e.o - a.vfood
			var R := maxf(rad.length(), 1.0)
			a.vrim = wrapf(a.vrim + (e.push as Vector2).dot(Vector2(-rad.y, rad.x) / R) * 0.6 / R, -PI, PI)
		a.voff = (a.voff + (e.push as Vector2) * CROWD_K) * (1.0 if at_food else ease)
		a.voff = a.voff.limit_length(CROWD_MAX)
		a.vdoff = (a.voff - before).length()


## The point of segment p-q closest to c.
static func _seg_point(p: Vector2, q: Vector2, c: Vector2) -> Vector2:
	var d := q - p
	var t := clampf((c - p).dot(d) / d.dot(d), 0.0, 1.0) if d.length_squared() > 1e-6 else 0.0
	return p + d * t


## The closest points of segments p1-q1 and p2-q2 (2D).
static func _seg_closest(p1: Vector2, q1: Vector2, p2: Vector2, q2: Vector2) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	var c := d1.dot(r)
	var b := d1.dot(d2)
	var den := a * e - b * b
	if den > 1e-6:
		s = clampf((b * f - c * e) / den, 0.0, 1.0)
	t = (b * s + f) / e if e > 1e-6 else 0.0
	if t < 0.0:
		t = 0.0
		s = clampf(-c / a, 0.0, 1.0) if a > 1e-6 else 0.0
	elif t > 1.0:
		t = 1.0
		s = clampf((b - c) / a, 0.0, 1.0) if a > 1e-6 else 0.0
	return [p1 + d1 * s, p2 + d2 * t]
