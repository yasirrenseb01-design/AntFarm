extends "res://scripts/game/parts/main_camera.gd"
## Game, layer 3 of 4: developer tools — screenshots (--shot), headless self-tests (--selftest),
## the test keeper and the nest side-view PNG. Options are listed at the top of scripts/game/main.gd.


var _walker = null          # --at-ant=walker: the forager the camera follows
var _watch_food = null       # --at-ant=hauler: the prey being hauled home
var _watch_creature = null   # --watch-fight=<n>: the enemy the camera follows once n ants hold it

# ---------------------------------------------------------------- tools

func _take_shot() -> void:
	var days := float(_opts.get("warm", "0"))
	for i in int(days * sim.TPD):
		sim.step()
		if _opts.has("autokeep") and sim.tick % sim.TPD == 0:
			_keeper(sim.day())
	if _opts.has("tod"):
		var target := int(float(_opts["tod"]) * sim.TPD)
		while sim.tick % sim.TPD != target:
			sim.step()
	if _opts.has("zoom"):
		_zoom_t *= float(_opts["zoom"])
		camera.zoom = Vector2.ONE * _zoom_t
		var fc: PackedStringArray = _opts.get("focus", "%d,%d" % [sim.nest_pos.x, sim.nest_pos.y]).split(",")
		_center_on(Vector2(float(fc[0]), float(fc[1])))
	if _opts.has("rock"):
		# drop a stone (keeper's tool) and look at it: --rock=<dx>,<dy>,<r> from the nest entrance
		var rp: PackedStringArray = String(_opts["rock"]).split(",")
		var at: Vector2 = sim.nest_pos + Vector2(float(rp[0]), float(rp[1]))
		print("rock placed: ", sim.add_rock(at, float(rp[2]) if rp.size() > 2 else 10.0), " climb ", sim.rocks[-1].get("climb", false))
		if mode == "outworld":
			outworld.target_t = Vector3(at.x, 0, at.y) * outworld.U
			outworld.target = outworld.target_t
	if _opts.has("enemy"):
		# stage a fight: an enemy beside the nest, then let it run for --fight=<ticks>
		sim.enemies = false
		sim._spawn_creature(_opts["enemy"])
		var ep: PackedStringArray = String(_opts.get("enemy-at", "%d,%d" % [sim.nest_pos.x + 120, sim.nest_pos.y + 40])).split(",")
		sim.creatures[-1].pos = Vector2(float(ep[0]), float(ep[1]))
		sim.creatures[-1].ang = float(_opts.get("enemy-ang", "3.1"))
		for i in int(_opts.get("fight", "0")):
			sim.step()
		if _opts.has("watch-fight"):
			# run on until ants are holding the enemy down (and follow it in --seq): fight animation checks
			for i in sim.TPD:
				if not sim.creatures.is_empty() and int(sim.creatures[-1].get("held", 0)) >= int(_opts["watch-fight"]):
					break
				if i % 60 == 0 and not sim.creatures.is_empty():
					var cc: Dictionary = sim.creatures[-1]
					print("  t%d held %d hp %.1f pos %s" % [i, int(cc.get("held", 0)), float(cc.get("hp", 0)), str(cc.pos)])
				sim.step()
			if not sim.creatures.is_empty():
				_watch_creature = sim.creatures[-1]
			print("watch-fight: creatures %d held %s" % [sim.creatures.size(), str(sim.creatures[-1].get("held", 0)) if not sim.creatures.is_empty() else "-"])
		var look_at := Vector2.INF
		if not sim.creatures.is_empty():
			look_at = sim.creatures[-1].pos
		else:
			for f in sim.foods:
				if String(f.kind).ends_with("_dead"):
					look_at = f.pos            # the ants won: look at the body
		if look_at != Vector2.INF and mode == "outworld" and not _opts.has("target"):
			var cp: Vector2 = look_at
			outworld.target_t = Vector3(cp.x, 0, cp.y) * outworld.U
			outworld.target = outworld.target_t     # the camera options below snap to these
	if _opts.has("food-left"):
		for f in sim.foods:
			if f.kind == "cricket":
				f.amt = f.cap * float(_opts["food-left"])
				if _opts.has("food-age"):
					f.age = float(_opts["food-age"])
					f.found = true
	if _opts.has("rain"):
		sim.climate.rain_ticks = sim.TPD
	if mode == "outworld":
		for k in ["yaw", "pitch", "dist"]:
			if _opts.has(k):
				outworld.set(k + "_t" if k != "dist" else "dist_t", float(_opts[k]))
		if _opts.has("target"):
			var tp: PackedStringArray = String(_opts["target"]).split(",")
			outworld.target_t = Vector3(float(tp[0]), float(tp[1]), float(tp[2]))
		if _opts.get("at-ant", "") == "act9" or _opts.get("at-ant", "") == "act10" or _opts.get("at-ant", "") == "act2":
			# run on until some forager is busy at that kind of food, then look at it
			var want := int(String(_opts["at-ant"]).trim_prefix("act"))
			var found = null
			for i in sim.TPD * 2:
				for a in sim.outside:
					if a.busy > 20 and a.act == want:
						found = a
				if found != null:
					break
				sim.step()
			if found != null:
				var at: Vector2 = found.pos
				for f in sim.foods:
					if f.pos.distance_to(found.pos) < f.r + 14.0:
						at = f.pos
				outworld.target_t = Vector3(at.x, 0, at.y) * outworld.U + Vector3(0, float(_opts.get("lift", "0")), 0)
		elif _opts.get("at-ant", "") == "hauler":
			# drop a dead fly a little way out, run on until nestmates are hauling it home, then follow it
			sim.place_food("fly", sim.nest_pos + Vector2(110, 50))
			var fly: Dictionary = sim.foods[-1]
			for i in sim.TPD:
				if sim.outside.filter(func(x): return x.state == sim.Ant.DRAG).size() >= 2 or not sim.foods.has(fly):
					break
				sim.step()
			print("hauler: draggers %d" % sim.outside.filter(func(x): return x.state == sim.Ant.DRAG).size())
			_watch_food = fly
			outworld.target_t = Vector3(fly.pos.x, 0, fly.pos.y) * outworld.U
		elif _opts.get("at-ant", "") == "climber":
			# run on until a forager starts up the glass wall, then follow it (wall-climb checks)
			for i in sim.TPD:
				for a in sim.outside:
					if a.busy > sim.WALL_TICKS - 20 and a.act == sim.ACT_WALL:
						_walker = a
				if _walker != null:
					break
				sim.step()
			print("climber: ", _walker != null)
			if _walker != null:
				outworld.target_t = Vector3(_walker.pos.x, 0, _walker.pos.y) * outworld.U + Vector3(0, 8, 0)
		elif _opts.get("at-ant", "") == "carrier":
			# run on until a forager is walking home with a load in its mandibles, then follow it (carry pose)
			if not sim.foods.any(func(f): return f.type == sim.Ant.PROTEIN):
				sim.place_food("cricket", sim.nest_pos + Vector2(140, 60))
			for i in sim.TPD:
				for a in sim.outside:
					if a.busy <= 0 and a.carry == sim.Ant.PROTEIN and a.pos.distance_to(sim.nest_pos) > 30.0:
						_walker = a
				if _walker != null:
					break
				sim.step()
			if _walker != null:
				outworld.target_t = Vector3(_walker.pos.x, 0, _walker.pos.y) * outworld.U
		elif _opts.get("at-ant", "") == "walker":
			# run on until a forager is out walking (not busy), then look at it (gait checks)
			for i in sim.TPD:
				for a in sim.outside:
					if a.busy <= 0 and a.state in [sim.Ant.SEARCH, sim.Ant.HOME] and a.pos.distance_to(sim.nest_pos) > 40.0:
						_walker = a
				if _walker != null:
					break
				sim.step()
			if _walker != null:
				outworld.target_t = Vector3(_walker.pos.x, 0, _walker.pos.y) * outworld.U
		elif _opts.has("at-ant") and not sim.outside.is_empty():
			var a = sim.outside[int(_opts["at-ant"]) % sim.outside.size()]
			outworld.target_t = Vector3(a.pos.x, 0, a.pos.y) * outworld.U
		if _opts.has("at-food"):
			# drop one of that food beside the nest and look at it (models: --at-food=fly)
			var fp: Vector2 = sim.nest_pos + Vector2(70, 30)
			sim.place_food(String(_opts["at-food"]), fp)
			outworld.target_t = Vector3(fp.x, 0, fp.y) * outworld.U
		outworld.snap_camera()
	if _opts.get("view", "surface") == "nest":
		hud._apply_mode("nest")
		_set_mode("nest")
		# only override the view's own starting camera when asked
		if _opts.has("yaw"):
			nest_view.yaw = float(_opts["yaw"])
		if _opts.has("pitch"):
			nest_view.pitch = float(_opts["pitch"])
		if _opts.has("dist"):
			nest_view.cam_dist = float(_opts["dist"])
		if _opts.has("cut"):
			nest_view.cut_offset = float(_opts["cut"])
		nest_view.snap_camera()
		if _opts.has("xray"):
			nest_view.set_xray(true)
		if _opts.has("look"):
			nest_view._refresh_spots()
			nest_view.focus(_opts["look"])
			nest_view.target = nest_view.target_t
			nest_view.cam_dist = nest_view.dist_t
			if _opts.has("dist"):                         # (closer or farther than the view's own choice)
				nest_view.dist_t = float(_opts["dist"])
				nest_view.cam_dist = nest_view.dist_t
		# act out life-cycle moments on demand: --anim=egg,pupate,eclose
		for k in String(_opts.get("anim", "")).split(",", false):
			nest_view._refresh_spots()
			match k:
				"egg": nest_view._start_egg()
				"pupate": nest_view._start_pupate(1.0)
				"eclose":
					# a real cocoon in the pile hatches (dev: take one out of the simulation, as hatching does)
					nest_view._update_brood()
					if not sim.pupae.is_empty():
						var pp: Dictionary = sim.pupae.pop_back()
						nest_view._start_eclose(float(pp.get("s", 1.0)))
						if _opts.has("trace"):
							print("ECLOSE anims ", nest_view._anims.map(func(x): return [x.k, x.get("p")]), " helpers ", nest_view._anims[-1].get("helpers", []).size() if not nest_view._anims.is_empty() else -1)
					else:
						nest_view._start_eclose(1.0)
				"care":
					nest_view._update_brood()
					nest_view._start_care(String(_opts.get("care", "eggs")))     # the queen tending her brood
		if _opts.has("target"):
			var tp: PackedStringArray = String(_opts["target"]).split(",")
			nest_view.target = Vector3(float(tp[0]), float(tp[1]), float(tp[2]))
			nest_view.snap_camera()
	if _opts.has("colonies"):
		hud.open_colonies()
	if _opts.has("fridge"):
		sim.fridge_on = true
		sim.climate.fridge = 1.0
	if _opts.has("queen-act"):
		nest_view._queen_mode = int(_opts["queen-act"])     # hold the queen in one idle activity (pose checks)
		nest_view._queen_mode_left = 1.0e9
	if _opts.has("newcolony"):
		hud._open_new_colony(1, true)
	var keep := speed
	if not _opts.has("live"):
		speed = 0        # hold the clock still; _process keeps rendering
	var frame_ms := []
	var last := Time.get_ticks_usec()
	var vrid := get_viewport().get_viewport_rid()
	var gpu_ms := 0.0
	var cpu_render_ms := 0.0
	if _opts.has("perf"):
		RenderingServer.viewport_set_measure_render_time(vrid, true)
	for i in int(_opts.get("frames", "40")):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now
		if i == 10:
			fprof.clear()                 # (the first frames load and warm up)
			nest_view.fprof.clear()
		if i == 60 and _opts.has("floor-check") and mode == "nest":
			var diffs := []
			for s in nest_view._spots.all.slice(0, 30):
				diffs.append(snappedf(s.y - nest_view._floor_y(s), 0.01))
			print("spot.y - floor: ", diffs)
		if i == 60 and _opts.has("hover"):
			_hover_some_ant(String(_opts["hover"]))
		elif i > 10 and _opts.has("perf"):
			gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vrid)
			cpu_render_ms += RenderingServer.viewport_get_measured_render_time_cpu(vrid)
		if _opts.has("live") and i % 120 == 0 and mode == "nest":
			print(nest_view.debug_summary())
	speed = keep
	if _opts.has("perf") and frame_ms.size() > 20:
		# frame times: the average and the worst ones (stutter is what the eye notices)
		var s := frame_ms.slice(10)
		s.sort()
		var avg := 0.0
		for v in s:
			avg += v
		avg /= s.size()
		print("perf: avg %.1f ms (%.0f fps)  p95 %.1f ms  worst %.1f ms  frames over 33 ms: %d" % [avg, 1000.0 / avg,
			s[int(s.size() * 0.95)], s[-1], s.filter(func(v): return v > 33.3).size()])
		# where a frame's time goes (per frame, ms): the game's own work, then the renderer
		var nf := float(s.size())
		var parts := []
		for k in fprof:
			parts.append("%s %.1f" % [k, fprof[k] / 1000.0 / nf])
		var nparts := []
		for k in nest_view.fprof:
			nparts.append("%s %.1f" % [k, nest_view.fprof[k] / 1000.0 / nf])
		print("perf parts: %s | nest view: %s | render cpu %.1f gpu %.1f" % [", ".join(parts), ", ".join(nparts),
			cpu_render_ms / nf, gpu_ms / nf])
	var path: String = _opts["shot"]
	if _opts.has("seq"):
		# a strip of frames with the clock running (gait checks): <shot>_0.png, _1.png ...
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		speed = float(_opts.get("seq-speed", str(keep)))
		var who = _walker
		if who == null and _opts.has("at-ant") and String(_opts["at-ant"]).is_valid_int() and not sim.outside.is_empty():
			who = sim.outside[int(_opts["at-ant"]) % sim.outside.size()]
		for k in int(_opts["seq"]):
			for i in int(_opts.get("seq-every", "3")):
				await get_tree().process_frame
				if _opts.has("pops"):
					_count_pops()
				if _watch_food != null and mode == "outworld" and sim.foods.has(_watch_food):
					var fp2: Vector2 = _watch_food.pos
					outworld.target_t = Vector3(fp2.x, 0, fp2.y) * outworld.U
					outworld.target = outworld.target_t
				if _watch_creature != null and mode == "outworld" and sim.creatures.has(_watch_creature):
					var cp: Vector2 = _watch_creature.pos
					outworld.target_t = Vector3(cp.x, 0, cp.y) * outworld.U
					outworld.target = outworld.target_t
				if _opts.has("follow-anim") and mode == "nest":
					# watch a life-cycle moment (--follow-anim=eclose|pupate|egg|care) where it happens
					for an in nest_view._anims:
						if an.k == _opts["follow-anim"] and an.has("p"):
							nest_view.target_t = an.p
							nest_view.target = nest_view.target_t
							break
				if _opts.has("follow-crossing") and mode == "nest":
					# watch a nestmate up on the brood pile (crossing it), once one is
					for m in nest_view._mates:
						if float(m.get("blift", 0.0)) > 0.05 and m.has("xf"):
							nest_view.target_t = (m.xf as Transform3D).origin
							nest_view.target = nest_view.target_t
							break
				if _opts.has("follow-queen") and mode == "nest" and nest_view._queen_mm.instance_count > 0:
					# watch her mouthparts from a fixed angle to her heading (--follow-queen=<radians round from her right side>)
					nest_view.target_t = nest_view._queen_xf * Vector3(1.15, 0.2, 0.0)
					nest_view.target = nest_view.target_t
					nest_view.yaw = nest_view._queen_turn + float(_opts["follow-queen"])
					nest_view.yaw_t = nest_view.yaw
				if who != null and mode == "outworld" and who.vpos.x != INF:
					outworld.target_t = Vector3(who.vpos.x, 0, who.vpos.y) * outworld.U     # follow the ant
					outworld.target = outworld.target_t
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(path.get_basename() + "_%d.png" % k)
			if _opts.has("trace") and mode == "nest":
				for an in nest_view._anims:
					print("  anim %s u %.2f p %s vis %s cocoons-fx %d" % [an.k, an.t / an.d, an.get("p"), nest_view._visible(an.get("p", Vector3.ZERO)), nest_view._fx_cocoon_mm.instance_count])
					for hm in an.get("helpers", []):
						if hm.has("xf"):
							var hx: Transform3D = hm.xf
							print("    helper at %s (from cocoon %.2f) facing %s act %d" % [hx.origin, hx.origin.distance_to(an.p), hx.basis.x.normalized(), hm.act])
			if _opts.has("trace-mates") and mode == "nest":
				print("%d: %s" % [k, nest_view.trace_mates()])
			if _opts.has("trace") and mode == "nest":
				print("%d: brood-overlaps %d mate-overlaps %d who %s | %s" % [k, nest_view.brood_overlaps(), nest_view.mate_overlaps(), nest_view._overlap_who, nest_view.trace_near_queen()])     # who is by the queen, doing what
		get_tree().quit()
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	get_viewport().get_texture().get_image().save_png(path)
	_save_now()
	print("saved ", path, "  fps ", Engine.get_frames_per_second(), "  process ms %.2f" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0))
	get_tree().quit()


