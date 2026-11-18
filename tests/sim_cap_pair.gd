extends SceneTree
## PART 0.14 step 0.5's bar, measured fairly on a busy machine: colony A (as the game was: GDScript, the old cap) and
## colony B (the new) stepped in turns of 60 steps in one process, so both meet the same load; warm 0.3 day, time 0.5 day.
##   godot --headless --path . --script res://tests/sim_cap_pair.gd -- <scenario> <seed> [workers_a mode_a workers_b mode_b]
## (mode: native | gd; default 1000 gd 2000 native) -> "pair <scenario> s<seed>: A ... ms/step  B ... ms/step  B/A ..."

var parts := ["colony", "nest", "ants"]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var scen := a[0] if a.size() > 0 else "keeper"
	var seed := int(a[1]) if a.size() > 1 else 3
	var spec := [[int(a[2]) if a.size() > 2 else 1000, a[3] if a.size() > 3 else "gd"],
		[int(a[4]) if a.size() > 4 else 2000, a[5] if a.size() > 5 else "native"]]
	var Sim = load("res://scripts/sim/simulation.gd")
	var sims := []
	for sp in spec:
		var s = Sim.new()
		s.native_off = sp[1] == "gd"
		s.setup(seed, sp[0], false, scen)
		s.sp = s.sp.duplicate(true)
		s.sp["colony_max"] = maxf(float(s.sp["colony_max"]), sp[0] * 1.5)
		for i in int(0.3 * Sim.TPD):
			s.step()
		for k in s.prof:
			s.prof[k] = 0
		sims.append(s)
	var us := [0, 0]
	var n := int(0.5 * Sim.TPD)
	var done := 0
	while done < n:
		for j in 2:
			var t0 := Time.get_ticks_usec()
			for i in 60:
				sims[j].step()
			us[j] += Time.get_ticks_usec() - t0
		done += 60
	var line := "pair %s s%d:" % [scen, seed]
	for j in 2:
		var s = sims[j]
		var nest: float = s.prof.get("nest", 0)
		line += "  %s %d %s %.3f ms/step (colony %.3f nest %.3f ants %.3f, out %d)" % ["AB"[j], s.workers.size(), spec[j][1],
			us[j] / 1000.0 / done, (s.prof.colony - nest) / 1000.0 / done, nest / 1000.0 / done, s.prof.ants / 1000.0 / done,
			s.outside.size()]
	line += "  B/A %.2f" % (float(us[1]) / us[0])
	print(line)
	quit()
