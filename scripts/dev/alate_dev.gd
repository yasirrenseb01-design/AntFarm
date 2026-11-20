extends RefCounted
## Dev options of PART 0.14 (the alates, the flight, the queens on the plot, the founding tubes), split out of
## dev_tools.gd (its size: docs/WORKFLOW.md). Options listed at the top of scripts/game/main.gd; m = main (dev_tools).


## With --shot, before the frames: --alates=<gynes>,<males>[,<gyne larvae>,<male larvae>], --queens=<n>, --flight,
## --tubes=<n>.
static func setup(m) -> void:
	var sim = m.sim
	var o: Dictionary = m._opts
	if o.has("alates"):
		# winged ones put in the nest as they come out of their cocoons (sim/alates.gd); then that many larvae turned
		# into theirs, grown halfway (their own chambers)
		var na: PackedStringArray = String(o["alates"]).split(",")
		for k in [["g", 0], ["m", 1]]:
			for i in (int(na[k[1]]) if na.size() > k[1] else 0):
				sim.Alates.eclose(sim, {"x": k[0], "q": 1.0})
		var li := 0
		for k in [["g", 2], ["m", 3]]:
			for i in (int(na[k[1]]) if na.size() > k[1] else 0):
				if li < sim.larvae.size():
					sim.larvae[li]["x"] = k[0]
					sim.larvae[li].p = 0.5
					li += 1
		for i in 60:
			sim.step()
		print("alates (dev): %d in the nest, brood_at %s" % [sim.alates.size(), sim.brood_at])
	if o.has("queens"):
		# mated queens come down near the nest, as after a flight day (sim/wild_queens.gd), the camera on them
		var g: RandomNumberGenerator = sim.WildQueens._gen(sim, 77)
		for i in int(o["queens"]):
			sim.WildQueens._land(sim, g, g.randf_range(0.8, 1.2), "area")
			var q: Dictionary = sim.ground_queens[-1]
			var at: Vector2 = sim.nest_pos + Vector2.from_angle(i * 1.9) * (30.0 + 12.0 * i)
			q.x = at.x
			q.y = at.y
	if o.has("flight"):
		# (with --alates) those in the nest ready, and their flight now - as on a flight afternoon (sim/alates.gd)
		for al in sim.alates:
			al.age = 30.0
			if al.x == "g":
				al.w = sim.Alates.GYNE_COST
		sim.Alates._fly(sim)
	if (o.has("queens") or o.has("flight")) and m.mode == "outworld":
		m.outworld.target_t = Vector3(sim.nest_pos.x, 0, sim.nest_pos.y) * m.outworld.U
		m.outworld.target = m.outworld.target_t
	if o.has("tubes"):
		m.home.tubes = []                    # (that many caught queens in the desk's tubes, in memory)
		for i in mini(int(o["tubes"]), m.home.MAX_TUBES):
			m.home.tubes.append({"w": 1.0, "from": "area", "day": 1})


## Each frame of the shot: --catch (with --queens) clicks the first queen on the ground at frame 60.
static func frame(m, i: int) -> void:
	if not m._opts.has("catch"):
		return
	if i == 60 and m.mode == "outworld" and not m.outworld._flight._qxf.is_empty():
		var qx: Transform3D = m.outworld._flight._qxf.values()[0]
		m.hud.ant_tip.test_mouse = m.outworld._cam.unproject_position(qx.origin + Vector3.UP * 0.3)
	if i == 70:
		print("catch (dev): %d queens on the ground, tubes %s" % [m.sim.ground_queens.size(), m.home.tubes])


## --hover=alate: the first winged one drawn in the nest (a male first).
static func hover(m) -> Vector3:
	var al: Array = m.nest_view._alates._xf.m + m.nest_view._alates._xf.g
	return (al[0] as Transform3D).origin + Vector3.UP * 0.4 if not al.is_empty() else Vector3.INF
