extends "res://scripts/sim/parts/sim_enemies.gd"
## Simulation, layer 4 of 5: colony physiology (days, roles, feeding, moisture, the queen, brood, the outworld's food and weather).


func _new_day() -> void:
	climate.new_day()
	match nest.plan_chambers(eggs.size() + larvae.size() + pupae.size(), workers.size()):
		"planned":
			_log(T.chamber_planned % nest.chambers.size(), "ok")
		"opened":
			_log(T.chamber_opened, "ok")
		"grown":
			_log(T.chamber_grown)
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


func _colony(dt: float) -> void:
	dev = _dev_rate(climate.nest)
	activity = _activity(climate.air) * (0.1 if climate.raining() else 1.0)
	hungry = sugar < workers.size() * 0.4 + 2.0 or protein < larvae.size() * 0.5 + 1.0
	var forager_age: float = sp["nurse_until_hungry"] if hungry else sp["nurse_until_days"]
	if workers.size() < 8:
		forager_age = sp["callow_days"]     # the first nanitics start foraging within days of emerging

	nurses = 0
	callow = 0
	out_count = 0
	var idle: Array = []
	outside.clear()
	for a in workers:
		a.age += dt
		if a.state != Ant.IN_NEST:
			out_count += 1
			outside.append(a)
			continue
		if a.age < sp["callow_days"]:
			callow += 1
		elif a.age < forager_age:
			nurses += 1
		else:
			idle.append(a)
	# Older ants resting inside still help with brood care when nurses are short.
	var lpn: float = sp["larvae_per_nurse"]
	var nurse_cap: float = nurses * lpn + idle.size() * lpn * 0.8 + callow * 1.0
	if queen.alive and workers.size() < 15:
		# a founding queen licks and feeds her first larvae herself, handing over as workers appear
		nurse_cap += 15.0 * (1.0 - workers.size() / 15.0)
	var care_short: bool = larvae.size() > nurses * lpn + callow

	# Undertakers carry nestmates that died inside out to the refuse pile.
	if corpses_inside > 0 and not idle.is_empty() and rng.randf() < 0.5:
		var u = idle.pop_back()
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
				var d = idle.pop_back()
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
		if rng.randf() < p_exit:
			_send_out(a, Ant.SEARCH)
			out_count += 1

	# Excavation: idle workers dig until the nest volume fits the colony; damp soil after rain invites digging.
	if nest.air >= target_air():
		diggers_wanted = 0
	else:
		var keen := 1.4 if humidity > 0.6 else 1.0
		diggers_wanted = clampi(int((idle.size() * 0.35 + 1.0) * keen), 1, 40) if workers.size() - out_count > 0 else 0

	_metabolism(dt)
	_moisture(dt)
	_queen(dt)
	_brood(dt, nurse_cap)
	_outworld(dt)


func _metabolism(dt: float) -> void:
	protein *= pow(0.92, dt)  # stored prey dries out and spoils
	# Workers feed the queen first by trophallaxis, then share what is left among themselves.
	var q_need: float = sp["sugar_queen"] * dt if queen.alive else 0.0
	queen_fed = sugar >= q_need
	if not queen_fed and queen.reserve > 0.0:
		queen.reserve = maxf(0.0, queen.reserve - q_need)   # living off her own body
		queen_fed = true
	else:
		sugar = maxf(0.0, sugar - q_need)
	var need: float = (workers.size() * sp["sugar_worker"] + larvae.size() * sp["sugar_larva"]) * dt
	if sugar < need and queen.reserve > 0.0:
		# while her reserves last the queen regurgitates food to her first workers
		var give := minf(need - sugar, queen.reserve)
		queen.reserve -= give
		sugar += give
	var fed := 1.0 if need <= 0.0 else clampf(sugar / need, 0.0, 1.0)
	starving = fed < 0.999
	sugar = maxf(0.0, sugar - need)
	var dry := humidity < 0.1
	for a in workers:
		if starving:
			a.energy -= dt * (1.0 - fed) / sp["starve_days_worker"] / a.hardiness
		elif dry:
			a.energy -= dt / 6.0 / a.hardiness
		else:
			a.energy = minf(1.0, a.energy + dt)
		if a.energy <= 0.0 or a.age > a.life or (a.state != Ant.IN_NEST and rng.randf() < sp["forager_daily_risk"] * dt):
			_kill(a)
	_warn("starve", starving, T.warn_starve)
	_warn("dry", dry, T.warn_dry)


func _moisture(dt: float) -> void:
	# Evaporation is proportional to how wet the nest is, so a drying nest slows down
	# (a watered Ytong/plaster nest lasts 2–3 weeks; a heat mat dries it faster).
	var k := 0.09 + (0.06 if heater else 0.0) + workers.size() * 0.0002
	humidity = clampf(humidity * exp(-k * dt), 0.0, 1.0)
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


func _queen(dt: float) -> void:
	if not queen.alive:
		return
	queen.starve = (queen.starve + dt) if not queen_fed else maxf(0.0, queen.starve - dt)
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
	var yolk := maxf(protein, 3.0 if (queen.reserve > 8.0 and workers.size() < 5) else 0.0)
	var rate := cap * dev * clampf(yolk / 3.0, 0.0, 1.0) * room
	if humidity < sp["humidity_ok_min"]:
		rate *= 0.3
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
		var need: float = n * sp["protein_larva"] * dt
		if protein < need and queen.reserve > 0.0 and workers.size() < 5:
			# the founding queen feeds her larvae from her own reserves (trophic eggs, saliva)
			var give := minf(need - protein + 0.01, queen.reserve)
			queen.reserve -= give
			protein += give
		var r := minf(1.0, minf(nurse_cap / n, protein / need))
		protein = maxf(0.0, protein - need * r)
		var hungriest := -1
		var worst: float = sp["larva_starve_days"]
		for i in range(n - 1, -1, -1):
			var l = larvae[i]
			l.p += dt / sp["larva_days"] * dev * r
			l.h = maxf(0.0, l.h + dt * (1.0 - r) - dt * r * 0.5)
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
	for f in foods:
		f.age += dt
		if f.regen > 0.0:
			f.amt = minf(f.cap, f.amt + f.regen * dt * (0.4 + 0.6 * light))
		elif FoodKinds.info(f.kind).has("dries"):
			f.amt *= pow(FoodKinds.info(f.kind).dries, dt)  # a drop dries out and crystallises
		elif f.age > FoodKinds.info(f.kind).get("rots_after", INF) and not f.rotten:
			f.rotten = true
			_food_dirty = true
	var before := foods.size()
	foods = foods.filter(func(f): return f.regen > 0.0 or (f.amt >= 1.0 and f.age < 9.0))
	if foods.size() != before:
		_food_dirty = true

	if rng.randf() < 0.8 * dt:
		var p := Vector2(rng.randf_range(30, WORLD.x - 30), rng.randf_range(30, WORLD.y - 30))
		if place_food("fly", p) and not _warned.get("fly_hint", false):
			_warned["fly_hint"] = true
			_log(T.fly_fell)

	for c in corpses:
		c.age += dt
	corpses = corpses.filter(func(c): return c.age < 30.0)
	if corpses.size() > 250:
		corpses = corpses.slice(corpses.size() - 250)

	if enemies and creatures.is_empty() and rng.randf() < 0.25 * dt:
		_spawn_creature("wolf_spider")
