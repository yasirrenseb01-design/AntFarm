extends "res://scripts/sim/parts/sim_warmth.gd"
## Simulation, layer 8 of 11: the queen laying and the brood growing (eggs, larvae, cocoons, new workers);
## the colony limit (species "colony_max"); the workers in fixed orders (_ranked, from sim_colony in v0.14.1).
## Split from sim_colony.gd in v0.12.1.


const QUEEN_KEEP := 20.0     # body reserve a founding queen will not spend on brood
const FAT_READY := 0.6      # step 5: after midsummer a wild colony lays freely only with this much of a full fat cap for each
                             # worker, egg, larva and pupa (less fat, fewer eggs) - see _queen


func _queen(dt: float) -> void:
	if not queen.alive:
		return
	queen.starve = (queen.starve + dt * cold_factor(climate.nest)) if not queen_fed else maxf(0.0, queen.starve - dt)
	queen.dry = (queen.get("dry", 0.0) + dt) if humidity < 0.1 else maxf(0.0, queen.get("dry", 0.0) - dt)
	if queen.starve > sp["starve_days_queen"] or queen.dry > sp["starve_days_queen"] * 1.5:
		queen.alive = false
		var why := T.cause_starvation if queen.starve > sp["starve_days_queen"] else T.cause_thirst
		_log(T.queen_died, "bad", [L.k(why)])
		if String(queen.get("name", "")) != "":
			_log(T.named_queen_died, "named", [queen.name, L.k(why)])       # (the HUD: a chime, a banner)
		return
	if starving:
		return
	var cap: float = minf(sp["queen_eggs_max"], sp["queen_eggs_base"] + workers.size() * sp["queen_eggs_per_worker"]) * colony_trait("queen")
	# Workers regulate brood: the queen is fed less when there is more brood than the colony can rear.
	var brood := eggs.size() + larvae.size()
	var room := clampf(1.0 - float(brood) / (12.0 + workers.size() * 2.5), 0.0, 1.0)
	room *= clampf(float(nest.air) / target_air(), 0.3, 1.0)   # a cramped nest holds back laying
	# a founding queen makes her first eggs from her own body reserves
	var yolk := maxf(protein, 3.0 if (queen.reserve > QUEEN_KEEP and workers.size() < 5) else 0.0)
	var rate := cap * dev * clampf(yolk / 3.0, 0.0, 1.0) * room * (0.35 + 0.65 * float(queen.get("rested", 1.0)))
	if humidity < sp["humidity_ok_min"]:
		rate *= 0.3
	if winding_down() and workers.size() >= 5:
		rate = 0.0
	elif scenario == "wild" and doy_f() > 172.0 and workers.size() >= 5:
		# (PART 0.13 step 5) after midsummer a wild queen lays only as far as the colony's fat would carry
		# all it rears through the winter: eggs laid in July-August are workers in September, too late to fatten up
		# [chosen; v0.13.21 wild seed 22 grew 154 -> 285 workers in August, its fat ran out and 15 starved in spring]
		var will := float(workers.size() + eggs.size() + larvae.size() + pupae.size())
		rate *= clampf(fat / (will * sp["fat_cap_each"] * FAT_READY), 0.0, 1.0)
	if not queen_tended:
		rate *= UNTENDED_LAYING          # nobody attended her this half hour (parts/sim_duties.gd)
	var whole := workers.size() + brood + pupae.size() + alates.size()      # (all of them may yet become workers; the alates
	                                                                         # are the colony's until they fly)
	if demo_max > 0 and whole >= demo_max:
		rate = 0.0                       # the free demo: no more laying at its limit, again as ants die (game/demo.gd)
		if not stats.get("demo_told", false):
			stats["demo_told"] = true    # (said once a colony: else the keeper thinks it a fault)
			_log(T.demo_limit, "ok", [demo_max])
	var most: float = sp.get("colony_max", 2000.0)
	rate *= clampf((most - whole) / (most * 0.15), 0.0, 1.0)
	# (said once a colony for each limit: v0.14.1 raised it 1,000 -> 2,000, and a colony told at 850 is told again near
	# 1,700 - "near_cap" keeps the limit it was told of; the "near_limit" of older saves is left as it was)
	if whole >= most * 0.85 and float(stats.get("near_cap", 0.0)) < most:
		stats["near_cap"] = most
		var m := int(most)
		_log(T.colony_near_cap, "ok", ["%d,%03d" % [m / 1000, m % 1000] if m >= 1000 else str(m)])
	if workers.size() >= 5 and rate > 0.0:
		# (PART 0.13 step 4, R9) She lays as far as she is fed: each egg takes EGG_SUGAR from her crop beyond a day of her
		# own eating, and her attendants give her only what their crops hold above QUEEN_FROM (sim_duties._tend_queen) -
		# so a colony lays as its foraging fills the crops [Ln: the queen's food sets her laying; the figures chosen].
		# Through v0.13.20 the colony's stores and its income against its upkeep set it ("earning", and from v0.12.11
		# how long the stores would carry a shortfall). A founding queen makes her first eggs from her body (yolk, above).
		var want := rate * dt * EGG_SUGAR
		var got := minf(maxf(0.0, queen.crop - sp["sugar_queen"]), want)
		queen.crop -= got
		sugar -= got
		food_eaten += got
		rate *= got / want
	egg_acc += rate * dt
	while egg_acc >= 1.0 and workers.size() + eggs.size() + larvae.size() + pupae.size() < most:
		egg_acc -= 1.0
		eggs.append({"p": 0.0, "c": queen_at})
		protein = maxf(0.0, protein - sp["protein_egg"])
		_event("egg")
	egg_acc = minf(egg_acc, 1.0)         # (held back at the limit: no stored-up burst when room opens)


