extends SceneTree
## Dev: a day in a colony's nest - each chamber's depth and temperature, and where the larvae, the cocoons and the
## queen are kept, every two hours (sim_warmth.gd).
##   godot --headless --path . --script res://tests/_warmth_dump.gd -- <wild|keeper> <workers> <days first> [heater]
func _init():
	var Sim = load("res://scripts/sim/simulation.gd")
	var args := OS.get_cmdline_user_args()
	var s = Sim.new()
	s.setup(5, int(args[1]), false, args[0])
	s.heater = args.size() > 3 and args[3] == "heater"
	for d in int(args[2]):
		for i in s.TPD:
			s.step()
	var deps := []
	for i in s.nest.chambers.size():
		deps.append("%.1f" % s.chamber_depth_cm(i))
	print("%s day %d  chambers at cm %s" % [args[0], s.day(), ", ".join(deps)])
	for h in 12:
		for i in s.TPD / 12:
			s.step()
		var ts := []
		for i in s.nest.chambers.size():
			ts.append("%.1f" % s.chamber_temp(i))
		var at := {}
		for kind in ["eggs", "larvae", "pupae"]:
			for b in s.get(kind):
				var k := "%s@%d" % [kind[0], int(b.get("c", -1))]
				at[k] = int(at.get(k, 0)) + 1
		print("%05.2f h  air %.1f  top %.1f  chambers %s  | queen in %d  larvae->%d  pupae->%d  %s" % [s.time_of_day() * 24.0, s.climate.air,
			s.climate.nest, ", ".join(ts), s.queen_at, s.brood_at.larvae, s.brood_at.pupae, at])
	quit()
