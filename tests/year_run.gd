extends SceneTree
## Runs a colony through whole years (seasons, winters) with a simple keeper who waters, feeds while
## the weather is warm and, indoors, puts the formicarium in the fridge from mid-November to January.
## Slow (minutes per year), so not part of tools/check.ps1. Prints a line every 10 days.
##   godot --headless --path . --script res://tests/year_run.gd -- <wild|keeper> <workers> <days> [alone|kept] [seed] [save-name]
## "alone": nobody waters or feeds (outdoors the colony must live on rain, aphids and what it hunts).
## save-name: the colony is saved at the end of each year to user://growtest/<save-name>/ (slot = year), to open
## in the game with --testsave=<save-name> [--slot=<year>] (performance and nest-shape checks on a grown colony).
func _init():
	var Sim = load("res://scripts/sim/simulation.gd")
	var args := OS.get_cmdline_user_args()
	var scen: String = args[0] if args.size() > 0 else "wild"
	var workers: int = int(args[1]) if args.size() > 1 else 0
	var days: int = int(args[2]) if args.size() > 2 else 730
	var alone: bool = args.size() > 3 and args[3] == "alone"
	var save_name: String = args[5] if args.size() > 5 else ""
	var Store = load("res://scripts/game/save_store.gd")
	if save_name != "":
		Store.base = "user://growtest/%s/" % save_name
	var s = Sim.new()
	s.setup(int(args[4]) if args.size() > 4 else 5, workers, false, scen)
	var r := RandomNumberGenerator.new(); r.seed = 3
	print("%s start %s  workers %d" % [scen, s.date_text(), workers])
	for d in days:
		for i in s.TPD: s.step()
		if alone: pass
		elif s.humidity < 0.45: s.add_water()
		if scen == "keeper": s.fridge_on = s.doy_f() > 320.0 or s.doy_f() < 20.0
		if not alone and d % 3 == 0 and s.climate.season_mean() > 8.0:
			for k in 1 + s.workers.size() / 40:
				s.place_food("cricket", Vector2(r.randf_range(600, 1100), r.randf_range(380, 700)))
		if not alone and s.sugar < s.sugar_cap() * 0.7 and s.climate.season_mean() > 8.0:
			for k in 1 + s.workers.size() / 50:
				s.place_food("honey", Vector2(r.randf_range(600, 1100), r.randf_range(80, 300)))
		if d % 10 == 0:
			print("%-8s y%d %-9s workers %3d eggs %3d larvae %3d pupae %3d  nest %5.1f air %5.1f  reserve %5.1f sugar %5.1f fat %5.1f prot %5.1f hum %.2f rested %.2f cold %d dead %d" % [
				s.date_text(), s.year(), s.season_name(), s.workers.size(), s.eggs.size(), s.larvae.size(), s.pupae.size(),
				s.climate.nest, s.climate.air, s.queen.reserve, s.sugar, s.fat, s.protein, s.humidity, s.queen.get("rested", 1.0), s.cold_days, s.stats.dead])
		if save_name != "" and (d + 1) % 365 == 0:
			Store.save((d + 1) / 365, s)
			print("saved year %d: workers %d, nest %.1f cm3, %d chambers, depth %.1f cm" % [(d + 1) / 365, s.workers.size(),
				s.nest.volume_cm3(), s.nest.chambers.size(), s.nest.depth_cm()])
		if not s.queen.alive:
			print("QUEEN DIED ", s.date_text()); break
	print("workers dead %d by %s · brood dead %d · larvae eaten %d · born %d" % [s.stats.dead, s.stats.dead_by, s.stats.brood_dead, s.stats.cannibalized, s.stats.born])
	quit()