func _brood(dt: float) -> void:
	# (v0.14.1) dev_in worked out once a chamber for this tick, not once a brood: the same numbers - a colony of 2,000 has
	# ~2,800 brood in a few chambers
	_dev_c.clear()
	var k_egg: float = dt / sp["egg_days"]
	for i in range(eggs.size() - 1, -1, -1):
		var e: Dictionary = eggs[i]
		var at := int(e.get("c", -1))
		e.p += k_egg * _dev_once(at)      # (each at its own chamber's warmth)
		if e.p >= 1.0:
			eggs.remove_at(i)
			larvae.append({"p": 0.0, "h": 0.0, "q": 0.6, "c": at})

	var n := larvae.size()
	if n > 0:
		# larvae eat to grow, each as far as it was fed in the last duty round ("f"; parts/sim_duties.gd): one held still by
		# the cold barely feeds
		var each: float = sp["protein_larva"] * dt * clampf(dev, 0.1, 1.0)
		var cared := 0.0
		var fed_n := 0.0
		for l in larvae:
			var f := float(l.get("f", 1.0))
			fed_n += f
			cared += f * Alates.eat_k(l) if l.has("x") else f     # (a sexual larva eats more: sim/alates.gd)
		var need := each * cared
		if protein < need and queen.reserve > QUEEN_KEEP and workers.size() < 5:
			# the founding queen feeds her larvae from her own reserves (trophic eggs, saliva), but
			# keeps back enough body fat to see herself through the winter
			var give := minf(need - protein + 0.01, queen.reserve - QUEEN_KEEP)
			queen.reserve -= give
			protein += give
		var r := minf(1.0, protein / need) if need > 0.0 else 1.0       # (the protein there is, shared out)
		larva_fed = r * fed_n / n
		protein = maxf(0.0, protein - need * r)
		var hungriest := -1
		var worst: float = sp["larva_starve_days"]
		# late in the year the last larvae stop short of pupating and overwinter as larvae (diapause)
		var diapause := winding_down() or fridge_on
		var cold := clampf(dev * 2.0, 0.0, 1.0)          # a larva held still by the cold does not go hungry
		var r_all := r
		var k_larva: float = dt / sp["larva_days"]
		for i in range(n - 1, -1, -1):
			var l = larvae[i]
			r = r_all * float(l.get("f", 1.0))      # (a larva nobody fed this half hour: no growth, hungrier)
			l.p += k_larva * _dev_once(int(l.get("c", -1))) * r * (Alates.larva_k(l) if l.has("x") else 1.0)
			if diapause:
				l.p = minf(l.p, 0.95)
			l.h = maxf(0.0, l.h + dt * (1.0 - r) * cold - dt * r * 0.5)
			l.q = lerpf(l.get("q", 0.6), r, minf(1.0, dt * 0.6))   # running average of how well it was fed
			if l.p >= 1.0:
				larvae.remove_at(i)
				if l.has("x"):           # a gyne's or male's: a bigger cocoon (sim/alates.gd)
					pupae.append({"p": 0.0, "s": Alates.SIZE[l.x], "c": int(l.get("c", -1)), "x": l.x, "q": l.q})
				else:
					pupae.append({"p": 0.0, "s": _adult_size(l.q), "c": int(l.get("c", -1))})
				_event("pupate", pupae[-1].s)
				if hungriest > i:
					hungriest -= 1
				continue
			if l.h > worst:
				worst = l.h
				hungriest = i
		_cannibal_cd = maxf(0.0, _cannibal_cd - dt)
		if hungriest >= 0 and _cannibal_cd <= 0.0:
			# Starving colonies recycle brood: workers eat the weakest larva, a few per day.
			_cannibal_cd = 0.15
			larvae.remove_at(hungriest)
			protein += 0.3
			stats.cannibalized += 1
			if stats.cannibalized == 1 or stats.cannibalized % 10 == 0:
				_log(T.cannibalism, "bad", [stats.cannibalized])

	var k_pupa: float = dt / sp["pupa_days"]
	for i in range(pupae.size() - 1, -1, -1):
		var pupa: Dictionary = pupae[i]
		pupa.p += k_pupa * _dev_once(int(pupa.get("c", -1))) * (Alates.pupa_k(pupa) if pupa.has("x") else 1.0)
		if pupa.p >= 1.0:
			pupae.remove_at(i)
			if pupa.has("x"):
				Alates.eclose(self, pupa)
				continue
			if workers.is_empty():
				_log(T.first_worker, "ok")
			var nw := _new_worker(0.0)
			nw.size = pupa.get("s", 1.0)
			_event("eclose", nw.size)
			workers.append(nw)
			stats.born += 1
			harmony_n.born += 1
			if nw.size >= HARMONY_BIG:
				harmony_n.big += 1
			if stats.born <= 3 or stats.born % 25 == 0:
				_log(T.new_worker, "", [stats.born])

	# too hot where they lie (outdoors, a sun-baked top chamber the nurses have not cleared yet)
	var hot: float = sp["dev_lethal_c"] - 2.0
	if climate.nest > hot:
		var p := 0.4 * dt
		for list in [eggs, larvae, pupae]:
			for i in range(list.size() - 1, -1, -1):
				if chamber_temp(int(list[i].get("c", -1))) > hot and rng.randf() < p:
					list.remove_at(i)
					stats.brood_dead += 1
		_warn("heat", true, T.warn_heat)
	else:
		_warn("heat", false, "")


