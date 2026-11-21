extends RefCounted
## The winged sexuals - new queens (gynes) and males - of a grown wild colony (PART 0.14 step 1). Static, given the
## simulation: called from sim_colony._new_day (the spring choice, the winters), sim_brood._brood (their larvae and
## pupae), sim_duties._duties (fed by the workers) and sim_colony._colony (their days in the nest, the flight).
## Biology and sources: docs/biology/alates.md ([A1]-[A9]); the plan and the keeper's choices: docs/roadmap/PLAN_0.14.md.
## Labels: [A1] etc. = evidence, [inference], [chosen] = a game value with no figure behind it, [keeper] = the keeper's
## decision (2026-11-18).
##
## The year: in autumn the queen's last eggs overwinter as larvae (sim_brood: diapause) [A1]. On CHOOSE_DOY (late
## March, when sexual larvae begin to grow [A1]) a colony big and old enough turns some of those larvae into gyne or
## male larvae ("x" = "g" / "m"), as many as ALATE_SHARE of last year's food buys. They eat more and grow longer than a
## worker's larvae, spin bigger cocoons and come out as alates in the nest (s.alates) in June; the workers feed them,
## the gynes fatten up [A3]; on a warm afternoon in July-August they fly (_fly) and are gone from the colony.
## Keeper colonies (indoor tanks) make none in 0.14 [keeper] - every function here does nothing for them.

const AUTUMN_DOY := 225          # 13 August: the queen of a colony that will make alates lays its autumn batch - most eggs
                                  # are laid early in autumn and winter as larvae [A1, Forel 1920]; the day chosen
const AUTUMN_MORE := 1.3          # eggs in the batch: the alates next year's spend would buy / LARVAE_MOST, x this [chosen:
                                  # some die over the winter]
const CHOOSE_DOY := 80            # 21 March: overwintered sexual larvae begin to grow late March [A1, Lausanne]
const WORKERS_K := 0.5            # workers >= half the colony limit (1,000 of 2,000) [keeper; keepers' forums say ~1,000 A9]
const WINTERS := 2                # and two winters behind it [keeper; colonies 2-3 years old, A9]
const ALATE_SHARE := 0.125        # of last year's food (loads brought home) spent on alates [keeper: 10-15%; no figure, A9]
const LARVAE_MOST := 0.6          # at most this share of the overwintered larvae become sexuals (the rest workers) [chosen]
# What one alate holds when it flies, in food units (a worker's larva eats ~3.8: protein 0.25 + sugar 0.04 a day for
# 13 days at full warmth). A male is 4.4-4.6 mm long as it pupates, a worker 2.9-3.6 [A1]: by volume (length cubed)
# ~2.6 workers -> ~10 units [inference]; a gyne costs 7.66 males [A1 from A2: energy 689 J against 90 J, A3].
const MALE_COST := 10.0
const GYNE_COST := MALE_COST * 7.66
# How the investment is split: gynes 13-14% of the alates by number [A1/A2] = about even in cost (0.14 x 7.66 : 0.86).
const GYNE_SPEND := 0.55          # share of the spend on gynes in a full year -> ~14% of the alates gynes
const GYNE_SPEND_FIRST := 0.1     # a colony's first year of alates: mostly males [keepers, A9; the share chosen]
# Their larvae: eat x a worker larva a day, take x its days: male 2.1 x 1.25 x 3.77 = ~10 units, gyne 3.25 x 1.6 x 3.77
# = ~19.6 - a quarter of what she holds at flight: she comes out at ~4 mg and flies at ~15.5 [A3]. The days chosen so
# they pupate by about the end of May in the game's spring [A1: all by 22 May] and come out from late June [keepers,
# A9]; v0.14.2 testing with 1.6 / 2.0 (and 1.15 / 1.3 for the cocoons): pupated mid- to late June, out from 5 July.
const EAT := {"m": 2.1, "g": 3.25}
const LARVA_DAYS := {"m": 1.25, "g": 1.6}
const PUPA_DAYS := {"m": 1.0, "g": 1.15}       # longer in the bigger cocoons [inference; no figure]
const SIZE := {"m": 1.07, "g": 1.8}            # body length / a 4.2 mm worker: male ~4.5 mm, gyne ~7.5 mm [A1] (the views)
# In the nest: a male stays at ~0.9 mg [A3] and eats as a big worker; a gyne fattens to GYNE_COST over FATTEN_DAYS
const UPKEEP := {"m": 1.5, "g": 2.0}           # x a worker's sugar a day [inference: bigger bodies]
const FATTEN_DAYS := 21.0                      # [inference: "weeks in the nest before the flight" - no figure, alates.md]
const READY_DAYS := 10.0                       # days out of the cocoon before an alate will fly [inference]
const GYNE_READY := 0.85                       # and a gyne not before she holds this share of GYNE_COST, or 30 days out
                                               # [A3: they fatten in the nest before the flight; the share chosen]
