extends "res://scripts/sim/parts/nest_chambers.gd"
## Underground nest, layer 5 of 6 (new in v0.12.21, PART 0.12 step 5d): more ways out. A big nest whose chambers lie far
## from its entrance digs a shaft up from one of them to the surface; dug through, it is an entrance as the first is -
## the steps to the way out run from it too (nest_voxels._bfs), a digger carries its soil out of the nearest
## (sim_surface), the crust may be broken round it (_hole_at).
## [inference: no count of entrances by colony size found for Lasius niger (docs/BIOLOGY.md, nest section, 2026-11-10).
## General accounts of ant nests give many small entrances; in Myrmica rubra medium colonies have several, which helps
## foraging. The numbers below are chosen, not measured. The user chose this, not told to the player (2026-11-10).]
## (Foragers come home to the nearest way in - sim_foragers._home_at: kept colonies past 300 workers grew 60-80% faster
## in their third year in 2 of 6 seeds, shorter trips with food; the user kept it, 2026-11-10.)
## Layers: parts/nest_voxels <- nest_ground <- nest_store <- nest_chambers <- nest_exits <- nest_volume.

const EXIT_WORKERS := 300          # workers before a nest digs another way out
const EXIT_MAX := 2                # ways out besides the entrance
const EXIT_FAR_STEPS := 60         # a chamber this many steps (voxels walked) from the nearest way out ...
const EXIT_FAR_FLAT := 30.0        # ... and this far across (voxels, 4.5 cm) from every one: one is dug up from it


func plan_chambers(brood: int, workers: int, target_air := 0) -> String:
	_plan_exits(workers)
	return super(brood, workers, target_air)


## Once a day (with the chamber plan): a way out being dug that has reached the surface is open; else, a nest big
## enough with a chamber far from every way out plans a shaft up from it (one at a time).
func _plan_exits(workers: int) -> void:
	if slab:
		return
	var digging := false
	for ex in exits:
		if not ex.open:
			if is_open(Vector3i((ex.b as Vector3).round())):
				ex.open = true
				exits_ver += 1
				_bfs()
			else:
				digging = true
	if digging or workers < EXIT_WORKERS or exits.size() >= EXIT_MAX:
		return
	var best = null
	var best_d := EXIT_FAR_STEPS
	for ch in chambers:
		if not ch.get("open", true):
			continue
		var c := Vector3i((ch.c as Vector3).round())
		if not inside(c) or rho[idx(c)] >= AIR or dist[idx(c)] < best_d:
			continue
		var flat := Vector2(ch.c.x - entrance.x, ch.c.z - entrance.z).length()
		for ex in exits:
			flat = minf(flat, Vector2(ch.c.x - ex.b.x, ch.c.z - ex.b.z).length())
		if flat < EXIT_FAR_FLAT:
			continue
		best = ch
		best_d = dist[idx(c)]
	if best == null:
		return
	# up from the chamber's ceiling, slanting a little its own way; not through a stone or a root, nor out past the box
	var a: Vector3 = (best.c as Vector3) + Vector3(0.0, chamber_axes(best).y * 0.8, 0.0)
	var lean := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 4.0)
	var b := Vector3(clampf(a.x + lean.x, x_lo + 3.0, nx - 4.0), ny - 1.0, clampf(a.z + lean.y, z_lo + 3.0, nz - 4.0))
	for k in 9:
		if hard_near(a.lerp(b, k / 8.0), 2.0):
			return
	exits.append({"a": a, "b": b, "open": false})


## Where the way out a digger at `cell` comes up through lies from the entrance, across (voxels; zero: the entrance) -
## the open one nearest it. (sim_surface: its worker comes out there and drops its pellet round it.)
func hole_off(cell: Vector3i) -> Vector2:
	var best := Vector2.ZERO
	var bd := Vector2(cell.x - entrance.x, cell.z - entrance.z).length()
	for ex in exits:
		if ex.open:
			var d := Vector2(cell.x - ex.b.x, cell.z - ex.b.z).length()
			if d < bd:
				bd = d
				best = Vector2(ex.b.x - entrance.x, ex.b.z - entrance.z)
	return best
