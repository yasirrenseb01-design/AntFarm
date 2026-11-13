extends "res://scripts/sim/parts/sim_brood.gd"
## Simulation, layer 9 of 11: colony physiology (days, roles, feeding, moisture, the outworld's food and weather).


func _new_day() -> void:
	climate.new_day()
	# a keeper cools the formicarium down (and warms it back up) over about a week
	climate.fridge = move_toward(climate.fridge, 1.0 if fridge_on else 0.0, 1.0 / 7.0)
	if scenario == "keeper" and not fridge_on and int(doy_f()) == 305 and queen.alive:     # 1 November
		_log(T.fridge_hint)
	# a winter is a stretch of cold days; six weeks of it fully rests the queen for the next year
	if climate.nest < 10.0:
		cold_days += 1
		if cold_days == 42:
			queen["rested"] = 1.0
			_log(T.winter_rest_done, "ok")
			if fridge_on:
				_log(T.fridge_ready, "ok")
	else:
		if cold_days > 0 and climate.nest > 14.0:
			cold_days = 0
		var was := float(queen.get("rested", 1.0))
		queen["rested"] = maxf(0.0, was - 1.0 / 300.0)
		if scenario == "keeper" and was >= 0.5 and queen.rested < 0.5 and not fridge_on:
			_log(T.rest_low, "bad")
	# a hotter ground: a deeper nest. Young L. niger colonies under daytime surface means of ~22, ~36 and ~48 °C dug
	# 13.7, 17.2 and 19.3 cm down, their chambers lower (García Ibarra et al. 2024) - the line through them, by 22 °C 1
	nest.heat_k = clampf(1.0 + 0.016 * ((surf_mean if surf_mean > -999.0 else 22.0) - 22.0), 0.9, 1.45)
	match nest.plan_chambers(eggs.size() + larvae.size() + pupae.size(), workers.size(), target_air()):
		"planned":
			_log(T.chamber_planned, "", [nest.chambers.size()])
		"opened":
			_log(T.chamber_opened, "")
		"grown":
			_log(T.chamber_grown)
	nest.work_left = nest.count_work_left()
	history.append(_snapshot())
	if history.size() > HISTORY_DAYS:
		_thin_history()
	# rain: outdoors only - a formicarium in the Home's room has none (it rained in the tanks until v0.11.77: the keeper,
	# 2026-11-03). The draws are made either way, so a colony's other chances come out as before.
	if rng.randf() < 0.14:
		var ticks := int(TPD * rng.randf_range(0.15, 0.4))
		if scenario == "wild":
			climate.rain_ticks = ticks
			_log(T.rain_start)


# ---------------------------------------------------------------- colony physiology

## How keen the foragers would be at a time of day (0..1; tod may run past 0..1): `activity`'s reckoning in _colony, by
## today's weather and the sun at that hour, rain or not. Reads only (the HUD's time bar: the hours before and after now).
func activity_at(tod: float, rain: bool) -> float:
	return _activity(climate.surface_at(climate.air_at(tod, rain), daylight(tod))) * (0.1 if rain else 1.0)


func _activity(t: float) -> float:
	if t < sp["forage_min_c"]:
		return 0.0
	if t < sp["forage_opt_c"]:
		return (t - sp["forage_min_c"]) / (sp["forage_opt_c"] - sp["forage_min_c"])
	if t <= sp["forage_hot_c"]:
		return 1.0
	return maxf(0.0, 1.0 - (t - sp["forage_hot_c"]) / (sp["forage_max_c"] - sp["forage_hot_c"]))


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