const FROM_KEEP := 0.3                         # a worker gives an alate only what its crop holds above this share [chosen,
                                               # as it gives the queen: sim_crops QUEEN_FROM]
# The flight [A4][A5][keepers]: July to August, afternoon to evening, warm (> 13 C), after rain more likely
const FLY_FROM := 182.0                        # 1 July [A9: early July - mid August in Britain; A1, A8]
const FLY_TO := 243.0                          # 31 August; after it the rest leave on the next warm afternoon
const FLY_LAST := 290.0                        # mid October: those still in the nest die
const FLY_MIN_C := 13.0                        # [A5: alates seen only above 13 C]
const FLY_TOD := Vector2(0.58, 0.8)            # ~14:00-19:00 [A4: the time of day differs; keepers: 18-20 h]
const FLY_CHANCE := 0.25                       # a suitable afternoon: chance a colony's alates go [chosen: colonies do
const FLY_RAIN_K := 3.0                        # not all fly the same day, A5] - x this within 2 days of rain [keepers]


static func is_sexual(l: Dictionary) -> bool:
	return l.has("x")


## A larva's or pupa's kind: "g", "m", or "" for a worker's.
static func kind_of(l: Dictionary) -> String:
	return String(l.get("x", ""))


## The day's bookkeeping (sim_colony._new_day): a winter counted when its cold has rested the queen; in late March the
## choice of this year's sexuals.
static func new_day(s) -> void:
	if s.scenario != "wild":
		return
	if int(s.doy_f()) == CHOOSE_DOY and int(s.stats.get("choose_y", 0)) != s.year():
		s.stats["choose_y"] = s.year()
		_choose(s)
	elif int(s.doy_f()) == AUTUMN_DOY and int(s.stats.get("autumn_y", 0)) != s.year():
		s.stats["autumn_y"] = s.year()
		_autumn_batch(s)


## The spend and its split for the food `year_food`: [gynes, males].
static func _split(s, year_food: float) -> Array:
	var spend := year_food * ALATE_SHARE
	var first: bool = int(s.stats.get("alate_years", 0)) == 0
	var n_g := int(spend * (GYNE_SPEND_FIRST if first else GYNE_SPEND) / GYNE_COST)
	return [n_g, int((spend - n_g * GYNE_COST) / MALE_COST)]


## Mid-August: a colony big enough, with the winter ahead its second (or later), lays a batch of eggs that winter as
## larvae, enough for next spring's alates - beyond the colony limit and the late-summer stop (sim_brood._queen): a
## colony at its limit lays almost nothing then, and went into winter with ~16 larvae of 1,860 workers (v0.14.2 testing:
## year_run wild 1100 kept seeds 5, 11).
static func _autumn_batch(s) -> void:
	var most: float = s.sp.get("colony_max", 2000.0)
	if not s.queen.alive or s.workers.size() < most * WORKERS_K or winters(s) < WINTERS - 1:
		return
	var had = s.stats.get("food_mark")
	var since := _food_mark(s) - float(had) if had != null else _food_mark(s) * 365.0 / maxf(365.0, float(s.day()))
	var days := float(AUTUMN_DOY - CHOOSE_DOY) if had != null else 365.0
	var n: Array = _split(s, since * 365.0 / days)
	var k := int(ceilf((n[0] + n[1]) / LARVAE_MOST * AUTUMN_MORE))
	for j in k:
		s.eggs.append({"p": 0.3 * float(j) / maxf(1.0, float(k)), "c": s.queen_at})     # (laid over the days before: spread)
		s.protein = maxf(0.0, s.protein - s.sp["protein_egg"])
	if k > 0:
		s._event("egg")
		s.stats["autumn_eggs"] = k


## How many winters the colony has come through (a winter: cold_days reached 42 - sim_colony._new_day).
static func winters(s) -> int:
	return int(s.stats.get("winters", 0))


static func _food_mark(s) -> float:
	return float(s.stats.sugar_in) + float(s.stats.protein_in)