var _pop_prev := []
var _pop_moves := []
var _pop_n := 0
var _brood_prev := []
var _brood_moved := 0
var _brood_said := 0
var _buried_said := 0
## Dev (--pops, with --seq): drawn ants that flick back and forth (moved more than 0.2 mm one frame, then
## back again the next: two bodies pushing each other, or a pose that cannot settle); prints each one.
func _count_pops() -> void:
	var mm: MultiMesh = nest_view._ant_mm if mode == "nest" else outworld._ant_mm
	var u := 1.0 / 1.5                                            # world units per mm (both views)
	var now := []
	var moves := []
	for i in mm.instance_count:
		var p: Vector3 = mm.get_instance_transform(i).origin
		now.append(p)
		var best := INF
		var bj := -1
		for j in _pop_prev.size():
			var d: float = p.distance_squared_to(_pop_prev[j])
			if d < best:
				best = d
				bj = j
		var mv := Vector3.ZERO if bj < 0 else p - (_pop_prev[bj] as Vector3)
		moves.append(mv)
		if bj >= 0 and mv.length() < 3.0 * u and mv.length() > 0.2 * u:
			var was: Vector3 = _pop_moves[bj]
			if was.length() > 0.2 * u and mv.dot(was) < -0.5 * mv.length() * was.length():
				_pop_n += 1
				print("pop %d: flick at %s  %.2f mm then %.2f mm back" % [_pop_n, p, was.length() / u, mv.length() / u])
	_pop_prev = now
	_pop_moves = moves
	if mode == "nest":
		# brood should lie still: count eggs, larvae and cocoons that moved by themselves
		var bs := []
		var counts := []
		for bm in [nest_view._egg_mm, nest_view._larva_mm, nest_view._pupa_mm]:
			counts.append(bm.instance_count)
			for i in bm.instance_count:
				bs.append(bm.get_instance_transform(i).origin)
		if not _brood_prev.is_empty():
			for p in bs:
				var best := INF
				for q in _brood_prev:
					best = minf(best, (p as Vector3).distance_squared_to(q))
				if best > 0.01 and best < 9.0:
					_brood_moved += 1
					if _opts.has("trace"):
						print("  brood item moved %.2f  eggs/larvae/cocoons %s  sim %d/%d/%d" % [sqrt(best), counts, sim.eggs.size(), sim.larvae.size(), sim.pupae.size()])
			if _brood_moved > 0 and _brood_moved != _brood_said:
				_brood_said = _brood_moved
				print("brood moved (running count) %d" % _brood_moved)
		_brood_prev = bs
		# and none of it inside the soil: larva and cocoon ends, eggs' middles
		var buried := 0
		for bm in [nest_view._larva_mm, nest_view._pupa_mm]:
			for i in bm.instance_count:
				var xf: Transform3D = bm.get_instance_transform(i)
				var up := Vector3(0, 0.25 * xf.basis.get_scale().x, 0)
				for e in [xf.origin + up, xf.origin + up + xf.basis.x * 0.7, xf.origin + up - xf.basis.x * 0.7]:
					if nest_view._density_at(e) >= 0.5:
						buried += 1
						if _opts.has("trace"):
							print("  buried %s at %s (y above floor %.2f)" % ["larva" if bm == nest_view._larva_mm else "cocoon", xf.origin, xf.origin.y - nest_view._floor_cached(xf.origin)])
						break
		for i in nest_view._egg_mm.instance_count:
			if nest_view._density_at(nest_view._egg_mm.get_instance_transform(i).origin) >= 0.5:
				buried += 1
		if buried != _buried_said:
			_buried_said = buried
			print("brood in the soil now: %d" % buried)


