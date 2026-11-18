extends SceneTree
## PART 0.14 step 0.5: how long one simulation step takes in a colony started at N workers (colony_max raised on a copy
## of the species' table, so the colony keeps its size), and where it goes. Warm 0.3 day, then time 0.5 day.
##   godot --headless --path . --script res://tests/sim_cap_bench.gd -- <scenario> <workers> <seed> [native|gd] [substep]
## Prints one line "bench <scenario> w<N> s<seed> <mode>: <ms>/step  colony <ms> nest <ms> ants <ms> other <ms>  out <n>".

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var scen := a[0] if a.size() > 0 else "keeper"
	var nw := int(a[1]) if a.size() > 1 else 1000
	var seed := int(a[2]) if a.size() > 2 else 3
	var mode := a[3] if a.size() > 3 else "native"
	var sub := int(a[4]) if a.size() > 4 else 1
	var Sim = load("res://scripts/sim/simulation.gd")
	var s = Sim.new()
	if "native_off" in s:
		s.native_off = mode == "gd"
	s.setup(seed, nw, false, scen)
	s.sp = s.sp.duplicate(true)
	s.sp["colony_max"] = maxf(float(s.sp["colony_max"]), nw * 1.5)
	s.ant_substep = sub
	for i in int(0.3 * s.TPD):
		s.step()
	for k in s.prof:
		s.prof[k] = 0
	var n := int(0.5 * s.TPD)
	var out_sum := 0
	var t0 := Time.get_ticks_usec()
	for i in n:
		s.step()
		if i % 100 == 0:
			out_sum += s.outside.size()
	var us := Time.get_ticks_usec() - t0
	var nest_us: float = s.prof.get("nest", 0)
	print("bench %s w%d s%d %s sub%d: %.3f ms/step  colony %.3f  nest %.3f  ants %.3f  other %.3f  grid %.3f  out %d  workers %d  native-steps %d" % [
		scen, nw, seed, mode, sub, us / 1000.0 / n,
		(s.prof.get("colony", 0) - nest_us) / 1000.0 / n, nest_us / 1000.0 / n, s.prof.get("ants", 0) / 1000.0 / n,
		s.prof.get("other", 0) / 1000.0 / n, s.prof.get("grid", 0) / 1000.0 / n, out_sum / (n / 100), s.workers.size(), s.prof.get("native", 0)])
	var parts := ""
	for k in s.prof:
		if str(k).begins_with("c_") or str(k).begins_with("a_") or str(k).begins_with("d_"):
			parts += "%s %.3f  " % [k, s.prof[k] / 1000.0 / n]
	print("   parts: ", parts)
	quit()
