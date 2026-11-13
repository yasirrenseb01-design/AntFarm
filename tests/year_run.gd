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
	var r := RandomNumberGenerator.new(); r.seed = 3
	print("%s start %s  workers %d" % [scen, s.date_text(), workers])
	var fill_of := func(): return clampf(s.sugar / (s.workers.size() * 2.5), 0.0, 1.0) if s.workers.size() > 0 else 0.0
	var bins := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]   # out share by crop fill 0-20-40-60-80-100%
	var bins_p := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]] # (the same while prey is not short)
	var out_sum := 0.0
	var out_n := 0
	for d in days:
		for i in s.TPD:
			s.step()
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
		if alone: pass
		elif s.humidity < 0.45: s.add_water()
		if scen == "keeper": s.fridge_on = s.doy_f() > 320.0 or s.doy_f() < 20.0
		if not alone and d % 3 == 0 and s.climate.season_mean() > 8.0:
			for k in 1 + s.workers.size() / 40:
				s.place_food("cricket", s.food_spot(300.0, 560.0, r))
		if not alone and s.sugar < s.sugar_cap() * 0.7 and s.climate.season_mean() > 8.0:
			for k in 1 + s.workers.size() / 50:
				s.place_food("honey", s.food_spot(300.0, 560.0, r))
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
	print("workers dead %d by %s · brood dead %d · larvae eaten %d · born %d" % [s.stats.dead, s.stats.dead_by, s.stats.brood_dead, s.stats.cannibalized, s.stats.born])
	quit()
