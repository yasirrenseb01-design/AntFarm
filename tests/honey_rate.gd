extends SceneTree
## How much sugar a colony brings home from a drop of honey a day (the keeper's honey, kept topped up), with nothing
## else to eat: for comparing the foraging economy before and after a change to how long ants drink.
##   godot --headless --path . --script res://tests/honey_rate.gd -- [workers] [days] [seed] [distance px]

const Sim := preload("res://scripts/sim/simulation.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var workers: int = int(args[0]) if args.size() > 0 else 100
	var days: int = int(args[1]) if args.size() > 1 else 3
	var seed_v: int = int(args[2]) if args.size() > 2 else 5
	var dist: float = float(args[3]) if args.size() > 3 else 150.0
	var s = Sim.new()
	s.setup(seed_v, workers, false, "keeper")
	s.foods.clear()
	var at: Vector2 = s.nest_pos + Vector2(dist, 0)
	if at.x > s.WORLD.x - 40:
		at = s.nest_pos - Vector2(dist, 0)
	s.rocks.clear()
	s.rock.fill(0)
	s._restamp_rocks()
	s.place_food("honey", at)
	s._food_dirty = true
	var got := 0
	var drinking_max := 0
	var t := 0
	for d in days:
		var before: int = s.stats.sugar_in
		for i in s.TPD:
			s.sugar = 0.0                   # (always hungry for it)
			s.step()
			t += 1
			if s.foods.is_empty() or s.foods.filter(func(f): return f.kind == "honey").is_empty():
				s.place_food("honey", at)
			if t % 60 == 0:
				var n := 0
				for a in s.outside:
					if a.busy > 0 and a.act == 10:
						n += 1
				drinking_max = maxi(drinking_max, n)
		print("day %d: sugar in %d" % [d + 1, s.stats.sugar_in - before])
		got += s.stats.sugar_in - before
	print("sugar a day %.1f  (most drinking at once %d)" % [float(got) / days, drinking_max])
	quit()
