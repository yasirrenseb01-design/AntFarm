extends SceneTree
## Dev: what is in a grown colony's soil (user://growtest/<name>/saves/slot<n>) - stones, roots, clay and sand depth.
##   godot --headless --path . --script res://tests/_soil_dump.gd -- <name> <slot>
func _init():
	var Store = load("res://scripts/game/save_store.gd")
	var Sim = load("res://scripts/sim/simulation.gd")
	var args := OS.get_cmdline_user_args()
	Store.base = "user://growtest/%s/" % args[0]
	var d: Dictionary = Store.load_slot(int(args[1]))
	var s = Sim.new()
	s.from_dict(d.sim)
	print("soil ", s.nest.soil)
	print("chambers ", s.nest.chambers.size(), " volume ", s.nest.volume_cm3(), " depth ", s.nest.depth_cm(), " traits ", s.trait_words())
	for st in s.nest.soil.get("stones", []):
		var c := Vector3(st[0], st[1], st[2])
		if s.nest._open_near(c, float(st[3]) + 1.5):
			print("stone by a tunnel: ", c, " r ", st[3])
	quit()
