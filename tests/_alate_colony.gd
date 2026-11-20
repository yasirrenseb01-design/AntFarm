extends SceneTree
## Dev (PART 0.14): a wild colony for looking at the alates in the views - written to user://growtest/<name>/saves/slot1,
## opened read-only with --testsave=<name> --slot=1 (add winged ones with --alates=<g>,<m>; scripts/dev/dev_tools.gd).
##   godot --headless --path . --script res://tests/_alate_colony.gd -- [workers] [days] [name] [seed]

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var Sim = load("res://scripts/sim/simulation.gd")
	var Store = load("res://scripts/game/save_store.gd")
	var name: String = a[2] if a.size() > 2 else "alates"
	Store.base = "user://growtest/%s/" % name
	var s = Sim.new()
	s.setup(int(a[3]) if a.size() > 3 else 4, int(a[0]) if a.size() > 0 else 300, false, "wild")
	for i in int((float(a[1]) if a.size() > 1 else 3.0) * s.TPD):
		s.step()
	Store.save(1, s)
	print("saved %s slot 1: %d workers, %s" % [name, s.workers.size(), s.date_text()])
	quit()
