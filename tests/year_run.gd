extends SceneTree
## Runs a colony through whole years (seasons, winters) with a simple keeper who waters, feeds while
## the weather is warm and, indoors, puts the formicarium in the fridge from mid-November to January.
## Slow (minutes per year), so not part of tools/check.ps1. Prints a line every 10 days (fill: the crops' mean fill;
## out: the share of workers out in the active hours of those 10 days), and at the end the share out by crop fill.
##   godot --headless --path . --script res://tests/year_run.gd -- <wild|keeper> <workers> <days> [alone|kept] [seed] [save-name] [big]
## big: the Home's bigger tank (90 x 56 cm, keeper only - v0.12.23, the nest spreading in it)
## "alone": nobody waters or feeds (outdoors the colony must live on rain, aphids and what it hunts).
## skip=<n> (anywhere after the others): n draws of the colony's generator thrown away after setup - the same colony on
## another run of chance (LESSONS 3e/3n: compare several, not one)
## why (anywhere after the others): each worker that starves, how it came to (from when its crop and fat ran out), and
## workers stuck standing on a big stone (PART 0.14 step 5, v0.14.4: a fight left them there - LESSONS 51). Slower.
## save-name: the colony is saved at the end of each year to user://growtest/<save-name>/ (slot = year), to open
## in the game with --testsave=<save-name> [--slot=<year>] (performance and nest-shape checks on a grown colony).
func _init():
	var Sim = load("res://scripts/sim/simulation.gd")
	var args := OS.get_cmdline_user_args()
	var scen: String = args[0] if args.size() > 0 else "wild"
	var workers: int = int(args[1]) if args.size() > 1 else 0
	var days: int = int(args[2]) if args.size() > 2 else 730
	var alone: bool = args.size() > 3 and args[3] == "alone"
	var save_name: String = args[5] if args.size() > 5 and not args[5].begins_with("skip=") else ""
	var Store = load("res://scripts/game/save_store.gd")
	if save_name != "":
		Store.base = "user://growtest/%s/" % save_name
	var s = Sim.new()
	s.setup(int(args[4]) if args.size() > 4 else 5, workers, false, scen, args.size() > 6 and args[6] == "big")
	for x in args:
		if x.begins_with("skip="):
			for i in int(x.substr(5)):
				s.rng.randf()
		if x.begins_with("winters="):         # (PART 0.14: a colony set up as one that has wintered n times - sim/alates.gd)
			s.stats["winters"] = int(x.substr(8))
	s.logged.connect(func(e):
		if String(e.key).begins_with("log_alates"):
			print("   LOG %s %s: %s" % [s.date_text(), s.year(), s.L.entry_text(e)]))
	var r := RandomNumberGenerator.new(); r.seed = 3
	print("%s start %s  workers %d" % [scen, s.date_text(), workers])
	var fill_of := func(): return clampf(s.sugar / (s.workers.size() * 2.5), 0.0, 1.0) if s.workers.size() > 0 else 0.0
	var bins := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]   # out share by crop fill 0-20-40-60-80-100%
	var bins_p := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]] # (the same while prey is not short)
	var starved := 0
	var out_sum := 0.0
	var out_n := 0
	# (PART 0.14 step 5, "why": each worker that starves, how it came to - from when it ran out of crop and fat: where it
	# was, what it did, how much food its nestmates had then)
	var why: bool = args.has("why")
	var hungry := {}                     # id -> {a, t0, n, nest, task {}, duty {}, mates_crop, mates_fat}
	var stuck_n := 0
	var trapped := {}
	for d in days:
		for i in s.TPD:
			s.step()
			if why:
				# (an ant outside, not riding an enemy, standing in a big stone's cell for 100 ticks: stuck - no step walks
				# it off; counted once each time, with what it was doing)
				for w in s.workers:
					if w.dead or w.state == 0 or w.busy > 0 or s.rock[s.home.index(w.pos.x, w.pos.y)] != 1:
						trapped.erase(w.id)
						continue
					trapped[w.id] = int(trapped.get(w.id, 0)) + 1
					if trapped[w.id] == 100:
						stuck_n += 1
						if stuck_n <= 10:
							print("   STUCK ON STONE %s y%d id %d: state %d act %d carry %d at %s" % [s.date_text(), s.year(), w.id,
								w.state, w.act, w.carry, w.pos.round()])
			if why and i % 10 == 0:
				var ins := 0
				var c_in := 0.0
				var f_in := 0.0
				for w in s.workers:
					if w.state == 0 and not w.dead:
						ins += 1
						c_in += w.crop
						f_in += w.body_fat
				for w in s.workers:
					if w.dead or w.crop + w.body_fat >= 0.02:
						if not w.dead:
							hungry.erase(w.id)
						continue
					var h: Dictionary = hungry.get(w.id, {})
					if h.is_empty():
						h = {"a": w, "t0": s.tick, "n": 0, "nest": 0, "task": {}, "duty": {}, "c_in": 0.0, "f_in": 0.0, "age": w.age,
							"p0": w.pos, "path": 0.0, "last": w.pos}
						hungry[w.id] = h
					h.n += 1
					h.path += w.pos.distance_to(h.last)
					h.last = w.pos
					h.nest += 1 if w.state == 0 else 0
					h.task[w.task] = int(h.task.get(w.task, 0)) + 1
					h.duty[w.duty] = int(h.duty.get(w.duty, 0)) + 1
					h.c_in += c_in / maxf(1.0, ins)
					h.f_in += f_in / maxf(1.0, ins)
				for id in hungry.keys():
					var h: Dictionary = hungry[id]
					if h.a.dead:
						var n: float = maxf(1.0, h.n)
						print("   WHY %s y%d id %d age %.0f hardy %.2f size %.2f: empty %.1f d, in nest %d%%, task %s duty %s, state %d carry %d, nest mates' mean crop %.2f fat %.2f | from %s to %s (home %s, %.0f px off) walked %.0f px, trip %d act %d busy %d follow %d rock %d" % [
							s.date_text(), s.year(), id, h.age, h.a.hardiness, h.a.size, float(s.tick - h.t0) / s.TPD, int(100.0 * h.nest / n),
							h.task, h.duty, h.a.state, h.a.carry, h.c_in / n, h.f_in / n, h.p0.round(), h.a.pos.round(), s._home_at(h.a.pos).round(),
							h.a.pos.distance_to(s._home_at(h.a.pos)), h.path, h.a.trip, h.a.act, h.a.busy, h.a.follow, s.rock[s.home.index(h.a.pos.x, h.a.pos.y)]])
						hungry.erase(id)
			if i % 60 == 0 and s.activity > 0.8 and s.workers.size() >= 20:
				var o: float = float(s.out_count) / s.workers.size()
				var b: int = mini(4, int(fill_of.call() * 5.0))
				bins[b][0] += o
				bins[b][1] += 1.0
				if s.protein >= s.protein_cap() * 0.6 or s.larvae.is_empty():
					bins_p[b][0] += o
					bins_p[b][1] += 1.0
				out_sum += o
				out_n += 1
		var st: int = int(s.stats.dead_by.get("starve", 0))
		if st > starved:
			# (PART 0.14 step 5: when the starvations happen, and how the colony was then)
			var empty := 0
			var no_fat := 0
			for w in s.workers:
				empty += 1 if w.crop < 0.05 else 0
				no_fat += 1 if w.body_fat < 0.05 else 0
			print("   STARVE +%d %s y%d: workers %d (crop empty %d, no fat %d) fill %d%% fat %.1f larvae %d out %d hibernating %s" % [
				st - starved, s.date_text(), s.year(), s.workers.size(), empty, no_fat, int(fill_of.call() * 100.0), s.fat,
				s.larvae.size(), s.out_count, s.hibernating()])
			starved = st
		if alone: pass
		elif s.humidity < 0.45: s.add_water()
		if scen == "keeper": s.fridge_on = s.doy_f() > 320.0 or s.doy_f() < 20.0
		if not alone and d % 3 == 0 and s.climate.season_mean() > 8.0:
			for k in 1 + s.workers.size() / 40:
				s.place_food("cricket", s.food_spot(300.0, 560.0, r))
		if not alone and s.sugar < s.sugar_cap() * 0.7 and s.climate.season_mean() > 8.0:
			for k in 1 + s.workers.size() / 50:
				s.place_food("honey", s.food_spot(300.0, 560.0, r))
		if d % 10 == 0 and (not s.alates.is_empty() or s.larvae.any(func(l): return l.has("x")) or s.pupae.any(func(l): return l.has("x"))):
			var nl := [0, 0, 0, 0, 0, 0]
			for l in s.larvae:
				if l.has("x"): nl[0 if l.x == "g" else 1] += 1
			for l in s.pupae:
				if l.has("x"): nl[2 if l.x == "g" else 3] += 1
			var gw := 0.0
			for al in s.alates:
				nl[4 if al.x == "g" else 5] += 1
				if al.x == "g": gw += al.w
			print("   alates: larvae g %d m %d  pupae g %d m %d  adults g %d (mean %.1f) m %d" % [nl[0], nl[1], nl[2], nl[3], nl[4],
				gw / maxf(1.0, nl[4]), nl[5]])
		if d % 10 == 0:
			print("%-8s y%d %-9s workers %3d eggs %3d larvae %3d pupae %3d  nest %5.1f air %5.1f  reserve %5.1f sugar %5.1f fat %5.1f prot %5.1f hum %.2f rested %.2f cold %d dead %d fill %3d%% out %3d%%" % [
				s.date_text(), s.year(), s.season_name(), s.workers.size(), s.eggs.size(), s.larvae.size(), s.pupae.size(),
				s.climate.nest, s.climate.air, s.queen.reserve, s.sugar, s.fat, s.protein, s.humidity, s.queen.get("rested", 1.0), s.cold_days, s.stats.dead,
				int(fill_of.call() * 100.0), int(100.0 * out_sum / maxf(1.0, out_n))])
			out_sum = 0.0
			out_n = 0
		if save_name != "" and (d + 1) % 365 == 0:
			Store.save((d + 1) / 365, s)
			print("saved year %d: workers %d, nest %.1f cm3, %d chambers, depth %.1f cm" % [(d + 1) / 365, s.workers.size(),
				s.nest.volume_cm3(), s.nest.chambers.size(), s.nest.depth_cm()])
		if not s.queen.alive:
			print("QUEEN DIED ", s.date_text()); break
	for set in [["out share by crop fill (active hours, >= 20 workers):", bins], ["  ... while prey is not short:", bins_p]]:
		var bl: String = set[0]
		var bb: Array = set[1]
		for b in 5:
			bl += "  %d-%d%%: %s" % [b * 20, b * 20 + 20, ("%.0f%% (n %d)" % [100.0 * bb[b][0] / bb[b][1], bb[b][1]]) if bb[b][1] > 0 else "-"]
		print(bl)
	print("alates: winters %d  made %s  this year %s  last flight %s" % [s.stats.get("winters", 0), s.stats.get("alate_log", []),
		s.stats.get("alates_y", {}), s.stats.get("flight", {})])
	if why:
		print("stuck on a stone (100 ticks, not riding): %d times" % stuck_n)
	print("workers dead %d by %s · brood dead %d · larvae eaten %d · born %d" % [s.stats.dead, s.stats.dead_by, s.stats.brood_dead, s.stats.cannibalized, s.stats.born])
	quit()
