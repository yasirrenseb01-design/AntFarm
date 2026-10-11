extends "res://scripts/sim/parts/sim_colony.gd"
## Colony + outworld simulation. Pure data and no nodes, so it can run headless (self-tests,
## offline catch-up). This file is the top of the chain: the main step, saving/loading and summaries.
## Layers: parts/sim_base <- sim_foragers <- sim_enemies <- sim_colony <- simulation (see docs/ARCHITECTURE.md).


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
	if tick % NestVolume.STEP_EVERY == 0:
		var tn := Time.get_ticks_usec()
		nest.step(tick, diggers_wanted, target_air(), humidity)
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
	for a: Ant in outside:
		if a.state != Ant.IN_NEST and not a.dead and (n == 1 or a.id % n == phase):
			if a.state == Ant.DEFEND:
				_step_defender(a)
			else:
				_step_ant(a)
			prof.steps += 1
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
		"rock": rock, "rocks": rocks, "foods": foods, "corpses": corpses, "workers": ants, "outside": out_ids,
		"eggs": eggs, "larvae": larvae, "pupae": pupae, "queen": queen,
		"sugar": sugar, "fat": fat, "sugar_income": sugar_income, "sugar_spend": sugar_spend, "protein": protein, "humidity": humidity, "mold": mold, "heater": heater, "enemies": enemies,
		"creatures": creatures, "corpses_inside": corpses_inside, "egg_acc": egg_acc, "stats": stats,
		"history": history, "log": log_entries, "warned": _warned, "next_id": _next_id,
		"cannibal_cd": _cannibal_cd, "recruits": _recruits,
		# values the colony tick derives but foragers read in between
		"derived": {"nurses": nurses, "callow": callow, "out_count": out_count, "dev": dev, "activity": activity,
			"starving": starving, "queen_fed": queen_fed, "hungry": hungry, "diggers_wanted": diggers_wanted},
	}


func from_dict(d: Dictionary) -> void:
	gw = int(WORLD.x / CELL)
	gh = int(WORLD.y / CELL)
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
	rock = d.rock
	rocks = d.rocks
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
	mold = d.mold
	heater = d.heater
	enemies = d.enemies
	creatures = d.creatures
	corpses_inside = d.corpses_inside
	egg_acc = d.egg_acc
	stats = d.stats
	history = d.history
	log_entries = d.log
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
func summary() -> Dictionary:
	return {"day": day(), "workers": workers.size(), "eggs": eggs.size(), "larvae": larvae.size(),
		"pupae": pupae.size(), "born": stats.born, "dead": stats.dead + stats.cannibalized,
		"chambers": nest.chambers.size(), "volume": nest.volume_cm3(), "humidity": humidity,
		"queen": queen.alive, "glass": nest.slab, "scenario": scenario, "founding": founding()}


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
			place_food("cricket", Vector2(rng.randf_range(600, 1100), rng.randf_range(380, 700)))
	if sugar < sugar_cap() * 0.3:
		for k in 1 + workers.size() / 50:
			place_food("honey", Vector2(rng.randf_range(600, 1100), rng.randf_range(80, 300)))