## Late March: a colony big and old enough turns some of its overwintered larvae into sexuals.
static func _choose(s) -> void:
	var got := _food_mark(s)
	var had = s.stats.get("food_mark")
	s.stats["food_mark"] = got
	var most: float = s.sp.get("colony_max", 2000.0)
	if not s.queen.alive or s.workers.size() < most * WORKERS_K or winters(s) < WINTERS:
		return
	# last year's food: the loads brought home since the last choice (a colony from an older save: its whole life's,
	# a year's worth of it)
	var year_food := got - float(had) if had != null else got * 365.0 / maxf(365.0, float(s.day()))
	var n: Array = _split(s, year_food)
	var n_g: int = n[0]
	var n_m: int = n[1]
	# from the larvae that wintered, the furthest grown first (fixed order: the simulation must repeat itself)
	var pool: Array = []
	for i in s.larvae.size():
		if not is_sexual(s.larvae[i]):
			pool.append(i)
	pool.sort_custom(func(a, b): return s.larvae[a].p > s.larvae[b].p or (s.larvae[a].p == s.larvae[b].p and a < b))
	var room := int(pool.size() * LARVAE_MOST)
	if n_g + n_m > room:
		var k := float(room) / float(n_g + n_m)
		n_g = int(n_g * k)
		n_m = room - n_g
	if n_g + n_m == 0:
		return
	s.stats["alate_years"] = int(s.stats.get("alate_years", 0)) + 1
	var made := {"y": s.year(), "g": n_g, "m": n_m, "food": snappedf(year_food, 0.1)}
	var list: Array = s.stats.get("alate_log", [])
	list.append(made)
	s.stats["alate_log"] = list.slice(-10)
	for j in n_g + n_m:
		var l: Dictionary = s.larvae[pool[j]]
		l["x"] = "g" if j < n_g else "m"
		l.p = 0.1                # (late March a male larva has ~11% of its weight [A1]; it grows on from there)
	if n_g == 0:
		s._log(s.T.alates_chosen_m, "ok", [n_m])       # (a poor year: food for males only)
	else:
		s._log(s.T.alates_chosen, "ok", [n_g, n_m])


## A sexual larva eats this much more than a worker's (protein and honeydew), 1.0 for a worker's.
static func eat_k(l: Dictionary) -> float:
	return EAT.get(String(l.get("x", "")), 1.0)


static func larva_k(l: Dictionary) -> float:
	return 1.0 / LARVA_DAYS.get(String(l.get("x", "")), 1.0)


static func pupa_k(p: Dictionary) -> float:
	return 1.0 / PUPA_DAYS.get(String(p.get("x", "")), 1.0)


## A sexual pupa comes out: an alate in the nest. What it holds: its larva's cost, as well fed as the larva was ("s"
## holds the size; "q" how well it was fed, carried in "w").
static func eclose(s, pupa: Dictionary) -> void:
	var x := String(pupa.x)
	var q := clampf(float(pupa.get("q", 1.0)), 0.3, 1.0)
	var w: float = MALE_COST * q if x == "m" else GYNE_COST * (1.0 / 3.9) * q     # (a gyne: ~4 of her 15.5 mg [A3])
	s.alates.append({"x": x, "w": w, "age": 0.0, "h": 0.0, "id": s._next_id})
	s._next_id += 1
	s._event("alate_" + x, SIZE[x])
	var y: Dictionary = s.stats.get("alates_y", {})
	if int(y.get("y", 0)) != s.year():
		y = {"y": s.year(), "g": 0, "m": 0}
		s._log(s.T.alates_first, "ok")
	y[x] = int(y[x]) + 1
	s.stats["alates_y"] = y


## The half-hour duty round (sim_duties._duties): the workers inside feed the alates from their crops - each its upkeep,
## and a gyne what she fattens by; whatever they cannot give, she or he lives on their own body ("w").
static func feed(s, inside: Array, hours: float) -> void:
	if s.alates.is_empty():
		return
	var heat: float = s.cold_factor(s.climate.nest)
	var keep: float = s.crop_cap() * FROM_KEEP
	var gi := 0
	for al: Dictionary in s.alates:
		var x := String(al.x)
		var need: float = s.sp["sugar_worker"] * UPKEEP[x] * heat * hours / 24.0
		var grow := 0.0
		if x == "g" and al.w < GYNE_COST:
			grow = minf(GYNE_COST * (1.0 - 1.0 / 3.9) / FATTEN_DAYS * hours / 24.0, GYNE_COST - al.w)
		var want := need + grow
		var got := 0.0
		while got < want and gi < inside.size():
			var a = inside[gi]
			var can := maxf(0.0, a.crop - keep)
			var take := minf(can, want - got)
			a.crop -= take
			got += take
			if a.crop <= keep + 0.0001:
				gi += 1
		s.sugar -= got
		s.food_eaten += got
		al.w = maxf(0.0, al.w + got - need)
		al.h = maxf(0.0, al.h - hours / 24.0) if got >= need else al.h + hours / 24.0


