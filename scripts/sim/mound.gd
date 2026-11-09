extends RefCounted
## The crater of soil round the nest entrance, as big as the soil the colony has dug out (v0.12.8, the keeper 2026-11-08:
## "the mound does not fit how much was dug"). One shape for the outworld's ground (shaders/terrain/ground_h.gdshaderinc,
## outworld_scene.ground_h) and the nest view's block top (nest_piles): a ring at r with a lower apron inside it, the
## entrance a pit in the middle. Units: model units = voxels = 1.5 mm.
## Volume: each pellet carried out is 1.5 voxels of soil (3 bites, 2 bites a voxel: nest_volume), heaped loose ~1.2 times
## its volume in the ground [inference: loose soil takes up more room than dug ground; ~1.2-1.3 for loam is the usual
## figure]; the slope of the ring's flank ~34 degrees, about the angle loose soil comes to rest at [general].
## (Until v0.12.8 it stopped growing at ~3 cm3 - a colony of 700 had dug ~50 cm3.)

const BULK := 1.2
const VOXELS_A_PELLET := 1.5
const C := 7.162                      # the shape's volume / (h r^2) (worked out numerically, without the pit)
const HOLE := Vector2(1.2, 3.0)       # the entrance's pit: no soil heaped within HOLE.x, all of it from HOLE.y


## [h, r]: the ring's height and radius for `pellets` carried out.
static func size(pellets: int) -> Vector2:
	var v := float(pellets) * VOXELS_A_PELLET * BULK
	var lo := 0.0
	var hi := 40.0
	for i in 40:
		var h := 0.5 * (lo + hi)
		var r := radius(h)
		if C * h * r * r > v:
			hi = h
		else:
			lo = h
	var h0 := maxf(0.25, lo)
	return Vector2(h0, radius(h0))


## The ring's radius for height h: as before v0.12.8 while it is small (3 + 2.2 h), then 3.56 h (the same shape scaled).
static func radius(h: float) -> float:
	return maxf(3.0 + 2.2 * h, 3.56 * h)


const PX := 3.0                       # simulation px a voxel (docs/ARCHITECTURE.md units)


## How far out (simulation px) a digger sets its pellet down, from a normal draw z (rng.randfn): about the ring's crest,
## spread a quarter of the radius either way, never in the entrance's pit (v0.12.10, the keeper 2026-11-08: the crater
## had grown to ~4 cm across while the diggers still dropped their soil 4.5-8 mm out, inside its inner slope).
## [Lasius niger carry each pellet out of the entrance and drop it at the crater's rim, where it rolls down the outside:
## field and keepers' observations, general; the quarter-radius spread is an inference to keep the ring's shape.]
static func drop_distance(pellets: int, z: float) -> float:
	var r := size(pellets).y * PX
	return maxf(HOLE.y * PX, r * (1.0 + 0.25 * z))


## Height of the heap at distance d from the entrance (without the pit itself, which the ground adds).
static func height(d: float, h: float, r: float) -> float:
	var k := (d - r) / (r * 0.6)
	return (h * exp(-k * k) + h * 0.5 * (1.0 - smoothstep(0.0, r, d))) * smoothstep(HOLE.x, HOLE.y, d)