var _dev_c := {}           # chamber -> dev_in this colony tick (_brood)


func _dev_once(c: int) -> float:
	var d = _dev_c.get(c)
	if d == null:
		d = dev_in(c)
		_dev_c[c] = d
	return d


# ---------------------------------------------------------------- the workers in fixed orders (sim_colony uses them)
# (moved here from sim_colony.gd in v0.14.1: that file had grown past ~500 lines)

## The index in `pool` of the worker readiest for this kind of need (lowest threshold, then lowest id).
func _eagerest(pool: Array, kind: int) -> int:
	var best := 0
	for i in range(1, pool.size()):
		var t: float = pool[i].threshold(kind)
		var bt: float = pool[best].threshold(kind)
		if t < bt or (t == bt and pool[i].id < pool[best].id):
			best = i
	return best


# All the workers in two fixed orders, made again only when the workers change (born: appended; died: a new array).
# Thresholds never change, so this gives the orders sorting the reserve each time gave (v0.12.2: that sort was most of
# _colony's time in a colony of 1,000).
var _rank_of: Array = []
var _rank_n := -1
var _by_forage: Array = []            # eagerest foragers last: TH_FORAGE high to low, then id high to low
var _by_dig: Array = []               # readiest diggers first: TH_DIG low to high, then id low to high


func _ranked() -> void:
	if is_same(_rank_of, workers) and _rank_n == workers.size():
		return
	# (v0.14.1) only the workers born since put in their places, the dead taken out: the very orders the sort gives (each
	# a strict order: threshold, then id), without sorting the whole colony again at every birth - 0.19 ms a step at 2,000
	if _rank_in():
		return
	_rank_of = workers
	_rank_n = workers.size()
	for a in workers:
		a.sort_a = a.threshold(Ant.TH_FORAGE)
		a.sort_b = a.threshold(Ant.TH_DIG)
		a.sort_c = a.threshold(Ant.TH_AGE)
	_by_forage = workers.duplicate()
	_by_forage.sort_custom(func(x, y): return x.sort_a > y.sort_a or (x.sort_a == y.sort_a and x.id > y.id))
	_by_dig = workers.duplicate()
	_by_dig.sort_custom(func(x, y): return x.sort_b < y.sort_b or (x.sort_b == y.sort_b and x.id < y.id))


## _ranked's orders brought up to date in place: the workers are those ranked before (less the dead) and, at the end of
## `workers`, the newborn (never ranked: sort_a 0 - thresholds are 0.6-1.4). False (sort them all) when it is not so.
func _rank_in() -> bool:
	if _by_forage.is_empty() or _by_forage.size() != _by_dig.size():
		return false
	var k := workers.size()
	while k > 0 and workers[k - 1].sort_a == 0.0:
		k -= 1
	var born := workers.size() - k
	if born > 64:
		return false
	if _by_forage.size() + born != workers.size():
		_by_forage = _by_forage.filter(func(w): return not w.dead)
		_by_dig = _by_dig.filter(func(w): return not w.dead)
		if _by_forage.size() + born != workers.size() or _by_dig.size() != _by_forage.size():
			return false
	for i in range(k, workers.size()):
		var a: Ant = workers[i]
		a.sort_a = a.threshold(Ant.TH_FORAGE)
		a.sort_b = a.threshold(Ant.TH_DIG)
		a.sort_c = a.threshold(Ant.TH_AGE)
		_by_forage.insert(_by_forage.bsearch_custom(a, func(x, y): return x.sort_a > y.sort_a or (x.sort_a == y.sort_a and x.id > y.id)), a)
		_by_dig.insert(_by_dig.bsearch_custom(a, func(x, y): return x.sort_b < y.sort_b or (x.sort_b == y.sort_b and x.id < y.id)), a)
	_rank_of = workers
	_rank_n = workers.size()
	return true
