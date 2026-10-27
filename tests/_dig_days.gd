extends SceneTree
## Dev probe: the game days a young garden colony has diggers at work (to stage the nest view on one).
##   godot --headless --path . --script res://tests/_dig_days.gd -- <seed> <days>
const SIM := "res://scripts/sim/simulation.gd"

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var sim = load(SIM).new()
	sim.setup(int(a[0]), 14, false, "wild")
	var by_day := {}
	for t in int(float(a[1]) * sim.TPD):
		sim.step()
		if t % 600 == 0 and sim.nest.diggers.size() > 0:
			by_day[int(t / sim.TPD)] = maxi(int(by_day.get(int(t / sim.TPD), 0)), sim.nest.diggers.size())
	print("days with diggers (most at once): ", by_day)
	quit()