## --hover=<role|out|queen>: put the mouse on such an ant, so the hover box shows in the shot.
func _hover_some_ant(what: String) -> void:
	var p := Vector3.INF
	if mode == "nest":
		if what == "queen":
			p = nest_view._queen_xf.origin
		else:
			for m in nest_view._mates:
				if m.has("xf") and m.role == what and nest_view._visible((m.xf as Transform3D).origin):
					p = (m.xf as Transform3D).origin
					break
		if p != Vector3.INF:
			hud.ant_tip.test_mouse = nest_view._cam.unproject_position(p)
	elif mode == "outworld":
		for a in sim.outside:
			if a.vpos.x != INF and a.state != sim.Ant.IN_NEST:
				var q: Vector2 = a.vpos * outworld.U
				p = Vector3(q.x, outworld.ground_top(q.x, q.y), q.y)
				if not outworld._cam.is_position_behind(p):
					hud.ant_tip.test_mouse = outworld._cam.unproject_position(p)
					break


## A diligent keeper for tests: water when the reservoir runs low, feed in proportion to colony size.
func _keeper(d: int) -> void:
	if sim.humidity < 0.45:
		sim.add_water()
	if d % 3 == 0:
		for k in 1 + sim.workers.size() / 40:
			sim.place_food("cricket", Vector2(randf_range(600, 1100), randf_range(380, 700)))
	if sim.sugar < sim.sugar_cap() * 0.3:
		for k in 1 + sim.workers.size() / 50:
			sim.place_food("honey", Vector2(randf_range(600, 1100), randf_range(80, 300)))


