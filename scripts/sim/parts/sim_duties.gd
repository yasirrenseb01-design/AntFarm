extends "res://scripts/sim/parts/sim_colony.gd"
## Simulation, layer 6 of 7 (PART EA3a): duties in the nest. Every half hour of game time each worker inside is given
## a duty - feeding larvae, carrying brood, giving honeydew to a nestmate (giver and taker paired one by one),
## attending the queen, cleaning, digging, standing still or walking about - from the colony's needs, its task
## (sim_colony._colony) and its own leanings (Ant.threshold), drawing only on duty_rng (its own generator, seeded from the
## colony's and saved: see sim_state): so it is the same every run and goes on while the game is closed.
## Rates and where they come from: docs/BIOLOGY.md "เวรงานของมดในรัง".
## What the duties do: a larva grows only on the half hours it was fed (sim_colony._brood: Larva "f"); a nestmate given
## honeydew gets some strength back (Ant.energy); a queen nobody attends lays a little less (queen_tended). Food itself
## stays the colony's (sugar, protein, fat). Each ant counts what it did (Ant.n_*) for top_ants().

const DUTY_EVERY := TPD / 48           # ticks: half an hour of game time
const DUTY_H := 0.5                    # hours in a duty round
const LARVAE_PER_FEEDER := 6           # larvae one nurse feeds in a round (the game's larvae_per_nurse; no figure for L. niger)
const QUEEN_FEEDS := 15.0              # a founding queen alone feeds this many larvae a round (fewer as her workers come)
const REST_SHARE := 0.4                # of the ants inside standing still, on an ordinary day ([ญาติ] 25-50%+, Temnothorax)
# cleaning: half of those neither resting nor at work ([ญาติ] ~15% of the time self-grooming, ~6% each other)
const GIVES := 3                       # nestmates one ant with a full crop feeds in a round
const FED_ENERGY := 0.15               # strength a nestmate gets back from a drop of honeydew
const ALLOGROOM_SHARE := 0.29         # of the cleaners, those cleaning a nestmate (6 of 15+6 [ญาติ], Bueno et al.)


## One duty round. Every ant inside gets a duty; outside it is D_OUT.
func _duties() -> void:
	var inside: Array = []
	for a in workers:
		if a.dead:
			continue
		a.partner = 0
		a.sweet *= 0.7                   # (a crop shared on, or kept)
		if a.state == Ant.IN_NEST:
			inside.append(a)
			a.duty = -1
		else:
			a.duty = Ant.D_OUT
	# digging: those the colony has at the dig face (sim_colony: task TASK_DIG)
	for a in inside:
		if a.task == Ant.TASK_DIG:
			a.duty = Ant.D_DIG
			a.dig_h += DUTY_H
	_feed_larvae(inside)
	_carry_brood(inside)
	_tend_queen(inside)
	_share_honeydew(inside)
	# the rest: standing still (more at night, in the cold, when full - and when hungry: a starved L. niger colony is less
	# active in the nest [Ln]), the laziest first and the same ones again; some cleaning; the others walking about
	var free: Array = inside.filter(func(a): return a.duty == -1)
	var k := REST_SHARE
	if daylight() < 0.15:
		k *= 1.3
	if climate.nest < 12.0:
		k *= 1.5
	if starving or hungry or satiated():
		k *= 1.25
	var n_rest := mini(roundi(free.size() * 0.8), roundi(minf(0.9, k) * inside.size()))     # (a few always about)
	var by_lazy := free.map(func(a): return [a.threshold(Ant.TH_FORAGE) + duty_rng.randf() * 0.4, a])
	by_lazy.sort_custom(func(x, y): return x[0] > y[0])
	for i in by_lazy.size():
		var a = by_lazy[i][1]
		if i < n_rest:
			a.duty = Ant.D_REST
			a.rest_h += DUTY_H
		elif duty_rng.randf() < 0.5:
			a.duty = Ant.D_GROOM
		else:
			a.duty = Ant.D_IDLE
	_groom_mates(inside)


## Some of the cleaners clean a nestmate standing still rather than themselves ([ญาติ] ~6% of the time against ~15%:
## about 2 in 7): the groomer's partner is the one it licks, and that one's (D_REST) partner is its groomer.
func _groom_mates(inside: Array) -> void:
	var still: Array = inside.filter(func(a): return a.duty == Ant.D_REST)
	for a in inside:
		if a.duty != Ant.D_GROOM or still.is_empty() or duty_rng.randf() >= ALLOGROOM_SHARE:
			continue
		var r = still[duty_rng.randi() % still.size()]
		still.erase(r)
		a.partner = r.id
		r.partner = a.id


