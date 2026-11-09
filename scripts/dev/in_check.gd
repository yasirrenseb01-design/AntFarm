extends RefCounted
## Dev checks of ants coming into the nest (v0.12.16; the keeper, 2026-10-24: an ant followed in from the ground
## "warped" to the deepest chamber, not in by the entrance - nest_bind._bind_tick). Started from dev_tools._dev_nest_after.
##   --follow-in[=<n>]   after 2 s on the ground, the keeper's "go to" pressed on a forager out there that had a body in
##                       the nest before it went out (or any, if none has); once it goes in and the nest opens, where its
##                       body is drawn - steps from the entrance - is printed, n times over (default 3), then it quits
##   --in-check          (with --nest-after) 0.1 s after the nest opened, where the bodies of workers just in from
##                       outside are drawn; all of them should be walking in from the entrance

var g                    # the game (main.gd)
var left := 0
var wid := -1
var t0 := 0.0


## true: --follow-in has taken over (nothing else of --nest-after is done).
## (also --grow-box=<voxels> with --nest-after: 1 s after the nest opened the box of soil held is grown that far every
## way, as the planner does when a chamber is planned out past it - the view laying itself out again while open)
static func start(game) -> bool:
	var c = new()
	c.g = game
	if game._opts.has("grow-box"):
		game.get_tree().create_timer(float(game._opts["nest-after"]) + 1.0).timeout.connect(func():
			var n = game.sim.nest
			var by := float(game._opts["grow-box"])
			var t0 := Time.get_ticks_usec()
			var d0: int = n.dirty.size()
			var grew: bool = n.extend_xz(Vector2(n.x_lo - by, n.z_lo - by), Vector2(n.nx + by, n.nz + by))
			print("grow-box: dirty %d -> %d" % [d0, n.dirty.size()])
			print("grow-box: %s, box x %d..%d z %d..%d, %.1f ms" % [grew, n.x_lo, n.nx, n.z_lo, n.nz, (Time.get_ticks_usec() - t0) / 1000.0])
			if game._opts.has("grow-shot"):
				# (--grow-shot=<png>: the picture 8 s after it grew, the soil's pieces laid out again by then; how many were
				# still waiting at 2 s and 8 s printed)
				game.get_tree().create_timer(2.0).timeout.connect(func(): print("grow-box: %d soil pieces waiting at 2 s" % game.nest_view._queue.size()))
				game.get_tree().create_timer(8.0).timeout.connect(func():
					print("grow-box: %d soil pieces waiting at 8 s" % game.nest_view._queue.size())
					await RenderingServer.frame_post_draw
					game.get_viewport().get_texture().get_image().save_png(String(game._opts["grow-shot"]))))
	if game._opts.has("queen-watch"):
		# (--queen-watch=<s> with --nest-after and --queen-to: 0.5 s after the nest opened, the "Queen" button pressed;
		# then each frame for s seconds, while she walks, whether she is drawn - the keeper, 2026-11-10: the camera sent to
		# her, she walked to another chamber and turned invisible)
		var w := {"walk": 0, "shown": 0, "frames": 0}
		game.get_tree().create_timer(float(game._opts["nest-after"]) + 0.5).timeout.connect(func():
			game.nest_view.focus("queen")
			var sim = game.sim
			var qt := clampi(int(game._opts.get("queen-to", "0")), 0, sim.nest.chambers.size() - 1)
			if qt == sim.queen_at:
				qt = (qt + sim.nest.chambers.size() / 2) % sim.nest.chambers.size()
			sim.nest.widen_way(sim.nest.chambers[sim.queen_at].c, sim.nest.chambers[qt].c, sim.QUEEN_WAY)   # (as the colony sends her)
			print("queen-watch: chamber %d -> %d" % [sim.queen_at, qt])
			sim.queen_at = qt
			sim._queen_stay = 0.0
			game.nest_view._refresh_spots()
			var t_end := Time.get_ticks_msec() + int(float(game._opts["queen-watch"]) * 1000.0)
			var tick := func():
				if Time.get_ticks_msec() > t_end:
					return
				w.frames += 1
				if not game.nest_view._queen_path.is_empty():
					w.walk += 1
					if game.nest_view._queen_mm.instance_count > 0:
						w.shown += 1
			game.get_tree().process_frame.connect(tick)
			if game._opts.has("queen-shot"):
				# (--queen-shot=<base>: pictures 3, 8 and 14 s after she set off, <base>_3.png ...)
				if game._opts.has("queen-speed"):
					game.speed = float(game._opts["queen-speed"])     # (--queen-speed=<x>: the game's pace while she is watched)
				for sec in ([3, 8, 14] if not game._opts.has("queen-shots") else Array(String(game._opts["queen-shots"]).split(",")).map(func(v): return int(v))):
					game.get_tree().create_timer(float(sec)).timeout.connect(func():
						await RenderingServer.frame_post_draw
						var nv = game.nest_view
						var mt: Transform3D = nv._queen_mm.get_instance_transform(0) if nv._queen_mm.instance_count > 0 else Transform3D()
						print("queen-shot %d s: drawn %s at %s (drawn %s, scale %.2f, on screen %s, behind %s), spot %s, busy %s, path %d, target %s, x-ray %s" % [sec,
							nv._queen_mm.instance_count > 0, str(nv._queen_xf.origin.snapped(Vector3.ONE * 0.1)), str(mt.origin.snapped(Vector3.ONE * 0.1)),
							mt.basis.get_scale().x, str(nv._cam.unproject_position(mt.origin).round()), nv._cam.is_position_behind(mt.origin),
							str((nv._spots.queen as Vector3).snapped(Vector3.ONE * 0.1)), nv._queen_busy(), nv._queen_path.size(), str(nv.target.snapped(Vector3.ONE * 0.1)), nv.xray])
						game.get_viewport().get_texture().get_image().save_png("%s_%d.png" % [game._opts["queen-shot"], sec]))
			game.get_tree().create_timer(float(game._opts["queen-watch"]) + 0.2).timeout.connect(func():
				print("queen-watch: %d frames, walking %d, drawn while walking %d (%.0f%%), following %s" % [w.frames, w.walk, w.shown,
					100.0 * w.shown / maxi(1, w.walk), game.nest_view.follow_wid == -2])))
	if game._opts.has("follow-in"):
		c.left = int(game._opts.get("follow-in", "3"))
		game.get_tree().create_timer(2.0).timeout.connect(c._pick)
		game.set_meta("in_check", c)           # (kept alive while its timers run)
		return true
	if game._opts.has("in-check"):
		game.get_tree().create_timer(float(game._opts["nest-after"]) + 0.1).timeout.connect(c._report)
		game.set_meta("in_check", c)
	return false


