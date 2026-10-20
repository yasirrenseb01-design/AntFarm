extends "res://scripts/sim/parts/sim_enemies.gd"
## Simulation, layer 5 of 7: colony physiology (days, roles, feeding, moisture, the queen, brood, the outworld's food and weather).


const QUEEN_KEEP := 20.0     # body reserve a founding queen will not spend on brood

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
	match nest.plan_chambers(eggs.size() + larvae.size() + pupae.size(), workers.size(), target_air()):
		"planned":
			_log(T.chamber_planned % nest.chambers.size(), "ok")
		"opened":
			_log(T.chamber_opened, "ok")
		"grown":
			_log(T.chamber_grown)
	nest.work_left = nest.count_work_left()
	history.append(_snapshot())
	if history.size() > 365:
		history.pop_front()
	if rng.randf() < 0.14:
		climate.rain_ticks = int(TPD * rng.randf_range(0.15, 0.4))
		_log(T.rain_start)


# ---------------------------------------------------------------- colony physiology

func _dev_rate(t: float) -> float:
	if t < sp["dev_min_c"]:
		return 0.0
	if t < sp["dev_opt_c"]:
		return (t - sp["dev_min_c"]) / (sp["dev_opt_c"] - sp["dev_min_c"])
	if t <= sp["dev_hot_c"]:
		return 1.0
	return maxf(0.0, 1.0 - (t - sp["dev_hot_c"]) / (sp["dev_lethal_c"] - sp["dev_hot_c"]))


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


func _colony(dt: float) -> void:
	dev = _dev_rate(climate.nest)
	activity = _activity(climate.surface()) * (0.1 if climate.raining() else 1.0)
	hungry = sugar < workers.size() * 0.4 + 2.0 or protein < larvae.size() * 0.5 + 1.0
	var forager_age: float = sp["nurse_until_hungry"] if hungry else sp["nurse_until_days"]
	if workers.size() < 8:
		forager_age = sp["callow_days"]     # the first nanitics start foraging within days of emerging

	var age_k := clampf(0.35 + 0.65 * (climate.nest - 4.0) / 20.0, 0.35, 1.0)     # cold slows ageing
	var dug := {}                         # who was digging: they keep at it while digging is wanted
	for a in workers:
		if a.task == Ant.TASK_DIG:
			dug[a.id] = true
	nurses = 0
	callow = 0
	out_count = 0
	var idle: Array = []
	outside.clear()
	for a in workers:
		a.age += dt * age_k
		if a.state != Ant.IN_NEST:
			out_count += 1
			outside.append(a)
			a.task = Ant.TASK_OUT
			continue
		if a.age < sp["callow_days"]:
			callow += 1
			a.task = Ant.TASK_CALLOW
		elif a.age < forager_age * (0.5 + 0.5 * a.threshold(Ant.TH_AGE)):     # some turn forager sooner than others
			nurses += 1
			a.task = Ant.TASK_NURSE
		else:
			idle.append(a)
			a.task = Ant.TASK_RESERVE
	# the reserve, eagerest foragers last (pop_back takes them first)
	idle.sort_custom(func(x, y): return x.threshold(Ant.TH_FORAGE) > y.threshold(Ant.TH_FORAGE) or (x.threshold(Ant.TH_FORAGE) == y.threshold(Ant.TH_FORAGE) and x.id > y.id))
	# Older ants resting inside still help with brood care when nurses are short.
	var lpn: float = sp["larvae_per_nurse"]
	var nurse_cap: float = nurses * lpn + idle.size() * lpn * 0.8 + callow * 1.0
	if queen.alive and workers.size() < 15:
		# a founding queen licks and feeds her first larvae herself, handing over as workers appear
		nurse_cap += 15.0 * (1.0 - workers.size() / 15.0)
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
	for a in idle:
		if out_count >= max_out:
			break
		if rng.randf() < p_exit / a.threshold(Ant.TH_FORAGE):     # the eager go out more often
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
		diggers_wanted = clampi(int((idle.size() * 0.35 + 1.0) * keen), 1, 40) if workers.size() - out_count > 0 else 0
	# who digs: the reserve ants still inside most ready to dig (the view shows them at the dig face)
	var still_in := idle.filter(func(x): return x.state == Ant.IN_NEST)
	still_in.sort_custom(func(x, y):
		if dug.has(x.id) != dug.has(y.id):
			return dug.has(x.id)              # the diggers already at it first (no flicking between jobs)
		return x.threshold(Ant.TH_DIG) < y.threshold(Ant.TH_DIG) or (x.threshold(Ant.TH_DIG) == y.threshold(Ant.TH_DIG) and x.id < y.id))
	for i in mini(diggers_wanted, still_in.size()):
		still_in[i].task = Ant.TASK_DIG

	_metabolism(dt)
	_moisture(dt)
	_queen(dt)
	_brood(dt, nurse_cap)
	_outworld(dt)