func _colony(dt: float) -> void:
	_place_brood(dt)
	dev = dev_in(queen_at)                # (in her chamber: how fast she lays, and the larvae are fed)
	activity = _activity(climate.surface()) * (0.1 if climate.raining() else 1.0)
	hungry = sugar < workers.size() * 0.4 + 2.0 or protein < larvae.size() * 0.5 + 1.0
	var forager_age: float = sp["nurse_until_hungry"] if hungry else sp["nurse_until_days"]
	if workers.size() < 8:
		forager_age = sp["callow_days"]     # the first nanitics start foraging within days of emerging

	var age_k := clampf(0.35 + 0.65 * (climate.nest - 4.0) / 20.0, 0.35, 1.0)     # cold slows ageing
	nurses = 0
	callow = 0
	out_count = 0
	var idle: Array = []
	outside.clear()
	_out_ver += 1
	_ranked()
	var callow_d: float = sp["callow_days"]
	var aged := dt * age_k
	_in_c = 0.0
	_in_f = 0.0
	for a in workers:
		a.was_dig = a.task == Ant.TASK_DIG       # who was digging: they keep at it while digging is wanted
		a.age += aged
		a.fed_in = a.state == Ant.IN_NEST        # (what those inside hold, for _metabolism: counted here, not again)
		if a.fed_in:
			_in_c += a.crop
			_in_f += a.body_fat
		else:
			out_count += 1
			outside.append(a)
			a.task = Ant.TASK_DIG if a.state == Ant.DUMP else Ant.TASK_OUT      # (a digger out with its pellet)
			continue
		if a.age < callow_d:
			callow += 1
			a.task = Ant.TASK_CALLOW
		elif a.age < forager_age * (0.5 + 0.5 * a.sort_c):     # some turn forager sooner than others
			nurses += 1
			a.task = Ant.TASK_NURSE
		else:
			a.task = Ant.TASK_RESERVE
	# the reserve, eagerest foragers last (pop_back takes them first): picked out of all the workers kept in that order
	for a in _by_forage:
		if a.task == Ant.TASK_RESERVE:
			idle.append(a)
	# (who feeds which larva is worked out every half hour by the duties, parts/sim_duties.gd; the older ants resting
	# inside help when nurses are short, and a founding queen feeds her first larvae herself)
	var lpn: float = sp["larvae_per_nurse"]
	var care_short: bool = larvae.size() > nurses * lpn + callow

	# Undertakers carry nestmates that died inside out to the refuse pile.
	if corpses_inside > 0 and not idle.is_empty() and rng.randf() < 0.5:
		var u = idle.pop_at(_eagerest(idle, Ant.TH_UNDERTAKE))
		_send_out(u, Ant.UNDERTAKER)
		u.carry = Ant.CORPSE
		corpses_inside -= 1

	# An enemy near the entrance: the alarm spreads inside and workers stream out to defend it.
	var threatened := false
	if not creatures.is_empty() and activity > 0.05:
		var near := false
		for c in creatures:
			if c.pos.distance_squared_to(nest_pos) < 40000.0 or alarm.read_i(home.index(nest_pos.x, nest_pos.y)) > 0.5:
				near = true
		threatened = near
		if near and workers.size() >= FIGHT_FROM:
			var defenders := 0
			for a in outside:
				if a.state == Ant.DEFEND:
					defenders += 1
			var want := mini(4 + int(workers.size() * 0.15), 40)
			while defenders < want and not idle.is_empty():
				var d = idle.pop_at(_eagerest(idle, Ant.TH_DEFEND))
				_send_out(d, Ant.DEFEND)
				d.foe = 0
				out_count += 1
				defenders += 1

	# Recruitment to forage depends on colony need: hungry → many, full stores → few.
	var need_k := 1.6 if hungry else (0.3 if satiated() else 0.7)
	if care_short:
		need_k *= 0.5
	# Only a minority of a colony forages at any moment.
	var max_out := ceili(minf(3.0 + workers.size() * (0.32 if hungry else 0.2), workers.size() * 0.6))
	var p_exit := 0.005 * (COLONY_EVERY / 10.0) * activity * need_k
	if threatened and workers.size() < FIGHT_FROM:
		p_exit = 0.0                      # a young colony keeps its workers in while an enemy prowls outside
	# A forager arriving with food stirs up nestmates, who leave along its fresh trail.
	while _recruits > 0 and not idle.is_empty() and out_count < max_out:
		_send_out(idle.pop_back(), Ant.SEARCH)
		out_count += 1
		_recruits -= 1
	_recruits = 0
	var forage_trait := colony_trait("forage")
	var p_go := p_exit * forage_trait
	for a in idle:
		if out_count >= max_out:
			break
		if rng.randf() < p_go / a.sort_a:     # the eager go out more often (and some colonies)
			_send_out(a, Ant.SEARCH)
			out_count += 1

	# Excavation: idle workers dig until the nest volume fits the colony; damp soil after rain invites digging.
	if nest.air >= target_air() and nest.work_left <= 0:
		diggers_wanted = 0
	elif nest.air >= target_air() and nest.work_at.x < 0:
		diggers_wanted = 0                    # (what is left cannot be reached from the tunnels)
	elif nest.air >= target_air():
		# big enough overall, but a planned chamber or a wider shaft is not finished: a few keep at it
		diggers_wanted = clampi(int(idle.size() * 0.25) + 2, 2, 6) if workers.size() - out_count > 0 else 0
	else:
		var keen := 1.4 if humidity > 0.6 else 1.0
		# (at most 20: more than that only crowded round the one face of the work in the view, a swarm - the cap is
		# chosen, not measured; until v0.11.19 it was 40)
		diggers_wanted = clampi(int((idle.size() * 0.35 + 1.0) * keen), 1, 20) if workers.size() - out_count > 0 else 0
	# who digs: the reserve ants still inside most ready to dig (the view shows them at the dig face)
	if diggers_wanted > 0:                # (none wanted: nothing to sort)
		# (the reserve still inside, readiest first; the diggers already at it before the rest - no flicking between jobs)
		var left := diggers_wanted
		for was_digging in [true, false]:
			for a in _by_dig:
				if left == 0:
					break
				if a.task == Ant.TASK_RESERVE and a.state == Ant.IN_NEST and a.was_dig == was_digging:
					a.task = Ant.TASK_DIG
					left -= 1

	_metabolism(dt)
	_moisture(dt)
	_queen(dt)
	_brood(dt)
	_outworld(dt)


