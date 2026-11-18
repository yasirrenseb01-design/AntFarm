extends RefCounted
## The queen's walks about her chamber between her moments (nest_lifecycle._queen_roam): where to, and her body on top of
## the brood she walks over. `nv` is the nest view.

const NEAR := 3.0                     # voxels: never a walk shorter than this (she shifted ~3 voxels a walk, about 4.5 mm)
const FAR_SHARE := 0.55               # the spot is picked among those at least this share of the farthest one away
const FRONT := [Vector3(1.1, -0.02, 0.0), Vector3(0.4, 0.0, 0.0), Vector3(0.4, 0.0, 0.3), Vector3(0.4, 0.0, -0.3)]
const RISE := 3.0                     # voxels a second she climbs onto the brood (her lift eased so; she walks 2.5)
const SINK := 1.2                     # and down off it
const AHEAD := 0.9                    # voxels: the brood under where each foot will be this far on counts already (rising
                                      # only once a foot was over it, a foot went into a larva for ~half a second)
const MOST := 1.6                     # voxels: no higher than this over what is under her (a heap of cocoons: round it)


## Where she walks to next: any spot of her chamber's floor with room for her all round, not on the brood, and well across
## it - the far side of the chamber as often as the near (the keeper, 2026-11-18: "walk farther, over the brood too"; the
## spots within 1.5-6 voxels kept her walks to 3 voxels, ~4.5 mm, by the brood she lay beside). Vector3.INF: none.
## [Inference: no measure of how far a Lasius niger queen walks about her chamber was found; queens of founding and young
## colonies are seen walking over and among their brood in observation nests.]
static func goal(nv, here: Vector3, spots: Array) -> Vector3:
	var cands := []
	var far := 0.0
	for sp in spots:
		var d := (sp as Vector3).distance_to(here)
		if d < NEAR or nv._brood_cells.has(Vector3i(roundi(sp.x), roundi(sp.y), roundi(sp.z))):
			continue
		# (room for her all round: her gaster is long and turned any way - by a wall it lay in the soil)
		var clear := true
		for o in [Vector3(1.6, 0.6, 0), Vector3(-1.6, 0.6, 0), Vector3(0, 0.6, 1.6), Vector3(0, 0.6, -1.6), Vector3(1.1, 0.6, 1.1),
				Vector3(-1.1, 0.6, 1.1), Vector3(1.1, 0.6, -1.1), Vector3(-1.1, 0.6, -1.1)]:
			if nv._density_at((sp as Vector3) + o) >= 0.5:
				clear = false
				break
		if clear:
			cands.append([d, sp])
			far = maxf(far, d)
	cands = cands.filter(func(c): return c[0] >= maxf(NEAR, far * FAR_SHARE))
	if cands.is_empty():
		return Vector3.INF
	return cands[randi() % cands.size()][1]


## Her six feet, front, middle and hind, left and right (model units: the lowest points of her legs in queen_hi.antmesh).
const FEET := [Vector3(0.93, -0.02, 1.11), Vector3(0.93, -0.02, -1.11), Vector3(0.03, -0.02, 1.11), Vector3(0.03, -0.02, -1.11),
	Vector3(-0.91, -0.02, 1.11), Vector3(-0.91, -0.02, -1.11)]
static var drawn_from := [Transform3D(), -1]   # (dev/queen_check.gd: how she was before this lift, and the frame)
const TILT := 0.35                    # radians: tipped front-back or side to side at most on the brood
const TILT_V := 0.7                   # radians a second she tips at most (at 1.5 her body turned over 3 degrees a frame twice as often)


