extends RefCounted
## The colony's toilets: where its workers defecate inside the nest (PART 0.13 step 7).
## Evidence [Ln] (Czaczkes, Heinze & Ruther 2015, PLoS ONE 10:e0118376 - 21 lab nests of 150-300 L. niger workers,
## 2 months, fed dyed sugar water and a protein food of another colour): every nest had 1-4 well-defined dark patches
## (mean 2.32, median 2), always the colour of the sugar water and never of the protein; 34 of the 41 in a corner of a
## chamber; a dark mud-like substance in the middle of the bigger ones; never any food remains, debris or dead ants (those
## went to refuse piles outside, sim.midden_pos); the ants did not avoid them, and often clustered on them. Made even
## with many chambers unused. Defecating itself was not seen: inferred from the colour and the mud.
## Here [chosen / inference, docs/biology/toilets.md]: what the workers eat while in the nest (honeydew, from their crops
## or their fat - sim_colony._metabolism) is counted as waste; once the colony has eaten FIRST_AT inside, the first toilet
## is made in a chamber corner, more (up to 4, about one for each two chambers) as the waste mounts; each duty round the
## waste of that half hour goes to them, more to the bigger ones (by the square root: the ants seek out a toilet in use).
## A chamber widened round one (its corner now open floor) leaves that patch as it is and starts a new one in the
## nearest corner of the same chamber. The queen's and the larvae's waste are not counted (larvae keep theirs in the
## meconium, thrown out with the cocoon: the paper). Nothing in the colony depends on them: they are drawn
## (view/nest/parts/nest_care.gd). Draws nothing from the random generators.

const FIRST_AT := 8.0           # units eaten inside before the first toilet (a 14-worker nest: ~2 weeks) [chosen]
const NEXT_AT := 60.0           # and each next one after this much more again x its number [chosen]
const MAX_N := 4                # toilets in use at most (the paper: 1-4)
const MAX_KEPT := 10            # patches kept with the old ones left behind (the smallest old one goes first)
const CHAMBERS_EACH := 2.0      # one toilet for each this many chambers (the paper: 2.32 in 5 cavities) [chosen]
const PULL := 4.0               # units: a new toilet's start; the waste goes by the square root of what each holds, so
                                # the bigger draw more but a new one still grows (a share by the amount itself left new
                                # ones at a few units beside one of hundreds) [chosen]
const CORNER := 4               # of the 8 cells round a floor cell at its height at least this many soil (two walls)

var due := 0.0                  # waste since the last duty round (units eaten inside)
var total := 0.0                # all the waste ever, the toilets' and what was waiting
var patches: Array = []         # [{"c": Vector3i floor cell, "amt": units, "ch": chamber index, "old": no longer used}]


## Called every duty round: a new toilet if one is due, then this round's waste shared out.
func round_done(nest, busy_rooms: Array = []) -> void:
	if due <= 0.0:
		return
	total += due
	# a corner the ants have dug away round: the patch stays, the toilet moves to the nearest corner of that chamber
	for p in patches.duplicate():
		if not p.old and _score(nest, p.c) < CORNER:
			var q = _corner_in(nest, int(p.ch), p.c)
			if q != null and Vector3(q - (p.c as Vector3i)).length() <= 2.5:
				p.c = q                       # (a step or two: the same patch, its edge where the wall was)
				continue
			p.old = true
			if q != null:
				patches.append({"c": q, "amt": 0.0, "ch": int(p.ch), "old": false})
	var used := patches.filter(func(p): return not p.old)
	var want := mini(MAX_N, maxi(1, roundi(nest.chambers.size() / CHAMBERS_EACH)))
	var need_more: float = FIRST_AT + NEXT_AT * used.size() * used.size()
	if used.size() < want and total >= need_more:
		var p = _new_spot(nest, busy_rooms)
		if p != null:
			patches.append(p)
			used.append(p)
	while patches.size() > MAX_KEPT:
		var worst := -1
		for i in patches.size():
			if patches[i].old and (worst < 0 or float(patches[i].amt) < float(patches[worst].amt)):
				worst = i
		if worst < 0:
			break
		patches.remove_at(worst)
	if used.is_empty():
		due = 0.0
		return                        # (none yet: the waste of the first days is in `total` only)
	var w := 0.0
	for p in used:
		w += sqrt(float(p.amt) + PULL)
	for p in used:
		p.amt = float(p.amt) + due * sqrt(float(p.amt) + PULL) / w
	due = 0.0