func _save_nest_png(path: String) -> void:
	# side view: darker = more open space along the depth axis; chamber centres in red
	var nv = sim.nest
	var s := 4
	var img := Image.create(nv.nx * s, nv.ny * s, false, Image.FORMAT_RGB8)
	for y in nv.ny:
		for x in nv.nx:
			var open := 0
			for z in nv.nz:
				if nv.rho[(z * nv.ny + y) * nv.nx + x] < nv.AIR:
					open += 1
			var depth: float = float(nv.ny - y) / nv.ny
			var soil: Color = Color(0.55, 0.42, 0.3).lerp(Color(0.62, 0.45, 0.32), depth)
			var c: Color = soil.lerp(Color(0.05, 0.03, 0.02), clampf(open / 3.0, 0.0, 1.0))
			img.fill_rect(Rect2i(x * s, (nv.ny - 1 - y) * s, s, s), c)
	for ch in nv.chambers:
		img.fill_rect(Rect2i(int(ch.c.x) * s - 2, (nv.ny - 1 - int(ch.c.y)) * s - 2, 5, 5), Color.RED)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("saved ", path)


func _selftest(days: int, autokeep: bool) -> void:
	var t0 := Time.get_ticks_msec()
	var every := int(_opts.get("every", "5"))
	var csv: FileAccess = null
	if _opts.has("csv"):
		DirAccess.make_dir_recursive_absolute(String(_opts["csv"]).get_base_dir())
		csv = FileAccess.open(_opts["csv"], FileAccess.WRITE)
		csv.store_line("day,workers,out,nurses,eggs,larvae,pupae,sugar,protein,humidity,nest_c,air_c,dead,cannibalized,born,ms_per_day")
	var slowest := 0
	print("day  workers out nurses  eggs larvae pupae  sugar protein  hum  nestC  dead cannib  ms/day")
	for d in days:
		var td := Time.get_ticks_msec()
		for i in sim.TPD:
			sim.step()
		var ms := Time.get_ticks_msec() - td
		slowest = maxi(slowest, ms)
		if autokeep:
			_keeper(d)
		if csv:
			csv.store_line("%d,%d,%d,%d,%d,%d,%d,%.2f,%.2f,%.3f,%.2f,%.2f,%d,%d,%d,%d" % [sim.day(), sim.workers.size(),
				sim.out_count, sim.nurses, sim.eggs.size(), sim.larvae.size(), sim.pupae.size(), sim.sugar, sim.protein,
				sim.humidity, sim.climate.nest, sim.climate.air, sim.stats.dead, sim.stats.cannibalized, sim.stats.born, ms])
		if d % every == every - 1 or d == days - 1:
			print("%3d  %7d %3d %6d  %4d %6d %5d  %5.1f %7.1f  %3d  %5.1f  %4d %6d  %6d" % [sim.day(), sim.workers.size(),
				sim.out_count, sim.nurses, sim.eggs.size(), sim.larvae.size(), sim.pupae.size(), sim.sugar,
				sim.protein, int(sim.humidity * 100), sim.climate.nest, sim.stats.dead, sim.stats.cannibalized, ms])
	if csv:
		csv.close()
	var nv = sim.nest
	print("nest: open %.1f cm³ (%d voxels, target %d)  chambers %d  depth %.1f cm  bites dumped %d  diggers %d" % [
		nv.volume_cm3(), nv.air, sim.target_air(), nv.chambers.size(), nv.depth_cm(), nv.excavated, nv.diggers.size()])
	if _opts.has("nestpng"):
		_save_nest_png(_opts["nestpng"])
	var pr: Dictionary = sim.prof
	print("profile ms: colony %d  food-grid %d (%d rebuilds)  ants %d (%d steps, %.1f us/step)  spider+cleanup %d  nest %d" % [
		pr.colony / 1000, pr.grid / 1000, pr.grids, pr.ants / 1000, pr.steps, float(pr.ants) / maxf(1.0, pr.steps), pr.other / 1000, pr.get("nest", 0) / 1000])
	print("queen alive: ", sim.queen.alive, "  sim time: %.1fs  slowest day: %d ms (headroom at 60× speed: %.1f×)" % [
		(Time.get_ticks_msec() - t0) / 1000.0, slowest, 1000.0 / maxf(1.0, slowest)])
	for e in sim.log_entries.slice(0, int(_opts.get("logs", "12"))):
		print("  ", e.stamp, "  ", e.text)
	get_tree().quit()