func _metabolism(dt: float) -> void:
	protein *= pow(0.92, dt)  # stored prey dries out and spoils
	# (PART 0.13 step 2) Each worker eats from its own crop, then burns its own fat; out of both, it starves on its own.
	# The queen and the larvae are still fed as a whole (step 4: mouth to mouth): the queen from her own crop, then
	# both from the honeydew at the entrance and the crops - then the fat - of the workers inside, in proportion to what
	# each holds. The workers feed the queen first; a cold nest burns little.
	var heat := cold_factor(climate.nest)
	var q_need: float = sp["sugar_queen"] * dt * heat if queen.alive else 0.0
	var l_need: float = larvae.size() * sp["sugar_larva"] * clampf(dev, 0.1, 1.0) * dt * heat     # (still in diapause)
	# (the crops and fat of those inside, as _colony counted them this tick: an ant sent out since gives its share too)
	var in_c := _in_c
	var in_f := _in_f
	var q_own := minf(queen.crop, q_need)
	var want := l_need
	queen_fed = q_own + _pending_in + in_c + in_f >= q_need
	if not queen_fed and queen.reserve > 0.0:
		queen.reserve = maxf(0.0, queen.reserve - q_need)   # living off her own body
		queen_fed = true
	else:
		queen.crop -= q_own
		food_eaten += q_own
		want += q_need - q_own
	var k := _nest_gives(want, in_c, in_f)
	var founding_w := workers.size() < 5
	if founding_w and k[2] > 0.0:
		# while founding, the queen regurgitates food from her reserves to her first larvae and workers
		queen.reserve = maxf(0.0, queen.reserve - k[2])
	var w_need: float = sp["sugar_worker"] * dt * heat
	var need: float = workers.size() * w_need + l_need
	# what the colony earns and eats, as running averages over about a week
	var fade := exp(-dt / 7.0)
	sugar_income *= fade
	sugar_spend = sugar_spend * fade + need + q_need
	# in autumn only a couple of days' food stays in the crops; everything else goes into fat (and from midsummer on
	# outdoors a surplus goes into fat too, not only in autumn when the honeydew is already drying up: a big colony
	# otherwise entered winter on half the fat it needed and starved in the spring) - each worker its own, at most
	# 0.15 units a day
	var late_summer: bool = scenario == "wild" and doy_f() > 172.0
	var keep: float = sp["sugar_worker"] * 2.0 if winding_down() else crop_cap() * (0.25 if late_summer else 0.5)
	var fat_each: float = sp["fat_cap_each"]
	var store_max := 0.15 * dt
	# ...and no more than the colony's cap in all (as through v0.13.0: the fat of the dead, shared among the living, can
	# take some over their own cap - without this the colony kept more fat than before, laid more, and grew past what
	# its fat carried through the winter)
	var fat_room := fat_cap() - fat
	var dry := humidity < 0.1
	var starve_k: float = dt * heat / sp["starve_days_worker"]
	var risk: float = sp["forager_daily_risk"] * dt
	var c_sum := 0.0
	var f_sum := 0.0
	var short := 0
	food_eaten += w_need * workers.size()      # (less what each could not find: below)
	for a: Ant in workers:
		if a.fed_in:
			a.crop -= a.crop * k[0]
			a.body_fat -= a.body_fat * k[1]
		var miss := w_need - a.crop
		if miss <= 0.0:
			a.crop -= w_need
			miss = 0.0
		else:
			a.crop = 0.0
			var burn := minf(miss, a.body_fat)          # lean times: it lives on its own body fat
			a.body_fat -= burn
			miss -= burn
			food_eaten -= miss
			if a.carry == Ant.SUGAR:
				miss = 0.0                               # a forager on its way home drinks from its load (in its crop)
			if miss > 0.0 and founding_w and queen.reserve > 0.0:
				# (the same, to her first workers)
				var give := minf(miss, queen.reserve)
				queen.reserve -= give
				miss -= give
				food_eaten += give
				food_in += give
		if a.crop > keep and a.body_fat < fat_each and fat_room > 0.0:
			var store := minf(minf(a.crop - keep, fat_each - a.body_fat), minf(store_max, fat_room))
			a.crop -= store
			a.body_fat += store
			fat_room -= store
		c_sum += a.crop
		f_sum += a.body_fat
		var empty := miss > 1e-12
		if empty:
			short += 1
			a.energy -= starve_k * (miss / w_need) / a.hardiness
		elif dry:
			a.energy -= dt / 6.0 / a.hardiness
		else:
			a.energy = minf(1.0, a.energy + dt)
		if a.energy <= 0.0:
			_kill(a, "starve" if empty else "thirst")
		elif a.age > a.life:
			_kill(a, "old")
		elif a.state != Ant.IN_NEST and rng.randf() < risk:
			_kill(a, "out")          # lost while foraging: a bird, a spider, a raindrop, a wrong turn
	sugar = c_sum + queen.crop + _pending_in
	fat = f_sum
	starving = short > workers.size() * STARVING_SHARE
	_warn("starve", starving, T.warn_starve)
	_warn("dry", dry, T.warn_dry)