## How enclosed a floor cell is: soil cells among the 8 round it at its height; -1 if it is no floor cell (open, soil
## under it) with open space over it (a cell under the wall's overhang, its ceiling a step up, scored high and was
## hidden from every side: the patch could not be seen) or if it is a hole in the wall (7-8).
func _score(nest, q: Vector3i) -> int:
	if not nest.is_open(q) or nest.is_open(q + Vector3i.DOWN) or not nest.inside(q + Vector3i.DOWN) \
			or not nest.is_open(q + Vector3i.UP) or not nest.is_open(q + Vector3i.UP * 2):
		return -1
	var s := 0
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if (dx != 0 or dz != 0) and not nest.is_open(q + Vector3i(dx, 0, dz)):
				s += 1
	return s if s < 7 else -1


## The most enclosed floor cell of chamber i (nearest `near` among the equally good ones, when given), or null.
## Ties go to the lowest coordinates: the same every run.
func _corner_in(nest, i: int, near := Vector3i(-99999, 0, 0)):
	if i < 0 or i >= nest.chambers.size():
		return null
	var ch: Dictionary = nest.chambers[i]
	var c: Vector3 = ch.c
	var r: float = float(ch.get("r", 3.0))
	var best := Vector3i(-1, -1, -1)
	var best_k := -INF
	var reach := ceili(r * 1.6)
	for y in range(floori(c.y - r) - 1, ceili(c.y) + 1):
		for z in range(floori(c.z) - reach, ceili(c.z) + reach + 1):
			for x in range(floori(c.x) - reach, ceili(c.x) + reach + 1):
				if Vector2(x - c.x, z - c.z).length() > r * 1.6:
					continue
				var q := Vector3i(x, y, z)
				var s := _score(nest, q)
				if s < CORNER:
					continue
				# the most enclosed; given `near`, a near corner rather (a step away costs one cell of enclosure)
				var k := float(s) - (Vector3(q - near).length() if near.x > -99999 else 0.0)
				if k > best_k:
					best_k = k
					best = q
	return best if best_k > -INF else null


## A corner of a chamber without a toilet in use. Chambers in order: the biggest first; the one the queen or the brood
## is kept in (busy_rooms, now) only in a one-chamber nest [chosen: the paper could not tell where the brood lay; drawn
## there, the patch was under the crowd round her].
func _new_spot(nest, busy_rooms: Array):
	var has := {}
	for p in patches:
		if not p.old:
			has[int(p.ch)] = true
	var order := []
	for i in nest.chambers.size():
		var ch: Dictionary = nest.chambers[i]
		if has.has(i) or not ch.get("open", true):
			continue
		var busy: int = 1 if i in busy_rooms else 0
		if busy == 1 and nest.chambers.size() > 1:
			continue                  # (where the queen or the brood is kept only while there is no other)
		order.append([busy, -float(ch.get("r", 3.0)), i])
	order.sort()
	for o in order:
		var q = _corner_in(nest, o[2])
		if q != null:
			return {"c": q, "amt": 0.0, "ch": o[2], "old": false}
	return null


## The nest's block moved (sim._nest_in_tank): the toilets with it.
func shift(dx: int, dz: int) -> void:
	for p in patches:
		p.c = (p.c as Vector3i) + Vector3i(dx, 0, dz)


func to_save() -> Dictionary:
	var ps := []
	for p in patches:
		var c: Vector3i = p.c
		ps.append([c.x, c.y, c.z, float(p.amt), int(p.ch), 1 if p.old else 0])
	return {"due": due, "total": total, "patches": ps}


## From a save (none before v0.13.24: no toilets yet, they come as the colony eats). A file anyone could change: only
## rows of six numbers are taken, at most MAX_KEPT.
func from_save(d) -> void:
	due = 0.0
	total = 0.0
	patches = []
	if not d is Dictionary:
		return
	for k in ["due", "total"]:
		var v = d.get(k, 0.0)
		if v is float or v is int:
			set(k, maxf(0.0, float(v)))
	var ps = d.get("patches", [])
	if not ps is Array:
		return
	for r in ps:
		if patches.size() >= MAX_KEPT or not r is Array or r.size() != 6:
			continue
		var ok := true
		for v in r:
			ok = ok and (v is int or v is float)
		if ok:
			patches.append({"c": Vector3i(int(r[0]), int(r[1]), int(r[2])), "amt": maxf(0.0, float(r[3])), "ch": int(r[4]),
				"old": int(r[5]) != 0})