## Walking over brood: her body raised onto it - each foot on what lies under it, not in it - and tipped front or back and
## side to side as the brood under her feet asks; and her gaster and head clear of it (eggs, larvae and cocoons are firm
## enough to step on: nest_bodies._brood_top - a worker crossing the pile walks on top of it too). Her legs are drawn
## straight from her body, not reaching down: a foot over the floor beside the brood stands off it, as on a step (her feet
## went into the larvae she walked over, the body above them: the keeper, 2026-11-18). `was`: her lift (voxels), tilt
## front-back and side to side (radians) last frame, eased toward the new; she is drawn so (nv._queen_xf and her
## instance). Not walking: back to none.
static func over(nv, was: Vector3, dt: float) -> Vector3:
	if nv._queen_path.is_empty() or nv._queen_mm.instance_count == 0:
		return Vector3.ZERO
	dt = minf(dt, 0.05)                 # (a slow frame: no jump up or down)
	var xf: Transform3D = nv._queen_xf
	drawn_from = [xf, Engine.get_process_frames()]
	var up: Vector3 = xf.basis.y.normalized()
	if up.y < 0.7:
		return was.move_toward(Vector3.ZERO, SINK * dt)       # (down a shaft's wall: no brood there)
	var h := []
	var fwd: Vector3 = xf.basis.x.normalized()
	for f in FEET:
		var w: Vector3 = xf * (f as Vector3)
		h.append(maxf(nv._brood_top(w), nv._brood_top(w + fwd * AHEAD)))
	var want := Vector3.ZERO
	var body := maxf(_need(nv, xf, FRONT), _need(nv, xf, nv.QUEEN_UNDER_TAIL))
	if h.max() > 0.02 or body > 0.0:
		var s: float = nv.queen_scale
		var fr := maxf(h[0], h[1])
		var hi := maxf(h[4], h[5])
		var pos := maxf(maxf(h[0], h[2]), h[4])
		var neg := maxf(maxf(h[1], h[3]), h[5])
		want.y = clampf(atan2(fr - hi, 1.84 * s), -TILT, TILT)      # (front up: + round her side)
		want.z = clampf(atan2(neg - pos, 2.22 * s), -TILT, TILT)                       # (her +z side up: -)
		# then up so far that every foot is on the top of its brood once tipped (her feet stand ~0.3 voxels off a bare floor
		# as she walks: raised by the brood's whole height she went up into a low chamber's roof)
		var tipped := _tipped(xf, want)
		var lift := 0.0
		for i in FEET.size():
			var f0: Vector3 = xf * (FEET[i] as Vector3)
			var f1: Vector3 = tipped * (FEET[i] as Vector3)
			lift = maxf(lift, nv._floor_cached(f0) + float(h[i]) + 0.03 - f1.y)
		var t2 := Transform3D(tipped.basis, tipped.origin + up * lift)
		lift += maxf(0.0, maxf(_need(nv, t2, FRONT), _need(nv, t2, nv.QUEEN_UNDER_TAIL)))
		want.x = minf(lift, MOST)
		want *= _room_for(nv, xf, want)
	var now := Vector3(move_toward(was.x, want.x, (RISE if want.x > was.x else SINK) * dt), move_toward(was.y, want.y, TILT_V * dt),
		move_toward(was.z, want.z, TILT_V * dt))
	if now.length_squared() > 0.000001:
		var t := _tipped(xf, now)
		nv._queen_xf = Transform3D(t.basis, t.origin + up * now.x)
		nv._queen_mm.set_instance_transform(0, nv._queen_xf)
	return now


## Her back and sides, head to gaster tip (model units: dev/queen_check.gd BODY).
const HULL := [Vector3(1.25, 0.15, 0.0), Vector3(0.9, 0.3, 0.3), Vector3(0.9, 0.3, -0.3), Vector3(0.3, 0.2, 0.35),
	Vector3(0.3, 0.2, -0.35), Vector3(0.3, 0.6, 0.0), Vector3(-0.7, 0.1, 0.5), Vector3(-0.7, 0.1, -0.5),
	Vector3(-1.3, 0.05, 0.6), Vector3(-1.3, 0.05, -0.6), Vector3(-1.3, 0.65, 0.0), Vector3(-2.2, 0.15, 0.0)]


## How much of the lift and tilt `want` the chamber has room for (1 all, 0 none): no more of her body in the soil than
## standing on the floor - raised onto larvae in a low chamber her gaster went into its roof (gaster top in the soil 22%
## of the frames walking, 2% before; --queen-walk).
static func _room_for(nv, xf: Transform3D, want: Vector3) -> float:
	var up: Vector3 = xf.basis.y.normalized()
	var n0 := _in_soil(nv, xf)
	var k := 1.0
	while k > 0.05:
		var t := _tipped(xf, want * k)
		if _in_soil(nv, Transform3D(t.basis, t.origin + up * want.x * k)) <= n0:
			return k
		k -= 0.2
	return 0.0


static func _in_soil(nv, xf: Transform3D) -> int:
	var n := 0
	for p in HULL:
		if nv._density_at(xf * (p as Vector3)) >= 0.5:
			n += 1
	return n


## Her transform tipped front-back (y) and side to side (z) about her middle.
static func _tipped(xf: Transform3D, a: Vector3) -> Transform3D:
	var b: Basis = Basis(xf.basis.x.normalized(), a.z) * (Basis(xf.basis.z.normalized(), a.y) * xf.basis)
	return Transform3D(b, xf.origin)


## How far the points (her model's units) are below the top of the floor and the brood under them, the most of them.
static func _need(nv, xf: Transform3D, pts: Array) -> float:
	var need := -INF
	for lp in pts:
		var w: Vector3 = xf * (lp as Vector3)
		need = maxf(need, nv._floor_cached(w) + nv._brood_top(w) + 0.04 - w.y)
	return need