const HISTORY_DAYS := 1095     # the colony's day-by-day record kept: three years (one until v0.11.77)
const TANK_DAYS := 25.0          # a full water tank lasts about this many days at room temperature


## How much of the water tank goes in a game day now (the Home shows each tank's going down from it: save meta).
func water_use() -> float:
	var k := 0.09 + (0.06 if heater else 0.0) + workers.size() * 0.0002
	if founding():
		k *= 0.3
	return k / 0.09 / TANK_DAYS

func _moisture(dt: float) -> void:
	if scenario == "wild":
		_soil_moisture(dt)
	else:
		# The formicarium's water tank keeps the nest damp (water wicks into the plaster/soil) until it runs dry,
		# ~3.5 weeks at room temperature (keeper kits with a reservoir or a water tube; a heat mat empties it
		# faster); then the nest dries out, evaporation in proportion to how wet it is. A founding queen's cell is
		# sealed, so it loses water far more slowly. (Tank length chosen with the user, 2026-10-12.)
		var k := 0.09 + (0.06 if heater else 0.0) + workers.size() * 0.0002
		if founding():
			k *= 0.3
		if water > 0.0:
			humidity += (0.72 - humidity) * (1.0 - exp(-0.6 * dt))
			water = maxf(0.0, water - dt * water_use())
		else:
			humidity = clampf(humidity * exp(-k * dt), 0.0, 1.0)
		_warn("lowwater", water > 0.0 and water < 0.15, T.warn_lowwater)
		_warn("nowater", water <= 0.0, T.warn_nowater)
	if humidity < sp["humidity_ok_min"]:
		var p: float = (sp["humidity_ok_min"] - humidity) * 2.0 * dt
		_cull(eggs, p)
		_cull(larvae, p * 0.5)
	_warn("lowhum", humidity < sp["humidity_ok_min"], T.warn_lowhum)
	if humidity > sp["humidity_ok_max"]:
		mold += dt
	else:
		mold = maxf(0.0, mold - dt * 0.5)
	if mold > 2.0:
		_cull(larvae, 0.15 * dt)
		_cull(pupae, 0.1 * dt)
		protein *= pow(0.85, dt)
		_warn("mold", true, T.warn_mold)
	else:
		_warn("mold", false, "")