## Larvae are fed one by one, the hungriest first (hungry larvae are fed more often [ญาติ]): one feeding a round,
## LARVAE_PER_FEEDER to a nurse. Nurses first, then the newly emerged, then those resting inside, the diggers last (fire
## ants: below one worker per larva the larvae are fed less [ญาติ]). A larva's "f": fed this round (1) or not (0).
## (A hungry larva needing two feedings was tried: a protein shortage then left fewer larvae fed at all. The diggers
## help because v0.11.7 counted them in the care too.)
func _feed_larvae(inside: Array) -> void:
	if larvae.is_empty():
		return
	for l in larvae:
		l["f"] = 0.0
	var want := larvae.size()
	var order: Array = []
	for t in [Ant.TASK_NURSE, Ant.TASK_CALLOW, Ant.TASK_RESERVE, Ant.TASK_DIG]:
		var some: Array = inside.filter(func(a): return a.task == t and (a.duty == -1 or a.duty == Ant.D_DIG))
		# keen nurses first, but not always the same ones (they take turns)
		var keen := some.map(func(a): return [a.threshold(Ant.TH_AGE) + duty_rng.randf() * 0.5, a])
		keen.sort_custom(func(x, y): return x[0] > y[0])
		order += keen.map(func(x): return x[1])
	var feeds: Array = larvae.duplicate()
	feeds.sort_custom(func(x, y): return float(x.h) > float(y.h))
	var li := 0
	var given := 0
	# a founding queen with few or no workers feeds them herself (trophic eggs, saliva)
	if queen.alive and workers.size() < 15:
		var q := roundi(QUEEN_FEEDS * (1.0 - workers.size() / 15.0))
		while q > 0 and li < feeds.size():
			li = _feed_one(feeds, li)
			q -= 1
			given += 1
	for a in order:
		if given >= want or li >= feeds.size():
			break
		if a.duty == Ant.D_DIG:
			a.dig_h -= DUTY_H                # (it nursed this half hour instead)
		a.duty = Ant.D_FEED_LARVAE
		for i in LARVAE_PER_FEEDER:
			if li >= feeds.size():
				break
			li = _feed_one(feeds, li)
			a.n_larvae += 1
			given += 1


## One feeding to the larva at feeds[li]; returns the index of the next one to feed.
func _feed_one(feeds: Array, li: int) -> int:
	feeds[li].f = 1.0
	return li + 1


## The brood moved since the last round (eggs laid, larvae spinning, workers helped out of their cocoons) - by nurses.
func _carry_brood(inside: Array) -> void:
	if _carry_due <= 0:
		return
	var can: Array = inside.filter(func(a): return a.duty == -1 and a.task in [Ant.TASK_NURSE, Ant.TASK_CALLOW])
	if can.is_empty():
		can = inside.filter(func(a): return a.duty == -1)
	if can.is_empty():
		return                           # (nobody in to carry: still due next round)
	var carriers := mini(can.size(), ceili(_carry_due / 3.0))
	for i in carriers:
		var a = can[duty_rng.randi() % can.size()]
		can.erase(a)
		a.duty = Ant.D_CARRY
		var n := ceili(float(_carry_due) / (carriers - i))
		a.n_brood += n
		_carry_due -= n
	_carry_due = 0


## A few ants keep with the queen, those most drawn to her (no figure for ants; honey bees 6-10 [ญาติไกล]). A queen nobody
## attended lays a little less (the keeper's choice, no evidence either way).
func _tend_queen(inside: Array) -> void:
	queen_tended = true
	if not queen.alive or workers.is_empty():
		return                           # (a founding queen alone: nobody to attend her, and nothing lost by it)
	var can: Array = inside.filter(func(a): return a.duty == -1)
	can.sort_custom(func(x, y): return x.threshold(Ant.TH_ATTEND) < y.threshold(Ant.TH_ATTEND))
	can += inside.filter(func(a): return a.duty == Ant.D_DIG)          # (a digger comes over if nobody else is free)
	var want := clampi(roundi(inside.size() * 0.05), 2, 6)
	for i in mini(want, can.size()):
		if can[i].duty == Ant.D_DIG:
			can[i].dig_h -= DUTY_H
		can[i].duty = Ant.D_QUEEN
	queen_tended = not can.is_empty()