## Each colony tick (sim_colony._colony): the alates age; those starved die; on a flight afternoon the ready ones fly.
static func step(s, dt: float) -> void:
	if s.alates.is_empty():
		return
	var starve: float = s.sp["starve_days_worker"]
	for i in range(s.alates.size() - 1, -1, -1):
		var al: Dictionary = s.alates[i]
		al.age += dt
		if al.h > starve or al.w <= 0.0:
			s.alates.remove_at(i)
			_count(s, "died_" + String(al.x))
	var d: float = s.doy_f()
	if d > FLY_LAST:
		for al in s.alates:
			_count(s, "died_" + String(al.x))
		s.alates.clear()
		return
	var tod: float = s.time_of_day()
	if d < FLY_FROM or tod < FLY_TOD.x or tod > FLY_TOD.y or s.climate.air <= FLY_MIN_C or s.climate.raining():
		return
	var wind: float = s.wind()
	if wind >= s.climate.WIND_MOST:
		return                   # (too windy: the next calm afternoon [A5])
	# one chance an afternoon (the colony tick that first falls in it)
	var today: int = s.day()
	if int(s.stats.get("fly_try", 0)) == today:
		return
	s.stats["fly_try"] = today
	var chance := FLY_CHANCE * clampf(1.5 * (1.0 - wind / s.climate.WIND_MOST), 0.0, 1.0)     # (calm: likelier [A4])
	if today - int(s.stats.get("rain_day", -99)) <= 2:
		chance *= FLY_RAIN_K
	if d <= FLY_TO and s.rng.randf() >= chance:
		return
	_fly(s)


## The ready alates leave the nest and fly (step 3: the view shows it on the plot). The gynes that fly are kept for
## step 4 (the mated queens on the ground the keeper can catch).
static func _fly(s) -> void:
	var g := 0
	var m := 0
	var queens: Array = []
	# the males wait for the colony's gynes: both sexes leave on the same flight [A9: a colony's alates fly together]
	# (v0.14.2 testing: the males went 9-15 July, the gynes, still fattening, 22-29) - until the end of August
	var gyne_waits := false
	for al in s.alates:
		if al.x == "g" and (al.age < READY_DAYS or (al.w < GYNE_COST * GYNE_READY and al.age < 30.0)):
			gyne_waits = true
	gyne_waits = gyne_waits and s.doy_f() <= FLY_TO
	for i in range(s.alates.size() - 1, -1, -1):
		var al: Dictionary = s.alates[i]
		if al.age < READY_DAYS or (al.x == "g" and al.w < GYNE_COST * GYNE_READY and al.age < 30.0) or (al.x == "m" and gyne_waits):
			continue
		s.alates.remove_at(i)
		if al.x == "g":
			g += 1
			queens.append(snappedf(al.w / GYNE_COST, 0.001))
		else:
			m += 1
	if g + m == 0:
		return
	_count(s, "flew_g", g)
	_count(s, "flew_m", m)
	s.stats["flight"] = {"day": s.day(), "g": g, "m": m, "w": queens, "wind": snappedf(s.wind(), 0.1)}
	s._event("flight", float(g + m))
	s.WildQueens.own_flight(s, queens)          # (a few come down on the plot again, mated: sim/wild_queens.gd)
	if g == 0 or m == 0:
		s._log(s.T.alates_flew_m if g == 0 else s.T.alates_flew_g, "ok", [m if g == 0 else g])
	else:
		s._log(s.T.alates_flew, "ok", [g, m])


static func _count(s, key: String, n := 1) -> void:
	var y: Dictionary = s.stats.get("alates_y", {"y": s.year(), "g": 0, "m": 0})
	y[key] = int(y.get(key, 0)) + n
	s.stats["alates_y"] = y


## The alates of a save, each checked (files in user:// are anyone's to edit: docs/release/SECURITY_REVIEW.md); larvae
## and pupae with a kind that is not one are made workers' again.
static func from_save(s, d: Dictionary) -> void:
	s.alates = []
	var v = d.get("alates", [])
	if v is Array:
		for a in v:
			if a is Dictionary and String(a.get("x", "")) in ["g", "m"]:
				var al := {"x": String(a.x), "w": 0.0, "age": 0.0, "h": 0.0, "id": 0}
				for k in ["w", "age", "h", "id"]:
					var n = a.get(k, 0.0)
					if n is float or n is int:
						al[k] = clampf(float(n), 0.0, 1.0e6) if k != "id" else int(n)
				s.alates.append(al)
	for list in [s.larvae, s.pupae]:
		for l in list:
			if l is Dictionary and l.has("x") and not String(l.x) in ["g", "m"]:
				l.erase("x")