## Outdoors nobody waters the nest: rain soaks into the ground, the deeper soil keeps it damp from
## below (wetter in winter, drier in a hot summer) and too much water drains away.
func _soil_moisture(dt: float) -> void:
	var warm := clampf((climate.season_mean() - 2.0) / 16.0, 0.0, 1.0)
	var ground := lerpf(0.75, 0.5, warm)                 # what the soil around the nest settles to
	humidity += (ground - humidity) * (1.0 - exp(-0.12 * dt))
	humidity *= exp(-(0.01 + 0.04 * warm + workers.size() * 0.0001) * dt)   # drying from the surface
	if climate.raining() and climate.air > 0.0:          # rain (not snow) soaks in
		humidity += (1.0 - humidity) * (1.0 - exp(-0.9 * dt))
	if humidity > 0.8:
		humidity -= (humidity - 0.8) * (1.0 - exp(-1.5 * dt))   # the excess drains away
	humidity = clampf(humidity, 0.0, 1.0)


func _outworld(dt: float) -> void:
	var light := daylight()
	var life := season_life()
	for f in foods:
		f.age += dt
		if f.regen > 0.0:
			# aphids feed and breed only in the warm months (they overwinter as eggs)
			var was: float = f.amt
			f.amt = minf(f.cap, f.amt + f.regen * dt * (0.4 + 0.6 * light) * life)
			if was < 1.0 and f.amt >= 1.0:
				_food_dirty = true      # honeydew again: foragers can smell it once more
			continue
		var info := FoodKinds.info(f.kind)
		if info.has("dries"):
			f.amt *= pow(info.dries, dt)  # a drop dries out and crystallises
		elif f.age > info.get("rots_after", INF) and not f.rotten:
			f.rotten = true
			_food_dirty = true
	var before := foods.size()
	# (a spent drop stays while ants are still drinking from it: each took its share as it began)
	foods = foods.filter(func(f): return f.regen > 0.0 or (f.amt >= 1.0 and f.age < 9.0) or tick < int(f.get("held_until", 0)))
	if foods.size() != before:
		_food_dirty = true

	_beyond_n = 0
	for a in outside:
		if a.act == ACT_AWAY and a.busy > 0:
			_beyond_n += 1
	# small insects die or are caught out on open ground far more often than in a closed box
	var insects := 3.0 if scenario == "wild" else 0.8
	if rng.randf() < insects * dt * life:
		var p := Vector2(rng.randf_range(30, WORLD.x - 30), rng.randf_range(30, WORLD.y - 30))
		if place_food("fly", p) and not _warned.get("fly_hint", false):
			_warned["fly_hint"] = true
			_log(T.fly_fell)

	for c in corpses:
		c.age += dt
	corpses = corpses.filter(func(c): return c.age < 30.0)
	if corpses.size() > 250:
		corpses = corpses.slice(corpses.size() - 250)

	if enemies:
		_maybe_spawn(dt)


## The record kept to HISTORY_DAYS by thinning its old part rather than dropping its start (v0.13.12, the keeper: "can I
## zoom the chart out to day 0?" - only the last three years were kept): the last year stays day by day, before it one
## day in a week, and only when all of that is weekly does the very first go.
func _thin_history() -> void:
	var old_end := history.size() - 365
	for i in range(1, old_end):
		if float(history[i + 1].get("day", 0)) - float(history[i - 1].get("day", 0)) <= 7.0:
			history.remove_at(i)
			return
	history.pop_front()
