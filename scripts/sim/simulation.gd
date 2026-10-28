extends "res://scripts/sim/parts/sim_duties.gd"
## Colony + outworld simulation. Pure data and no nodes, so it can run headless (self-tests,
## offline catch-up). This file is the top of the chain: the main step, saving/loading and summaries.
## Layers: parts/sim_state <- sim_base <- sim_foragers <- sim_enemies <- sim_warmth <- sim_colony <- sim_duties <- simulation
## (see docs/ARCHITECTURE.md).


# ---------------------------------------------------------------- main step

func step() -> void:
	tick += 1
	if tick % TPD == 0:
		_new_day()
	climate.doy = doy_f()
	climate.sun = daylight()
	climate.update(time_of_day(), heater, TPD)
	var raining: bool = climate.raining()
	if raining:
		climate.rain_ticks -= 1
		if climate.rain_ticks == 0:
			_log(T.rain_stop)
	home.decay(_log_rain if raining else _log_home)
	food.decay(_log_rain if raining else _log_food)
	alarm.decay(_log_rain if raining else _log_alarm)
	var t0 := Time.get_ticks_usec()
	if tick % COLONY_EVERY == 0:
		_colony(float(COLONY_EVERY) / TPD)
	if tick % DUTY_EVERY == 0:
		_duties()
	if tick % NestVolume.STEP_EVERY == 0:
		var tn := Time.get_ticks_usec()
		nest.step(tick, diggers_wanted, target_air(), humidity)
		_surface()
		prof.nest = prof.get("nest", 0) + Time.get_ticks_usec() - tn
	var t1 := Time.get_ticks_usec()
	_spd = sp["walk_speed"] * (0.35 + 0.65 * activity)
	_want_sugar = sugar < sugar_cap() * 0.95
	_want_protein = protein < protein_cap() * 0.95
	if _food_dirty:
		_rebuild_food_grid()
		prof.grids += 1
	var t2 := Time.get_ticks_usec()
	var n := maxi(1, ant_substep)
	var phase := tick % n
	_noise_k = sqrt(n)
	if n > 1:
		_spd *= n
	if tick % 4 == 0:
		_encounters()
	var hauling := false
	for a: Ant in outside:
		if a.state == Ant.DRAG:
			hauling = true                         # moved together with the item they hold, below
		elif a.state != Ant.IN_NEST and not a.dead and (n == 1 or a.id % n == phase):
			if a.state == Ant.DEFEND:
				_step_defender(a)
			else:
				_step_ant(a)
			prof.steps += 1
	if hauling:
		_step_drags()
	var t3 := Time.get_ticks_usec()
	if not creatures.is_empty():
		_step_creatures()
	if _any_dead:
		workers = workers.filter(func(w): return not w.dead)
		outside = outside.filter(func(w): return not w.dead)
		_any_dead = false
	var t4 := Time.get_ticks_usec()
	prof.colony += t1 - t0
	prof.grid += t2 - t1
	prof.ants += t3 - t2
	prof.other += t4 - t3


## The complete state of the colony and its box. Loading it with from_dict() and stepping on gives
## exactly the same future as never having stopped (the random generator's state is included).
func to_dict() -> Dictionary:
	var ants := []
	for a in workers:
		var row := []
		for f in ANT_FIELDS:
			row.append(a.get(f))
		ants.append(row)
	var out_ids := PackedInt32Array()
	for a in outside:
		out_ids.append(a.id)
	return {
		"version": SAVE_VERSION, "species": sp["id"], "scenario": scenario, "start_doy": start_doy, "cold_days": cold_days, "fridge_on": fridge_on, "rng_seed": rng.seed, "rng_state": rng.state, "tick": tick,
		"climate": climate.to_dict(), "nest": nest.to_dict(), "home": home.to_dict(), "food": food.to_dict(), "alarm": alarm.to_dict(), "next_cid": _next_cid,
		"world": [WORLD.x, WORLD.y], "plot_seed": plot_seed, "nest_pos": nest_pos, "midden_pos": midden_pos, "traits": traits,
		"brood_at": brood_at, "queen_at": queen_at, "queen_stay": _queen_stay, "ch_mean": ch_mean, "surf_mean": surf_mean,
		"rock": rock, "rocks": rocks, "foods": foods, "corpses": corpses, "workers": ants, "outside": out_ids, "dumps": _dumps,
		"eggs": eggs, "larvae": larvae, "pupae": pupae, "queen": queen,
		"sugar": sugar, "fat": fat, "sugar_income": sugar_income, "sugar_spend": sugar_spend, "protein": protein, "humidity": humidity, "water": water, "mold": mold, "heater": heater, "enemies": enemies, "enemy_rate": enemy_rate,
		"creatures": creatures, "corpses_inside": corpses_inside, "egg_acc": egg_acc, "stats": stats,
		"queen_tended": queen_tended, "carry_due": _carry_due, "unloaded": _unloaded, "duty_rng": [duty_rng.seed, duty_rng.state],
		"history": history, "log": log_entries, "warned": _warned, "next_id": _next_id,
		"cannibal_cd": _cannibal_cd, "recruits": _recruits,
		# values the colony tick derives but foragers read in between
		"derived": {"nurses": nurses, "callow": callow, "out_count": out_count, "dev": dev, "activity": activity,
			"starving": starving, "queen_fed": queen_fed, "hungry": hungry, "diggers_wanted": diggers_wanted},
	}


