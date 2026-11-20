extends SceneTree
## Dev (PART 0.14): the wild plot's wind (climate.wind_at) over a year, for a few colony seeds: the day's mean, the
## afternoon's (15:00) - and how many July-August afternoons are calm enough for a flight (< 6.3 m/s [A5], < 1.7 [A4]).

func _init() -> void:
	var C = load("res://scripts/sim/climate.gd")
	var c = C.new(RandomNumberGenerator.new())
	c.scenario = "wild"
	for seed in [5, 11, 22, 1234567]:
		var all := []
		var aft := []
		var ok := 0
		var calm := 0
		var n := 0
		for d in 365:
			var m := 0.0
			for h in 24:
				m += c.wind_at(seed, d, h / 24.0) / 24.0
			all.append(m)
			var a: float = c.wind_at(seed, d, 0.63)
			aft.append(a)
			if d % 365 >= 182 and d % 365 < 243:
				n += 1
				ok += 1 if a < 6.3 else 0
				calm += 1 if a < 1.7 else 0
		all.sort()
		aft.sort()
		print("seed %d: day mean m/s  10%% %.1f  50%% %.1f  90%% %.1f  max %.1f | 15:00  10%% %.1f  50%% %.1f  90%% %.1f | Jul-Aug afternoons < 6.3: %d/%d, < 1.7: %d" % [
			seed, all[36], all[182], all[328], all[364], aft[36], aft[182], aft[328], ok, n, calm])
	quit()
