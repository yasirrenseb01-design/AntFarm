extends SceneTree
## (dev, PART 0.12 step 5c) How far a grown keeper's nest spreads in the tank's soil: a colony grown by year_run.gd
## (user://growtest/<name>/, slot = year; read, never written) run on with the same simple keeper, printing every 30
## days the box of soil held, how far the open space reaches (x, z: voxels; 1.5 mm each) and the chambers.
##   godot --headless --path . --script res://tests/_spread_run.gd -- <name> <slot> <days> [save-name]
## save-name: the colony at the end saved to user://growtest/<save-name>/ slot 1 (open it with --testsave=<save-name>)
func _init():
	var Sim = load("res://scripts/sim/simulation.gd")
	var Store = load("res://scripts/game/save_store.gd")
	var args := OS.get_cmdline_user_args()
	Store.base = "user://growtest/%s/" % args[0]
	var d = Store.load_slot(int(args[1]))
	if d == null or not d is Dictionary or not d.has("sim"):
		print("no colony in ", args[0], " slot ", args[1])
		quit()
		return
	var s = Sim.new()
	s.from_dict(d.sim)
	var days := int(args[2])
	var r := RandomNumberGenerator.new(); r.seed = 3
	_line(s, 0)
	var t0 := Time.get_ticks_msec()
	for day in days:
		for i in s.TPD: s.step()
		if s.humidity < 0.45: s.add_water()
		s.fridge_on = s.doy_f() > 320.0 or s.doy_f() < 20.0
		if day % 3 == 0 and s.climate.season_mean() > 8.0:
			for k in 1 + s.workers.size() / 40:
				s.place_food("cricket", s.food_spot(300.0, 560.0, r))
		if s.sugar < s.sugar_cap() * 0.7 and s.climate.season_mean() > 8.0:
			for k in 1 + s.workers.size() / 50:
				s.place_food("honey", s.food_spot(300.0, 560.0, r))
		if (day + 1) % 30 == 0:
			_line(s, day + 1)
	print("done in %.1f min" % ((Time.get_ticks_msec() - t0) / 60000.0))
	if args.size() > 3:
		Store.base = "user://growtest/%s/" % args[3]
		Store.save(1, s)
		print("saved to ", Store.base)
	quit()


func _line(s, day: int) -> void:
	var n = s.nest
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-1, -1)
	for z in range(n.z_lo, n.nz):
		for x in range(n.x_lo, n.nx):
			if n.proj.is_empty():
				break
			for y in range(n.y_lo, n.ny):
				if n.rho[n.idx(Vector3i(x, y, z))] < n.AIR:
					lo = Vector2i(mini(lo.x, x), mini(lo.y, z))
					hi = Vector2i(maxi(hi.x, x), maxi(hi.y, z))
					break
	print("day %3d %s workers %4d | box x %d..%d z %d..%d (%dx%d of tank %dx%d) | open x %d..%d z %d..%d = %.1f x %.1f cm | %d chambers, %.1f cm3, depth %.1f cm | ways out %s" % [
		day, s.date_text(), s.workers.size(), n.x_lo, n.nx, n.z_lo, n.nz, n.wx(), n.wz(), n.tank.x, n.tank.y,
		lo.x, hi.x, lo.y, hi.y, (hi.x - lo.x + 1) * 0.15, (hi.y - lo.y + 1) * 0.15, n.chambers.size(), n.volume_cm3(), n.depth_cm(), str(n.exits.map(func(e): return "%s%s" % ["open " if e.open else "digging ", str(Vector3i((e.b as Vector3).round()))]))])