func from_dict(d: Dictionary) -> void:
	# the box: one of the two sizes there are (saved from v0.11.43; before that every box was the small one)
	var wd = d.get("world", [])
	WORLD = BIG_WORLD if wd is Array and wd.size() == 2 and Vector2(float(wd[0]), float(wd[1])) == BIG_WORLD else SMALL_WORLD
	gw = int(WORLD.x / CELL)
	gh = int(WORLD.y / CELL)
	sp = Species.data(String(d.get("species", Species.DEFAULT)))
	rng.seed = d.rng_seed
	rng.state = d.rng_state
	tick = d.tick
	scenario = d.scenario
	start_doy = d.start_doy
	cold_days = d.cold_days
	fridge_on = d.fridge_on
	climate = Climate.new(rng)
	climate.from_dict(d.climate)
	nest = NestVolume.new()
	nest.from_dict(rng, d.nest)
	home = Field.new(gw, gh, CELL)
	home.from_dict(d.home)
	food = Field.new(gw, gh, CELL)
	food.from_dict(d.food)
	alarm = Field.new(gw, gh, CELL)
	if d.alarm != null:
		alarm.from_dict(d.alarm)
	_next_cid = d.next_cid
	# (saves before v0.11.18: the one plot every colony had)
	plot_seed = int(d.get("plot_seed", 0))
	# (saves before v0.11.19: where the brood and the queen are is worked out on the first colony tick)
	brood_at = {"larvae": -1, "pupae": -1}
	var ba = d.get("brood_at", {})
	if ba is Dictionary:
		for k in ["larvae", "pupae"]:
			if ba.get(k) is int or ba.get(k) is float:
				brood_at[k] = int(ba[k])
	queen_at = int(d.get("queen_at", -1)) if (d.get("queen_at") is int or d.get("queen_at") is float) else -1
	_queen_stay = float(d.get("queen_stay", 0.0)) if (d.get("queen_stay") is int or d.get("queen_stay") is float) else 0.0
	surf_mean = clampf(float(d.get("surf_mean", -1000.0)), -1000.0, 80.0) if (d.get("surf_mean", -1000.0) is float or d.get("surf_mean", -1000.0) is int) else -1000.0
	ch_mean = d.get("ch_mean") if d.get("ch_mean") is PackedFloat32Array and (d.get("ch_mean") as PackedFloat32Array).size() <= 64 else PackedFloat32Array()
	traits = {}
	var tt = d.get("traits", {})
	if tt is Dictionary:
		for k in tt:
			if (tt[k] is float or tt[k] is int) and k is String:
				traits[k] = clampf(float(tt[k]), 0.5, 1.5)
	nest.depth_k = colony_trait("depth")
	nest.spread_k = colony_trait("spread")
	nest.wind_k = colony_trait("wind")
	nest.lean_k = colony_trait("lean")
	nest.bush_k = colony_trait("bush")
	nest_pos = d.get("nest_pos", Vector2(480, 400))
	midden_pos = d.get("midden_pos", Vector2(575, 480))
	rock = d.rock
	rocks = d.rocks
	_restamp_rocks()                    # which stones are climbed over is worked out from the stones themselves
	# (not saved: worked out from the nest and the colony as the daily plan does)
	if nest.entrance_r < 0.0:
		nest.entrance_r = clampf(1.0 + workers.size() * 0.012, 1.0, 1.7)
	if nest.work_left < 0:
		nest.work_left = nest.count_work_left()      # (older saves; it also lays out the paths to the work)
	foods = d.foods
	corpses = d.corpses
	workers = []
	var by_id := {}
	for row in d.workers:
		var a := Ant.new()
		for i in ANT_FIELDS.size():
			a.set(ANT_FIELDS[i], row[i])
		workers.append(a)
		by_id[a.id] = a
	outside = []
	for id in d.outside:
		if by_id.has(id):
			outside.append(by_id[id])
	_dumps = d.get("dumps", {})
	eggs = d.eggs
	larvae = d.larvae
	pupae = d.pupae
	queen = d.queen
	sugar = d.sugar
	fat = d.fat
	sugar_income = d.sugar_income
	sugar_spend = d.sugar_spend
	protein = d.protein
	humidity = d.humidity
	water = float(d.get("water", 1.0))      # (saves before v0.8.26 had no tank: start it full)
	mold = d.mold
	heater = d.heater
	enemies = d.enemies
	enemy_rate = d.enemy_rate
	creatures = d.creatures
	corpses_inside = d.corpses_inside
	queen_tended = d.queen_tended
	_carry_due = d.carry_due
	_unloaded = d.unloaded
	duty_rng.seed = d.duty_rng[0]
	if d.duty_rng.size() > 1:
		duty_rng.state = d.duty_rng[1]
	egg_acc = d.egg_acc
	stats = d.stats
	history = d.history
	# (the dead fly and cricket being found are no longer logged: clutter, the keeper 2026-10-28)
	log_entries = d.log.filter(func(e): return not (e is Dictionary and e.get("key", "") in [T.found_fly, T.found_cricket]))
	_warned = d.warned
	_next_id = d.next_id
	_cannibal_cd = d.cannibal_cd
	_recruits = d.recruits
	var dv: Dictionary = d.derived
	nurses = dv.nurses
	callow = dv.callow
	out_count = dv.out_count
	dev = dv.dev
	activity = dv.activity
	starving = dv.starving
	queen_fed = dv.queen_fed
	hungry = dv.hungry
	diggers_wanted = dv.diggers_wanted
	food_cell.resize(gw * gh)
	food_cell.fill(-1)
	_food_dirty = true