## Honeydew mouth to mouth: each forager home with honeydew feeds a nestmate; an ant with a full crop feeds up to GIVES, the
## weakest first; those fed pass on what they got next round (L. niger: frequency, not size, of the exchanges sets how
## food spreads, and nest workers are go-betweens [Ln]). The sugar itself is the colony's.
func _share_honeydew(inside: Array) -> void:
	var takers: Array = inside.filter(func(a): return a.duty == -1 and a.sweet <= 0.25)
	takers.sort_custom(func(x, y): return x.energy < y.energy or (x.energy == y.energy and x.id < y.id))
	var ti := 0
	# each load of honeydew brought home since the last round went first to a nestmate at the entrance (the forager may be
	# out again by now)
	var by_id := {}
	for a in workers:
		by_id[a.id] = a
	for fid in _unloaded:
		var f = by_id.get(fid)
		if f == null or f.dead or ti >= takers.size():
			continue
		var t = takers[ti]
		ti += 1
		t.duty = Ant.D_FED
		t.partner = f.id
		t.energy = minf(1.0, t.energy + FED_ENERGY)
		t.sweet = 1.0
		f.n_mates += 1
		if f.duty == -1:
			f.duty = Ant.D_FEED_MATE
			f.partner = t.id
	_unloaded.clear()
	# ...and those with a full crop pass it on
	var givers: Array = inside.filter(func(a): return a.sweet > 0.25 and a.duty == -1)
	givers.sort_custom(func(x, y): return x.sweet > y.sweet or (x.sweet == y.sweet and x.id < y.id))
	for g in givers:
		if ti >= takers.size():
			break
		if g.duty != -1:
			continue
		g.duty = Ant.D_FEED_MATE
		for k in GIVES:
			if ti >= takers.size() or g.sweet <= 0.25:
				break
			var t = takers[ti]
			ti += 1
			t.duty = Ant.D_FED
			t.partner = g.id
			if g.partner == 0:
				g.partner = t.id
			t.energy = minf(1.0, t.energy + FED_ENERGY)
			t.sweet = maxf(t.sweet, g.sweet * 0.5)
			g.sweet *= 0.7
			g.n_mates += 1


# ---------------------------------------------------------------- for the views and the star ants panel

const DUTY_NAMES := {Ant.D_OUT: "out", Ant.D_REST: "rest", Ant.D_FEED_LARVAE: "feed_larvae", Ant.D_CARRY: "carry_brood",
	Ant.D_FEED_MATE: "feed_mate", Ant.D_FED: "fed", Ant.D_QUEEN: "queen", Ant.D_GROOM: "groom", Ant.D_DIG: "dig",
	Ant.D_IDLE: "idle"}


## What a worker does this half hour: {"duty": Ant.D_*, "name": a key of DUTY_NAMES, "partner": a worker id or 0}; {} if
## it is not in the colony. (The nest view acts it out - round 2.)
func duty_of(id: int) -> Dictionary:
	for a in workers:
		if a.id == id and not a.dead:
			return {"duty": a.duty, "name": DUTY_NAMES.get(a.duty, "idle"), "partner": a.partner}
	return {}


## The first in each line of work, for the star ants panel (ui/parts/hud_stars.gd): one row per line,
## {"key", "title", "id" (worker id), "text"}; a line nobody has done yet is left out.
func top_ants() -> Array:
	var out := []
	if workers.is_empty():
		return out
	var lines := [
		["big", L.t("top_big"), func(w): return w.size, func(w): return L.f("top_big_text", [(w.size * 4.2)])],
		["small", L.t("top_small"), func(w): return -w.size, func(w): return L.f("top_small_text", [(w.size * 4.2)])],
		["old", L.t("top_old"), func(w): return w.age, func(w): return L.f("top_old_text", [int(w.age)])],
		["hurt", L.t("top_hurt"), func(w): return w.hurt, func(w): return L.f("top_hurt_text", [roundi(w.hurt * 100.0)])],
		["feed_larvae", L.t("top_feed_larvae"), func(w): return w.n_larvae, func(w): return L.f("top_feed_larvae_text", [w.n_larvae])],
		["carry_brood", L.t("top_carry_brood"), func(w): return w.n_brood, func(w): return L.f("top_carry_brood_text", [w.n_brood])],
		["feed_mates", L.t("top_feed_mates"), func(w): return w.n_mates, func(w): return L.f("top_feed_mates_text", [w.n_mates])],
		["rest", L.t("top_rest"), func(w): return w.rest_h, func(w): return L.f("top_rest_text", [int(w.rest_h)])],
		["dig", L.t("top_dig"), func(w): return w.dig_h, func(w): return L.f("top_dig_text", [int(w.dig_h)])],
		["sugar_trips", L.t("top_sugar_trips"), func(w): return w.n_sugar, func(w): return L.f("top_sugar_trips_text", [w.n_sugar])],
		["prey", L.t("top_prey"), func(w): return w.n_prey, func(w): return L.f("top_prey_text", [w.n_prey])],
		["corpses", L.t("top_corpses"), func(w): return w.n_corpses, func(w): return L.f("top_corpses_text", [w.n_corpses])],
		["fights", L.t("top_fights"), func(w): return w.n_fights, func(w): return L.f("top_fights_text", [w.n_fights])]]
	for line in lines:
		var score: Callable = line[2]
		var best = null
		var top := -INF
		for w in workers:
			if w.dead:
				continue
			var v: float = score.call(w)
			if v > top or (v == top and best != null and w.id < best.id):
				top = v
				best = w
		if best == null or (not (line[0] in ["big", "small", "old"]) and top <= 0.0):
			continue                         # (nobody has done it yet)
		if line[0] == "hurt" and top < 0.05:
			continue
		out.append({"key": line[0], "title": line[1], "id": best.id, "text": (line[3] as Callable).call(best)})
	return out