func _report() -> void:
	var nv = g.nest_view
	var ef: Dictionary = nv._fields.get(-1, {})
	var near := 0
	var far := []
	for m in nv._mates:
		var id := int(m.get("wid", -1))
		if id < 0 or m.get("leaving", false):
			continue
		for w in g.sim.workers:
			if w.id == id and nv._came_in_now(w):
				var d := int(ef.get(m.cell, -1))
				if d >= 0 and d <= 8:
					near += 1
				else:
					far.append(d)
	var latest := -1
	for w in g.sim.workers:
		latest = maxi(latest, int(w.came_in))
	print("in-check: just in %d, by the entrance %d, elsewhere %d %s  io %s  (outside %d, last in %d ticks ago)" % [near + far.size(),
		near, far.size(), str(far), str(nv.io), g.sim.outside.size(), g.sim.tick - latest])


func _pick() -> void:
	var had := {}
	for m in g.nest_view._mates:
		had[int(m.get("wid", -1))] = true
	var best = null
	for w in g.sim.outside:
		if w.dead:
			continue
		if best == null or (had.has(w.id) and not had.has(best.id)):
			best = w
	if best == null:
		g.get_tree().create_timer(1.0).timeout.connect(_pick)
		return
	wid = best.id
	t0 = Time.get_ticks_msec() / 1000.0
	print("follow-in: following %d (a body in the nest before: %s)" % [best.id, had.has(best.id)])
	g.hud.go_to_ant(best.id)
	_wait()


func _wait() -> void:
	var w = null
	for x in g.sim.workers:
		if x.id == wid:
			w = x
	if w == null or (Time.get_ticks_msec() / 1000.0 - t0) > 240.0:
		print("follow-in: lost %d" % wid)
		_next()
		return
	if w.state != g.sim.Ant.IN_NEST or g.mode != "nest":
		g.get_tree().create_timer(0.1).timeout.connect(_wait)
		return
	g.get_tree().create_timer(0.3).timeout.connect(_measure)


func _measure() -> void:
	var ef: Dictionary = g.nest_view._fields.get(-1, {})
	var d := -1
	var role := ""
	for m in g.nest_view._mates:
		if int(m.get("wid", -1)) == wid:
			d = int(ef.get(m.cell, -1))
			role = String(m.role)
	var deep := 0
	for k in ef:
		deep = maxi(deep, int(ef[k]))
	print("follow-in: %d in; its body %d steps from the entrance (deepest %d), role %s, io %s" % [wid, d, deep, role, str(g.nest_view.io)])
	_next()


func _next() -> void:
	left -= 1
	if left <= 0:
		g.get_tree().quit()
		return
	g.hud._apply_mode("outworld")
	g._set_mode("outworld")
	g.get_tree().create_timer(5.0).timeout.connect(_pick)
