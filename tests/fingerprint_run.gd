extends SceneTree
## A colony's whole saved state, hashed once a game day: two builds (an older one in a worktree, the C++ part or not)
## that give the same lines gave the same colony to the last bit (PART 0.14 v0.14.1: the foragers in C++).
##   godot --headless --path . --script res://tests/fingerprint_run.gd -- <scenario> <workers> <seed> <days> [substep] [cap] [--no-native]
## cap: colony_max on a copy of the species' table (as the bench raises it); 0 = as it is.

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var scen := a[0]
	var nw := int(a[1])
	var seed := int(a[2])
	var days := int(a[3])
	var sub := int(a[4]) if a.size() > 4 else 1
	var cap := float(a[5]) if a.size() > 5 else 0.0
	var s = load("res://scripts/sim/simulation.gd").new()
	s.setup(seed, nw, false, scen)
	if cap > 0.0:
		s.sp = s.sp.duplicate(true)
		s.sp["colony_max"] = cap
	s.ant_substep = sub
	for d in days:
		for i in s.TPD:
			s.step()
		s.auto_care(d)
		var dd: Dictionary = s.to_dict()
		print("day %d workers %d out %d brood %d/%d/%d  %s" % [d + 1, s.workers.size(), s.outside.size(), s.eggs.size(),
			s.larvae.size(), s.pupae.size(), str(hash(var_to_bytes(dd))) + " " + var_to_bytes(dd).hex_encode().sha256_text().left(16)])
	quit()
