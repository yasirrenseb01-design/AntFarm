extends SceneTree
## PART 0.12 step 1: how long one simulation step takes in a grown colony (user://growtest/<name>/ slot <n>, read only),
## at ant_substep 4 (as the time away is worked out) and 1 (play at 1x-5x), and where it goes.
##   godot --headless --path . --script res://tests/big_sim_bench.gd -- <name> <slot> <days>

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var Store = load("res://scripts/game/save_store.gd")
	Store.base = "user://growtest/%s/" % a[0]
	var d: Dictionary = Store.load_slot(int(a[1]))
	var Sim = load("res://scripts/sim/simulation.gd")
	var days := float(a[2])
	for sub in [4, 1]:
		var s = Sim.new()
		s.from_dict(d.sim)
		s.ant_substep = sub
		var n := int(days * s.TPD)
		var inside := 0
		for w in s.workers:
			if w.state == 0: inside += 1
		var t0 := Time.get_ticks_usec()
		for i in n:
			s.step()
		var us := Time.get_ticks_usec() - t0
		var ms_step := us / 1000.0 / n
		print("%s/%s substep %d  workers %d (in nest %d)  %.3f ms a step  -> 120 days away %.1f min" % [a[0], a[1], sub,
			s.workers.size(), inside, ms_step, ms_step * 120.0 * s.TPD / 60000.0])
		var parts := ""
		for k in ["colony", "grid", "ants", "nest", "other"]:
			parts += "%s %.1f s  " % [k, s.prof.get(k, 0) / 1000000.0]
		print("   parts over %.0f days: %s" % [days, parts])
	print("static memory %.0f MB" % (OS.get_static_memory_usage() / 1048576.0))
	quit()
