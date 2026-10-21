extends SceneTree
## Dev: what the diggers are doing - the nest's air against its target, the planned work left, and each digger's
## state (carrying, biting, how far from the work face) every few game minutes.
##   godot --headless --path . --script res://tests/_dig_dump.gd -- <workers> <days first> [seed]
func _init():
	var Sim = load("res://scripts/sim/simulation.gd")
	var args := OS.get_cmdline_user_args()
	var s = Sim.new()
	s.setup(int(args[2]) if args.size() > 2 else 3, int(args[0]), false, "keeper")
	for d in int(args[1]):
		for i in s.TPD:
			s.step()
	var bites0: int = s.nest.excavated
	var vv := Vector3(34, 65, 32)
	var ea := Vector3(s.nest.entrance)
	var eb: Vector3 = s.nest.chambers[0].c
	var t := clampf((vv - ea).dot(eb - ea) / (eb - ea).length_squared(), 0.0, 1.0)
	print("entrance line dist ", vv.distance_to(ea + (eb - ea) * t), " r ", s.nest.entrance_r, " done ", s.nest.entrance_done, " ch0 ", eb)
	var cnt := 0
	var best := [1 << 30]
	var n0: int = s.nest._work_on_line(ea, eb, s.nest.entrance_r, false, best)
	var n1: int = s.nest._work_in_chamber(s.nest.chambers[0], best)
	print("line work ", n0, " chamber work ", n1, " count_work_left ", s.nest.count_work_left(), " work_at now ", s.nest.work_at)
	for ch in s.nest.chambers:
		print("  ch ", ch.c, " goal ", ch.goal, " open ", ch.get("open", true), " q ", s.nest.chamber_q(vv, ch), " from ", ch.get("from"))
	var wa: Vector3i = s.nest.work_at
	for dd in s.nest.DIRS:
		var n: Vector3i = wa + dd
		if s.nest.inside(n):
			print("work_at nb ", n, " rho ", s.nest.rho[s.nest.idx(n)], " plan ", s.nest._plan_at(n), " hard ", s.nest.is_hard(n), " p ", s.nest._dig_chance(n, wa, s.humidity), " entrance ", s.nest.entrance, " r ", s.nest.entrance_r)
	for k in 12:
		for i in s.TPD / 48:
			s.step()
		var ds := []
		for d in s.nest.diggers:
			var c: Vector3i = d.cell
			var wd: int = s.nest.work_dist[s.nest.idx(c)] if s.nest.work_dist.size() == s.nest.rho.size() else -9
			var bp := 0.0
			var why := ""
			for dd in s.nest.DIRS:
				var n: Vector3i = c + dd
				if s.nest.inside(n) and s.nest.rho[s.nest.idx(n)] >= s.nest.AIR:
					var pch: float = s.nest._dig_chance(n, c, s.humidity)
					if pch >= bp:
						bp = pch
						why = "plan%d hard%s y%d" % [s.nest._plan_at(n), s.nest.is_hard(n), n.y]
			ds.append("%s%s wd%d p%.3f %s" % ["C" if d.carry else ("B" if int(d.get("biting", 0)) > 0 else "-"), "" if not d.get("back", false) else "r", wd, bp, why])
		print("day %.2f workers %d air %d / %d  work_left %d at %s  dug %d  diggers %s" % [float(s.tick) / s.TPD, s.workers.size(), s.nest.air,
			s.target_air(), s.nest.work_left, s.nest.work_at, s.nest.excavated - bites0, ", ".join(ds)])
	quit()
