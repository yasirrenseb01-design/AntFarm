extends RefCounted
## Where on an enemy the ants hold on (v0.11.68, the keeper 2026-10-28: "most of them only circle round it, a few
## hold its legs - let them cover it, and pile up in layers when the colony is big").
## Each enemy kind lists spots in its STATS ("spots"): [x, y, h, pitch] in its own frame - x px forward, y px to one
## side (mirrored to the other; y = 0 once), h mm the height of the ant's feet there (on a leg, up its side, on its
## back), pitch how far the ant is tilted head-up there (climbing its side). Spot i of layer k is index k * n + i; an ant
## in layer k > 0 stands on the nestmate holding the spot under it.
## Evidence and inference (docs/BIOLOGY.md "รุมศัตรู"): Lasius niger mobs and bites intruders and predators at its aphids
## and recruits nestmates to prey with alarm and trails [Ln]; holding prey by the limbs and stretching it out is
## documented in other ants (Crematogaster, Azteca, Pheidole) [other ants]; ants over the whole body and in layers in a
## big colony [inference].

const LAYER_MM := 1.3          # a worker's body height: the next layer's feet stand this much higher
const SEEK_PX := 40.0          # px beyond its reach an ant answering the alarm starts picking a free spot

static var _cache := {}


## The spots of this enemy kind, both sides: [{p: Vector2 px, h: mm, pitch, face: angle to look along}].
static func spots(K) -> Array:
	if _cache.has(K.NAME):
		return _cache[K.NAME]
	var out := []
	for s in K.STATS.spots:
		for side in ([1.0, -1.0] if absf(s[1]) > 0.01 else [1.0]):
			var p := Vector2(s[0], s[1] * side)
			# facing the body's midline (or along it, on the midline)
			var face := (Vector2(p.x * 0.7, 0.0) - p).angle() if absf(p.y) > 1.0 else (PI if p.x > 0.0 else 0.0)
			out.append({"p": p, "h": float(s[2]), "pitch": float(s[3]), "face": face})
	_cache[K.NAME] = out
	return out


## How many layers of ants an enemy can carry: one in a young colony, two from 120 workers, three from 400
## [inference: piling up needs more ants than there is room for, and a big colony sends that many].
static func layers(workers: int) -> int:
	return 1 + (1 if workers >= 120 else 0) + (1 if workers >= 400 else 0)


## Spot index i (any layer) where it is now, in the outworld (px).
static func at(c: Dictionary, K, i: int) -> Vector2:
	var sp: Array = spots(K)
	return c.pos + (sp[i % sp.size()].p as Vector2).rotated(c.ang)


## The free spot nearest `from` in the lowest layer that has one (a spot above one only when the one under it is held),
## or -1. `taken`: spot index -> ant id.
static func free_spot(c: Dictionary, K, taken: Dictionary, from: Vector2, n_layers: int) -> int:
	var sp: Array = spots(K)
	var n := sp.size()
	var local: Vector2 = (from - c.pos).rotated(-c.ang)
	for k in n_layers:
		var best := -1
		var bd := INF
		for j in n:
			var i := k * n + j
			if taken.has(i) or (k > 0 and not taken.has(i - n)):
				continue
			var d: float = local.distance_squared_to(sp[j].p)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			return best
	return -1


## For the view: [feet height in mm, head-up tilt, facing] of the ant holding spot i.
static func pose(c: Dictionary, K, i: int) -> Array:
	var sp: Array = spots(K)
	var s: Dictionary = sp[i % sp.size()]
	return [s.h + LAYER_MM * float(i / sp.size()), s.pitch, c.ang + s.face]
