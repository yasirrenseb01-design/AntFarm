extends "res://scripts/sim/parts/sim_warmth.gd"
## Simulation, layer 8 of 11: the queen laying and the brood growing (eggs, larvae, cocoons, new workers);
## the colony limit (species "colony_max"). Split from sim_colony.gd in v0.12.1.


const QUEEN_KEEP := 20.0     # body reserve a founding queen will not spend on brood
const LAY_COVER_WEEKS := Vector2(12.0, 24.0)   # full stores lay flat out only if they carry the shortfall this long (v0.12.11)


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
		# ...unless the stores are well filled already (v0.12.0, the keeper's choice: before, full stores laid at 16%)
		var fill := (sugar + fat) / (sugar_cap() + fat_cap())
		# (v0.12.11) - and only while those stores would carry the shortfall a good while: in the wild, a colony whose
		# stores were full in spring laid flat out, doubled by midsummer on foraging that fed half of it, and starved
		# through the autumn and winter (year_run wild alone: 4 of 6 seeds). Weeks the stores last at today's shortfall:
		# (the eggs already laid counted as mouths too: they will be workers within two months)
		var ahead: float = 7.0 * ((mouths + eggs.size()) * sp["sugar_worker"] + sp["sugar_queen"])
		var short := maxf(ahead - sugar_income, 0.001)
		var lasts := (sugar + fat) / short
		var full := clampf((fill - 0.4) / 0.2, 0.0, 1.0) * clampf((lasts - LAY_COVER_WEEKS.x) / (LAY_COVER_WEEKS.y - LAY_COVER_WEEKS.x), 0.0, 1.0)
		rate *= lerpf(clampf((earning - 1.0) / 0.5, 0.05, 1.0), 1.0, full)
	if not queen_tended:
		rate *= UNTENDED_LAYING          # nobody attended her this half hour (parts/sim_duties.gd)
	var whole := workers.size() + brood + pupae.size()      # (all of them may yet become workers)
	var most: float = sp.get("colony_max", 1000.0)
	rate *= clampf((most - whole) / (most * 0.15), 0.0, 1.0)
	if whole >= most * 0.85 and not stats.get("near_limit", false):
		stats["near_limit"] = true       # (said once a colony)
		_log(T.colony_near_limit, "ok")
	egg_acc += rate * dt
	while egg_acc >= 1.0 and workers.size() + eggs.size() + larvae.size() + pupae.size() < most:
		egg_acc -= 1.0
		eggs.append({"p": 0.0, "c": queen_at})
		protein = maxf(0.0, protein - sp["protein_egg"])
		_event("egg")
	egg_acc = minf(egg_acc, 1.0)         # (held back at the limit: no stored-up burst when room opens)


func _brood(dt: float) -> void:
	for i in range(eggs.size() - 1, -1, -1):
		eggs[i].p += dt / sp["egg_days"] * dev_in(int(eggs[i].get("c", -1)))      # (each at its own chamber's warmth)
		if eggs[i].p >= 1.0:
			var at := int(eggs[i].get("c", -1))
			eggs.remove_at(i)
			larvae.append({"p": 0.0, "h": 0.0, "q": 0.6, "c": at})

	var n := larvae.size()
	if n > 0:
		# larvae eat to grow, each as far as it was fed in the last duty round ("f"; parts/sim_duties.gd): one held still by
		# the cold barely feeds
		var each: float = sp["protein_larva"] * dt * clampf(dev, 0.1, 1.0)
		var cared := 0.0
		for l in larvae:
			cared += float(l.get("f", 1.0))
		var need := each * cared
		if protein < need and queen.reserve > QUEEN_KEEP and workers.size() < 5:
			# the founding queen feeds her larvae from her own reserves (trophic eggs, saliva), but
			# keeps back enough body fat to see herself through the winter
			var give := minf(need - protein + 0.01, queen.reserve - QUEEN_KEEP)
			queen.reserve -= give
			protein += give
		var r := minf(1.0, protein / need) if need > 0.0 else 1.0       # (the protein there is, shared out)
		larva_fed = r * cared / n
		protein = maxf(0.0, protein - need * r)
		var hungriest := -1
		var worst: float = sp["larva_starve_days"]
		# late in the year the last larvae stop short of pupating and overwinter as larvae (diapause)
		var diapause := winding_down() or fridge_on
		var cold := clampf(dev * 2.0, 0.0, 1.0)          # a larva held still by the cold does not go hungry
		var r_all := r
		for i in range(n - 1, -1, -1):
			var l = larvae[i]
			r = r_all * float(l.get("f", 1.0))      # (a larva nobody fed this half hour: no growth, hungrier)
			l.p += dt / sp["larva_days"] * dev_in(int(l.get("c", -1))) * r
			if diapause:
				l.p = minf(l.p, 0.95)
			l.h = maxf(0.0, l.h + dt * (1.0 - r) * cold - dt * r * 0.5)
			l.q = lerpf(l.get("q", 0.6), r, minf(1.0, dt * 0.6))   # running average of how well it was fed
			if l.p >= 1.0:
				larvae.remove_at(i)
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

	for i in range(pupae.size() - 1, -1, -1):
		pupae[i].p += dt / sp["pupa_days"] * dev_in(int(pupae[i].get("c", -1)))
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
			harmony_n.born += 1
			if nw.size >= HARMONY_BIG:
				harmony_n.big += 1
			if stats.born <= 3 or stats.born % 25 == 0:
				_log(T.new_worker, "ok", [stats.born])

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
