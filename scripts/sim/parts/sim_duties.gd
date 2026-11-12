extends "res://scripts/sim/parts/sim_colony.gd"
## Simulation, layer 10 of 11 (PART EA3a): duties in the nest. Every half hour of game time each worker inside is given
## a duty - feeding larvae, carrying brood, giving honeydew to a nestmate (giver and taker paired one by one),
## attending the queen, cleaning, digging, standing still or walking about - from the colony's needs, its task
## (sim_colony._colony) and its own leanings (Ant.threshold), drawing only on duty_rng (its own generator, seeded from the
## colony's and saved: see sim_state): so it is the same every run and goes on while the game is closed.
## Rates and where they come from: docs/BIOLOGY.md "เวรงานของมดในรัง".
## What the duties do: a larva grows only on the half hours it was fed (sim_colony._brood: Larva "f"); honeydew passes
## from crop to crop (Ant.crop, since v0.13.1); a queen nobody attends lays a little less (queen_tended). Protein stays
## the colony's. Each ant counts what it did (Ant.n_*) for top_ants().

const DUTY_EVERY := TPD / 48           # ticks: half an hour of game time
const DUTY_H := 0.5                    # hours in a duty round
const LARVAE_PER_FEEDER := 6           # larvae one nurse feeds in a round (the game's larvae_per_nurse; no figure for L. niger)
const QUEEN_FEEDS := 15.0              # a founding queen alone feeds this many larvae a round (fewer as her workers come)
const REST_SHARE := 0.4                # of the ants inside standing still, on an ordinary day ([ญาติ] 25-50%+, Temnothorax)
# cleaning: half of those neither resting nor at work ([ญาติ] ~15% of the time self-grooming, ~6% each other)
const GIVES := 3                       # nestmates one ant with a full crop feeds in a round
const ALLOGROOM_SHARE := 0.29         # of the cleaners, those cleaning a nestmate (6 of 15+6 [ญาติ], Bueno et al.)


## One duty round. Every ant inside gets a duty; outside it is D_OUT.
func _duties() -> void:
	var inside: Array = []
	for a in workers:
		if a.dead:
			continue
		a.partner = 0
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
	# (plain loops where filter/map lambdas were, the same lists in the same order and the same draws: v0.12.3)
	var free: Array = []
	for a in inside:
		if a.duty == -1:
			free.append(a)
	var k := REST_SHARE
	if daylight() < 0.15:
		k *= 1.3
	if climate.nest < 12.0:
		k *= 1.5
	if starving or hungry or satiated():
		k *= 1.25
	var n_rest := mini(roundi(free.size() * 0.8), roundi(minf(0.9, k) * inside.size()))     # (a few always about)
	# (as [-key, id, ant] sorted by the engine: ~4x faster than a sort_custom lambda, the same order - v0.12.2)
	var by_lazy: Array = []
	for a in free:
		by_lazy.append([-(a.threshold(Ant.TH_FORAGE) + duty_rng.randf() * 0.4), a.id, a])
	by_lazy.sort()
	for i in by_lazy.size():
		var a = by_lazy[i][2]
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
	var still: Array = []
	for a in inside:
		if a.duty == Ant.D_REST:
			still.append(a)
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
	var tasks := [Ant.TASK_NURSE, Ant.TASK_CALLOW, Ant.TASK_RESERVE, Ant.TASK_DIG]
	var by_task := [[], [], [], []]
	for a in inside:
		if a.duty == -1 or a.duty == Ant.D_DIG:
			var ti := tasks.find(a.task)
			if ti >= 0:
				by_task[ti].append(a)
	for some: Array in by_task:
		# keen nurses first, but not always the same ones (they take turns)
		var keen: Array = []
		for a in some:
			keen.append([-(a.threshold(Ant.TH_AGE) + duty_rng.randf() * 0.5), a.id, a])
		keen.sort()
		for x in keen:
			order.append(x[2])
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
	# the `want` free ones least reluctant to attend her (picked, not the whole lot sorted: v0.12.2), then diggers
	var want := clampi(roundi(inside.size() * 0.05), 2, 6)
	var can: Array = []                  # [threshold, ant], low to high
	var diggers := []
	for a in inside:
		if a.duty == Ant.D_DIG:
			diggers.append(a)            # (a digger comes over if nobody else is free)
		elif a.duty == -1:
			var t: float = a.threshold(Ant.TH_ATTEND)
			if can.size() == want and t >= can[want - 1][0]:
				continue
			var at := can.size()
			while at > 0 and can[at - 1][0] > t:
				at -= 1
			can.insert(at, [t, a])
			if can.size() > want:
				can.pop_back()
	var chosen := can.map(func(x): return x[1]) + diggers
	for i in mini(want, chosen.size()):
		if chosen[i].duty == Ant.D_DIG:
			chosen[i].dig_h -= DUTY_H
		chosen[i].duty = Ant.D_QUEEN
	queen_tended = not chosen.is_empty()