## A short summary for the save menu and the "while you were away" report.
## How many game days the colony's sugar and protein last at today's appetite (x: sugar, y: protein; 999 = no end in
## sight: nobody eating it, or aphids renewing it) - what is in the workers' crops and stored prey, and the food lying
## in the box not yet carried in (the keeper's warnings, the keeper, 2026-10-27: "sometimes I forget"; hud_warn.gd,
## the Home). Body fat is not counted: it is the winter's reserve, not the keeper's to fill. Only reads.
func food_days() -> Vector2:
	var s := sugar
	var p := protein
	var renew := false
	for f in foods:
		if f.get("rotten", false):
			continue
		if int(f.type) == Ant.SUGAR:
			s += float(f.amt)
			renew = renew or float(f.get("regen", 0.0)) > 0.0
		else:
			p += float(f.amt)
	var heat := cold_factor(climate.nest)
	var s_need: float = ((sp["sugar_queen"] if queen.alive else 0.0) + workers.size() * sp["sugar_worker"]
		+ larvae.size() * sp["sugar_larva"] * clampf(dev, 0.1, 1.0)) * heat
	var p_need: float = larvae.size() * sp["protein_larva"] * clampf(dev, 0.1, 1.0)
	return Vector2(999.0 if renew or s_need <= 0.0 else minf(999.0, s / s_need), 999.0 if p_need <= 0.0 else minf(999.0, p / p_need))


func summary() -> Dictionary:
	var fd := food_days()
	return {"sugar_days": snappedf(fd.x, 0.1), "protein_days": snappedf(fd.y, 0.1), "day": day(), "workers": workers.size(), "eggs": eggs.size(), "larvae": larvae.size(),
		"pupae": pupae.size(), "born": stats.born, "dead": stats.dead, "brood_dead": stats.brood_dead + stats.cannibalized,
		"chambers": nest.chambers.size(), "volume": nest.volume_cm3(), "humidity": humidity,
		"queen": queen.alive, "glass": nest.slab, "scenario": scenario, "founding": founding(), "fridge": fridge_on}


## The automatic keeper used by tests and, if the player allows it, while the game is closed:
## waters when the reservoir runs low and feeds in proportion to the colony.
func auto_care(day_index: int) -> void:
	if scenario == "wild":
		return      # outdoors nobody tends the colony: rain waters it and it forages for itself
	if humidity < 0.45:
		add_water()
	if workers.is_empty():
		return
	if day_index % 3 == 0:
		for k in 1 + workers.size() / 40:
			place_food("cricket", food_spot(300.0, 560.0))
	if sugar < sugar_cap() * 0.3:
		for k in 1 + workers.size() / 50:
			place_food("honey", food_spot(300.0, 560.0))