func _metabolism(dt: float) -> void:
	protein *= pow(0.92, dt)  # stored prey dries out and spoils
	# Workers feed the queen first by trophallaxis, then share what is left among themselves.
	var heat := cold_factor(climate.nest)          # little food is burnt in a cold nest
	var q_need: float = sp["sugar_queen"] * dt * heat if queen.alive else 0.0
	if sugar < q_need and fat > 0.0:
		var burn := minf(q_need - sugar, fat)
		fat -= burn
		sugar += burn
	queen_fed = sugar >= q_need
	if not queen_fed and queen.reserve > 0.0:
		queen.reserve = maxf(0.0, queen.reserve - q_need)   # living off her own body
		queen_fed = true
	else:
		sugar = maxf(0.0, sugar - q_need)
	# larvae held still by the cold (winter diapause) barely eat
	var need: float = (workers.size() * sp["sugar_worker"] + larvae.size() * sp["sugar_larva"] * clampf(dev, 0.1, 1.0)) * dt * heat
	if sugar < need and fat > 0.0:
		# lean times: the workers live on (and regurgitate) their own body fat
		var burn := minf(need - sugar, fat)
		fat -= burn
		sugar += burn
	if sugar < need and queen.reserve > 0.0 and workers.size() < 5:
		# while founding, the queen regurgitates food from her reserves to her first workers
		var give := minf(need - sugar, queen.reserve)
		queen.reserve -= give
		sugar += give
	# what the colony earns and eats, as running averages over about a week
	var fade := exp(-dt / 7.0)
	sugar_income *= fade
	sugar_spend = sugar_spend * fade + need + q_need
	var fed := 1.0 if need <= 0.0 else clampf(sugar / need, 0.0, 1.0)
	starving = fed < 0.999
	sugar = maxf(0.0, sugar - need)
	# in autumn only a couple of days' food stays in the crops; everything else goes into fat
	# (and from midsummer on outdoors a surplus goes into fat too, not only in autumn when the honeydew is already
	# drying up: a big colony otherwise entered winter on half the fat it needed and starved in the spring)
	var late_summer: bool = scenario == "wild" and doy_f() > 172.0
	var keep := minf(sugar_cap() * 0.5, workers.size() * sp["sugar_worker"] * 2.0 + 2.0) if winding_down() 		else sugar_cap() * (0.25 if late_summer else 0.5)
	if sugar > keep and fat < fat_cap():
		# a well-fed colony lays down fat (and full crops) for the lean months, above all in autumn
		var store := minf(minf(sugar - keep, fat_cap() - fat), workers.size() * 0.15 * dt)
		fat += store
		sugar -= store
	var dry := humidity < 0.1
	for a in workers:
		if starving:
			a.energy -= dt * heat * (1.0 - fed) / sp["starve_days_worker"] / a.hardiness
		elif dry:
			a.energy -= dt / 6.0 / a.hardiness
		else:
			a.energy = minf(1.0, a.energy + dt)
		if a.energy <= 0.0:
			_kill(a, "starve" if starving else "thirst")
		elif a.age > a.life:
			_kill(a, "old")
		elif a.state != Ant.IN_NEST and rng.randf() < sp["forager_daily_risk"] * dt:
			_kill(a, "out")          # lost while foraging: a bird, a spider, a raindrop, a wrong turn
	_warn("starve", starving, T.warn_starve)
	_warn("dry", dry, T.warn_dry)


const TANK_DAYS := 25.0          # a full water tank lasts about this many days at room temperature

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
			water = maxf(0.0, water - dt * k / 0.09 / TANK_DAYS)
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