## Honeydew mouth to mouth (PART 0.13 step 2: real amounts, Ant.crop). What the foragers brought home since the last round
## (_pending_in) goes first, to the emptiest ants inside - a forager home with a load feeding a nestmate at the entrance;
## then the fullest crops feed the emptiest, a giver up to GIVES of them, each drop at most half the difference between
## the two crops and SHARE_ROOM of the taker's room (it is not filled at once: sim_crops). Every ant inside takes part,
## whatever its duty (a nurse is fed too); only the free ones are shown at it (D_FED, D_FEED_MATE) and counted.
## (L. niger: frequency, not size, of the exchanges sets how food spreads, and nest workers are go-betweens [Ln])
func _share_honeydew(inside: Array) -> void:
	if _pending_in <= 1e-9:
		# nothing at the entrance and the crops too even for a drop to pass: no sorting (most rounds in a settled colony)
		var lo := INF
		var hi := -INF
		for a in inside:
			lo = minf(lo, a.crop)
			hi = maxf(hi, a.crop)
		if (hi - lo) * SHARE_GAP < MIN_DROP:
			_unloaded.clear()
			_feed_from_fat(inside)
			return
	var order: Array = []                # the emptiest first (crop, then id: sorted by the engine)
	for a in inside:
		order.append([a.crop, a.id, a])
	order.sort()
	for i in order.size():
		order[i] = order[i][2]
	var cap := crop_cap()
	var ti := 0
	var fi := 0
	var by_id := _worker_map() if not _unloaded.is_empty() else {}
	while _pending_in > 1e-9 and ti < order.size():
		var t = order[ti]
		var room: float = (cap - t.crop) * SHARE_ROOM
		if room < MIN_DROP:
			break                        # (the rest are fuller still: it waits for the next round)
		var drop := minf(_pending_in, room)
		t.crop += drop
		_pending_in -= drop
		ti += 1
		var f = null                     # the forager who brought it (it may be out again by now)
		while f == null and fi < _unloaded.size():
			f = by_id.get(_unloaded[fi])
			fi += 1
			if f != null and (f.dead or f == t):
				f = null
		if f != null and t.duty == -1:
			t.duty = Ant.D_FED
			t.partner = f.id
			f.n_mates += 1
			harmony_n.fed += 1
			if f.duty == -1:
				f.duty = Ant.D_FEED_MATE
				f.partner = t.id
	_unloaded.clear()
	# ...and the fullest crops pass it on to the emptiest
	var gi := order.size() - 1
	while gi > ti:
		var g = order[gi]
		var gave := 0
		while gave < GIVES and ti < gi:
			var t = order[ti]
			var drop: float = minf((g.crop - t.crop) * SHARE_GAP, (cap - t.crop) * SHARE_ROOM)
			if drop < MIN_DROP:
				break
			g.crop -= drop
			t.crop += drop
			ti += 1
			gave += 1
			if t.duty == -1 and (g.duty == -1 or g.duty == Ant.D_FEED_MATE):
				t.duty = Ant.D_FED
				t.partner = g.id
				g.duty = Ant.D_FEED_MATE
				if g.partner == 0:
					g.partner = t.id
				g.n_mates += 1
				harmony_n.fed += 1
		if gave == 0:
			break                        # (the fullest left cannot feed the emptiest left: nobody can)
		gi -= 1
	_feed_from_fat(inside)


## When the crops have run dry, a worker with nothing left - crop and fat - is fed by the fattest nestmates from their
## body fat (inferred: the fluid ants pass mouth to mouth carries proteins and hormones, not only sugar [ญาติ: Camponotus
## floridanus, LeBoeuf et al. 2016 eLife 5:e20375] - that it comes from the giver's fat is not shown; the colony's fat fed
## every worker through v0.13.0). A giver keeps FAT_SPARE for itself and
## gives FAT_DROP at a time, up to GIVES nestmates a round. (Without it the young workers, who have no fat of their own
## yet, starved in late summer next to nestmates with fat to spare: 51 against 2 in 9 wild colonies over 3 years.)
func _feed_from_fat(inside: Array) -> void:
	var needy: Array = []
	for a in inside:
		if a.crop + a.body_fat < FAT_ASK:
			needy.append(a)
	if needy.is_empty():
		return
	var donors: Array = []               # the fattest first
	for a in inside:
		if a.body_fat > FAT_SPARE + FAT_DROP * 0.5:
			donors.append([-a.body_fat, a.id, a])
	donors.sort()
	var ni := 0
	for x in donors:
		var g = x[2]
		var k := 0
		while k < GIVES and ni < needy.size() and g.body_fat > FAT_SPARE:
			var t = needy[ni]
			var drop: float = minf(FAT_DROP, g.body_fat - FAT_SPARE)
			g.body_fat -= drop
			t.crop += drop
			fat -= drop
			sugar += drop
			ni += 1
			k += 1
			if t.duty == -1 and (g.duty == -1 or g.duty == Ant.D_FEED_MATE):
				t.duty = Ant.D_FED
				t.partner = g.id
				g.duty = Ant.D_FEED_MATE
				if g.partner == 0:
					g.partner = t.id
				g.n_mates += 1
				harmony_n.fed += 1
		if ni >= needy.size():
			break


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