func _queen(dt: float) -> void:
	if not queen.alive:
		return
	queen.starve = (queen.starve + dt * cold_factor(climate.nest)) if not queen_fed else maxf(0.0, queen.starve - dt)
	queen.dry = (queen.get("dry", 0.0) + dt) if humidity < 0.1 else maxf(0.0, queen.get("dry", 0.0) - dt)
	if queen.starve > sp["starve_days_queen"] or queen.dry > sp["starve_days_queen"] * 1.5:
		queen.alive = false
		var why := T.cause_starvation if queen.starve > sp["starve_days_queen"] else T.cause_thirst
		_log(T.queen_died % why, "bad")
		return
	if starving:
		return
	var cap: float = minf(sp["queen_eggs_max"], sp["queen_eggs_base"] + workers.size() * sp["queen_eggs_per_worker"])
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
	if workers.size() >= 5:
		# workers feed the queen (and so her laying) by how much food the colony has in store: a colony
		# grows only as far as its foraging ground can feed it
		var stock := (sugar + fat) / (sugar_cap() * 0.5 + fat_cap() * 0.5)
		rate *= clampf(stock, 0.1, 1.0)
		# ...and above all by whether foraging brings in more than the colony will eat once it is warm,
		# counting the brood that is about to become workers: when the income only just covers them there
		# is nothing spare for more brood
		var mouths := workers.size() + larvae.size() + pupae.size()
		var upkeep: float = 7.0 * (mouths * sp["sugar_worker"] + sp["sugar_queen"])     # a week, at full warmth
		var earning := sugar_income / upkeep
		rate *= clampf((earning - 1.0) / 0.5, 0.05, 1.0)
	egg_acc += rate * dt
	while egg_acc >= 1.0:
		egg_acc -= 1.0
		eggs.append({"p": 0.0})
		protein = maxf(0.0, protein - sp["protein_egg"])
		_event("egg")


func _brood(dt: float, nurse_cap: float) -> void:
	for i in range(eggs.size() - 1, -1, -1):
		eggs[i].p += dt / sp["egg_days"] * dev
		if eggs[i].p >= 1.0:
			eggs.remove_at(i)
			larvae.append({"p": 0.0, "h": 0.0, "q": 0.6})

	var n := larvae.size()
	if n > 0:
		# larvae eat to grow: one held still by the cold barely feeds
		var need: float = n * sp["protein_larva"] * dt * clampf(dev, 0.1, 1.0)
		if protein < need and queen.reserve > QUEEN_KEEP and workers.size() < 5:
			# the founding queen feeds her larvae from her own reserves (trophic eggs, saliva), but
			# keeps back enough body fat to see herself through the winter
			var give := minf(need - protein + 0.01, queen.reserve - QUEEN_KEEP)
			queen.reserve -= give
			protein += give
		var r := minf(1.0, minf(nurse_cap / n, protein / need))
		larva_fed = r
		protein = maxf(0.0, protein - need * r)
		var hungriest := -1
		var worst: float = sp["larva_starve_days"]
		# late in the year the last larvae stop short of pupating and overwinter as larvae (diapause)
		var diapause := winding_down() or fridge_on
		var cold := clampf(dev * 2.0, 0.0, 1.0)          # a larva held still by the cold does not go hungry
		for i in range(n - 1, -1, -1):
			var l = larvae[i]
			l.p += dt / sp["larva_days"] * dev * r
			if diapause:
				l.p = minf(l.p, 0.95)
			l.h = maxf(0.0, l.h + dt * (1.0 - r) * cold - dt * r * 0.5)
			l.q = lerpf(l.get("q", 0.6), r, minf(1.0, dt * 0.6))   # running average of how well it was fed
			if l.p >= 1.0:
				larvae.remove_at(i)
				pupae.append({"p": 0.0, "s": _adult_size(l.q)})
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
				_log(T.cannibalism % stats.cannibalized, "bad")

	for i in range(pupae.size() - 1, -1, -1):
		pupae[i].p += dt / sp["pupa_days"] * dev
		if pupae[i].p >= 1.0:
			var pupa: Dictionary = pupae[i]
			pupae.remove_at(i)
			if workers.is_empty():
				_log(T.first_worker, "ok")
			var nw := _new_worker(0.0)
			nw.size = pupa.get("s", 1.0)
			_event("eclose", nw.size)
			workers.append(nw)
			stats.born += 1
			if stats.born <= 3 or stats.born % 25 == 0:
				_log(T.new_worker % stats.born, "ok")

	if climate.nest > sp["dev_lethal_c"] - 2.0:
		var p := 0.4 * dt
		_cull(eggs, p)
		_cull(larvae, p)
		_cull(pupae, p)
		_warn("heat", true, T.warn_heat)
	else:
		_warn("heat", false, "")


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
		elif FoodKinds.info(f.kind).has("dries"):
			f.amt *= pow(FoodKinds.info(f.kind).dries, dt)  # a drop dries out and crystallises
		elif f.age > FoodKinds.info(f.kind).get("rots_after", INF) and not f.rotten:
			f.rotten = true
			_food_dirty = true
	var before := foods.size()
	foods = foods.filter(func(f): return f.regen > 0.0 or (f.amt >= 1.0 and f.age < 9.0))
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
