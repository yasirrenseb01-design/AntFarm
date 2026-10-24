extends "res://scripts/game/parts/main_camera.gd"
## Game, layer 3 of 4: developer tools — screenshots (--shot), headless self-tests (--selftest),
## the test keeper and the nest side-view PNG. Options are listed at the top of scripts/game/main.gd.


var _walker = null          # --at-ant=walker: the forager the camera follows
var _duty_seen = null       # --follow-duty: the meeting the camera is on
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
		outworld.crowd = not _opts.has("no-crowd")
		if _opts.has("at-food"):
			# drop one of that food beside the nest and look at it (models: --at-food=fly)
			var fp: Vector2 = sim.nest_pos + Vector2(70, 30)
			sim.place_food(String(_opts["at-food"]), fp)
			outworld.target_t = Vector3(fp.x, 0, fp.y) * outworld.U
		outworld.snap_camera()
	if _opts.has("heater"):
		sim.heater = true                 # (dev: the heat mat on - the brood is carried down toward it)
	if _opts.has("queen-to"):
		# (dev: the colony sends the queen to that chamber - she walks there through the tunnels)
		get_tree().create_timer(2.0).timeout.connect(func():
			sim.queen_at = clampi(int(_opts["queen-to"]), 0, sim.nest.chambers.size() - 1)
			sim._queen_stay = 0.0
			nest_view._refresh_spots())
	if _opts.get("view", "outworld") == "nest":
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
				"feed":
					# the two nearest nestmates meet and share a droplet (trophallaxis)
					for w in 90:
						await get_tree().process_frame
						if nest_view._mates.filter(func(m): return m.has("vp")).size() >= 2:
							break
					var ms: Array = nest_view._mates.filter(func(m): return m.has("vp") and not m.has("script") and not nest_view._on_brood(m))
					var pairs := []
					for i in ms.size():
						for j in range(i + 1, ms.size()):
							var d: float = (ms[i].vp as Vector3).distance_to(ms[j].vp)
							if d > 0.5 and d < 6.0:
								pairs.append([d, ms[i], ms[j]])
					pairs.sort_custom(func(x, y): return x[0] < y[0])
					var best := []
					for pr in pairs:
						var n0: int = nest_view._anims.size()
						pr[1].fed = true
						nest_view._start_feed(pr[1], pr[2])
						if nest_view._anims.size() > n0:
							best = [pr[1], pr[2]]
							break
					if _opts.has("trace"):
						print("FEED mates %d free %d pair %s anims %d" % [nest_view._mates.size(), ms.size(), not best.is_empty(), nest_view._anims.size()])
				"care":
					nest_view._update_brood()
					nest_view._start_care(String(_opts.get("care", "eggs")))     # the queen tending her brood
		if _opts.has("target"):
			var tp: PackedStringArray = String(_opts["target"]).split(",")
			nest_view.target = Vector3(float(tp[0]), float(tp[1]), float(tp[2]))
			nest_view.snap_camera()
	if _opts.has("colonies"):
		hud.open_colonies()
	if _opts.has("name-first") and not sim.workers.is_empty():
		sim.name_ant(sim.workers[0].id, String(_opts["name-first"]))     # (--name-first=<name>: the title tour follows it)
	if _opts.has("fridge"):
		sim.fridge_on = true
		sim.climate.fridge = 1.0
	if _opts.has("queen-act"):
		nest_view._queen_mode = int(_opts["queen-act"])     # hold the queen in one idle activity (pose checks)
		nest_view._queen_mode_left = 1.0e9
	if _opts.has("newcolony"):
		hud._open_new_colony(1, true)
	if _opts.has("widest"):
		# (--widest: what makes the side panel wider than PANEL_W - longer words in another language)
		await get_tree().process_frame
		var found := []
		var walk := func(n, f):
			for c in n.get_children():
				if c is Control and c.get_combined_minimum_size().x > hud.PANEL_W - 30.0:
					found.append("%s %s %.0f '%s'" % [c.get_class(), c.name, c.get_combined_minimum_size().x, String(c.get("text")).left(40) if c.get("text") != null else ""])
				f.call(c, f)
		walk.call(hud._side, walk)
		print("side panel min width %.0f (PANEL_W %.0f)" % [hud._side.get_combined_minimum_size().x, hud.PANEL_W])
		for s in found.slice(-12):
			print("  ", s)
	if _opts.has("stars"):
		hud.toggle_stars()                   # (--stars: the star ants panel open; --star-go=<worker id|-1 queen>: its "ไปดู")
	if _opts.has("star-go"):
		hud.go_to_ant(sim.outside[0].id if _opts["star-go"] == "out" and not sim.outside.is_empty() else int(_opts["star-go"]))     # (out: a forager)
	if _opts.has("species"):
		var sw: Window = hud.open_species(1, true)
		sw._show(int(_opts["species"]) if String(_opts["species"]).is_valid_int() else 0)      # (--species=<i>: which model)
	if _opts.has("settings"):
		hud.open_settings()
	if _opts.has("enemy-panel") or _opts.has("release"):
		hud.toggle_enemies()                 # (the enemy panel open; --release=<kind>: as if its button were pressed)
		if _opts.has("release"):
			hud._release_enemy(String(_opts["release"]))
			for i in int(_opts.get("fight", "0")):
				sim.step()
	if _opts.has("dev-speeds"):
		for b in hud._dev_speed_buttons:
			b.visible = true                 # (as F10 does)
	var keep := float(_opts.get("speed", str(speed)))     # (--speed=<x>: run --live at that speed)
	if not _opts.has("live"):
		speed = 0        # hold the clock still; _process keeps rendering
	else:
		speed = keep
		sim.ant_substep = 1 if keep <= 5 else (2 if keep <= 20 else 4)
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
		if i == int(_opts.get("frames", "40")) - 20 and _opts.has("select") and mode == "nest" and _opts["select"] in ["eggs", "larvae", "pupae"]:
			# click on an item of brood (--select=eggs|larvae|pupae): its rim is drawn, the box says what it is
			var drawn: Array = nest_view._brood_drawn[_opts["select"]]
			# (the first one not behind an ant: there the ant is what the click is on)
			for e in drawn:
				var bsp: Vector2 = nest_view._cam.unproject_position((e[0] as Transform3D).origin)
				if nest_view.pick_ant(bsp).get("kind", "") == _opts["select"]:
					hud.ant_tip._click(bsp)
					break
		elif i == 60 and _opts.has("select") and mode == "nest":
			# click on a nestmate (its gaster, not its middle: picking by the whole body) - its outline is drawn
			for m in nest_view._mates:
				if m.has("xf") and nest_view._shown(m.xf):
					hud.ant_tip._click(nest_view._cam.unproject_position((m.xf as Transform3D) * Vector3(-0.8, 0.4, 0)))
					break
		if i == 62 and _opts.has("name-ant") and not hud.ant_tip.sel.is_empty():
			# (--name-ant=<name>, with --select: type a name into the chosen ant's box, as the keeper does)
			hud.ant_tip._name_edit.text = String(_opts["name-ant"])
			hud.ant_tip._give_name()
		if i == 64 and _opts.has("named-death"):
			# (--named-death: the banner a named ant's death puts up, with the words the simulation would use)
			var TT = load("res://scripts/sim/text_th.gd")
			sim._log(TT.named_died, "named", ["Mimi", sim.L.k(TT.death_causes.starve), 42])
		if i == 60 and _opts.has("hover"):
			_hover_some_ant(String(_opts["hover"]))
		elif i > 10 and _opts.has("perf"):
			gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vrid)
			cpu_render_ms += RenderingServer.viewport_get_measured_render_time_cpu(vrid)
		if _opts.has("live") and i % 120 == 0 and mode == "nest":
			print(nest_view.debug_summary())
	speed = keep
	if _opts.has("pick-check") and mode == "nest":
		# click on each drawn nestmate's head, middle and gaster tip: is it the one picked?
		var ok := 0
		var tried := 0
		var hidden := 0
		for m in nest_view._mates:
			if not m.has("xf") or not nest_view._shown(m.xf):
				continue
			for q in [Vector3(0.9, 0.4, 0), Vector3(0, 0.3, 0), Vector3(-0.95, 0.4, 0)]:
				var sp: Vector2 = nest_view._cam.unproject_position((m.xf as Transform3D) * q)
				var got: Dictionary = nest_view.pick_ant(sp)
				var own: float = nest_view._cam.global_position.distance_to((m.xf as Transform3D).origin)
				var got_d := INF
				if got.get("kind", "") == "queen":
					got_d = nest_view._cam.global_position.distance_to(nest_view._queen_xf.origin)
				for o in nest_view._mates:
					if got.get("w") != null and o.get("wid", -2) == got.w.id and o.has("xf"):
						got_d = nest_view._cam.global_position.distance_to((o.xf as Transform3D).origin)
				if got.get("w") != null and got.w.id == m.wid:
					ok += 1
					tried += 1
				elif got_d < own - 0.3:
					hidden += 1                   # (behind another body there: that one is what the click is on)
				else:
					tried += 1
					print("   missed at %s: got %s; own gap %.1f" % [q, got.get("kind", "nothing"), nest_view._body_gap(m.xf, sp)])
		print("pick check: %d of %d clicks on a nestmate's head / middle / gaster picked that nestmate (%d behind another body)" % [ok, tried, hidden])
	if _opts.has("perf") and frame_ms.size() > 20:
		# frame times: the average and the worst ones (stutter is what the eye notices)
		var s := frame_ms.slice(10)
		s.sort()
		var avg := 0.0
		for v in s:
			avg += v
		avg /= s.size()
		var counts := {}
		var stack: Array = [get_tree().root]
		while not stack.is_empty():
			var nd: Node = stack.pop_back()
			stack.append_array(nd.get_children())
			if nd is GeometryInstance3D and nd.is_visible_in_tree():
				var key := nd.get_class()
				if nd is MultiMeshInstance3D and nd.multimesh != null:
					counts[key + " inst"] = counts.get(key + " inst", 0) + nd.multimesh.instance_count
				counts[key] = counts.get(key, 0) + 1
		print("visible geometry: ", counts)
		print("memory: %.0f MB (game)  video %.0f MB" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
		print("engine: process %.1f ms  draw calls %d  objects %d  primitives %d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
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
				if _opts.has("buried") and mode == "nest":
					BuriedCheck.measure(nest_view, _buried)
				if _opts.has("feet") and mode == "nest":
					if _opts.has("feet-debug"):
						_feet.debug = true
					FootCheck.measure(nest_view, _feet)
				if _opts.has("bodies") and mode == "nest":
					_bodies.worst = {}
					if _opts.has("trace-crowd"):
						_bodies.trace = true
					BodyCheck.measure(nest_view, _bodies)
				elif _opts.has("bodies") and mode == "outworld":
					_bodies.worst = {}
					if _opts.has("trace-crowd"):
						_bodies.trace = true
					BodyCheck.measure_out(outworld, sim, _bodies)
					# (--follow-bodies=ant|brood|feet: the camera on the worst case of that kind, held a while)
					var fw: Array = (_bodies.worst as Dictionary).get(_opts.get("follow-bodies", ""), [])
					if not fw.is_empty() and (_bodies_at == Vector3.INF or float(fw[0]) > _bodies_d * 1.5 or k % 4 == 0 and i == 0):
						_bodies_at = fw[1]
						_bodies_d = fw[0]
						nest_view.target_t = _bodies_at
						nest_view.target = _bodies_at
						print("  follow %s: %.2f %s at %s" % [_opts["follow-bodies"], fw[0], fw[2], fw[1]])
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
						if an.k == "feed" and _opts["follow-anim"] == "feed" and an.giver.has("xf") and an.taker.has("xf"):
							# between the two mouths, looking across the pair (side view of the exchange)
							var gm: Vector3 = (an.giver.xf as Transform3D) * nest_view.MOUTH
							var tm: Vector3 = (an.taker.xf as Transform3D) * nest_view.MOUTH
							nest_view.target_t = (gm + tm) * 0.5
							nest_view.target = nest_view.target_t
							var ax: Vector3 = gm - tm
							nest_view.yaw = atan2(-ax.z, ax.x) + float(_opts.get("side", "1.57"))
							nest_view.yaw_t = nest_view.yaw
							break
						if an.k == _opts["follow-anim"] and an.has("p"):
							nest_view.target_t = an.p
							nest_view.target = nest_view.target_t
							break
				if _opts.has("follow-fit") and mode == "nest":
					# watch a nestmate lying on a slope (body tipped and bent to the ground under it), the same one;
					# seen from its side (--side=<radians round from its right side>)
					# (--follow-fit=over: one climbing over a nestmate's back instead; =turn one rounding a bend; =walk one walking)
					var fm = _pushed if _pushed != null and nest_view._mates.has(_pushed) else null
					var climbs: bool = _opts["follow-fit"] == "over"
					if fm != null and climbs and not fm.has("over_on") and float(fm.get("over", 0.0)) <= 0.0 and float(_pushed_t) > 1.0:
						fm = null                 # (past the one it climbed over a second ago: another climber)
					if fm == null:
						_pushed_t = 0.0
						for m in nest_view._mates:
							var g: PackedFloat32Array = m.get("gfit", PackedFloat32Array())
							var pick: bool = absf(float(m.get("lat", 0.0))) > 0.2 if _opts["follow-fit"] == "turn" else \
								float(m.get("mv", 0.0)) > 0.8 if _opts["follow-fit"] == "walk" else \
								(m.has("over_on") and float(m.get("over", 0.0)) > 0.05) if climbs else \
								(g.size() == 5 and absf(g[1]) + absf(g[2]) + absf(g[3]) > float(_opts.get("fit-min", "0.35")))
							if pick and m.has("xf") and (climbs or nest_view._visible((m.xf as Transform3D).origin)):
								fm = m
								break
					if fm != null:
						_pushed = fm
						var fx: Transform3D = fm.xf
						nest_view.target_t = fx.origin
						nest_view.target = nest_view.target_t
						var fwd: Vector3 = fx.basis.x
						nest_view.yaw = atan2(-fwd.z, fwd.x) + float(_opts.get("side", "1.57"))
						nest_view.yaw_t = nest_view.yaw
						if fm.has("over_on") or float(fm.get("over", 0.0)) > 0.0:
							_pushed_t = 0.0
						else:
							_pushed_t = float(_pushed_t) + get_process_delta_time()
						if i == 0:
							print("  fitted ant: %s act %d over %.2f tip %.2f on %s lat %.2f" % [fm.get("gfit"), fm.act, float(fm.get("over", 0.0)),
								float(fm.get("over_tip", 0.0)), fm.has("over_on"), float(fm.get("lat", 0.0))])
				if _opts.has("follow-queen") and mode == "nest" and nest_view._queen_mm.instance_count > 0:
					nest_view.target_t = nest_view._queen_xf.origin        # (dev: watch her walk, --queen-to)
					nest_view.target = nest_view.target_t
				if _opts.has("follow-digger") and mode == "nest":
					# watch a digger (the same one), seen from its side (--side) or above
					var dv = _pushed if _pushed != null and nest_view._dig_vis.values().has(_pushed) else null
					if dv == null:
						for v in nest_view._dig_vis.values():
							if v.has("xf") and (float(v.get("still", 0.0)) > 0.3 if _opts.get("follow-digger") == "face" else float(v.get("still", 0.0)) < 0.1):
								dv = v
								break
					if dv != null:
						_pushed = dv
						var dx: Transform3D = dv.xf
						nest_view.target_t = dx.origin
						nest_view.target = nest_view.target_t
						if _opts.has("side"):
							nest_view.yaw = atan2(-dx.basis.x.z, dx.basis.x.x) + float(_opts["side"])
							nest_view.yaw_t = nest_view.yaw
						var dcl: Vector2 = nest_view._soil_clearance(dx, float(dv.size), dv.get("bend", Vector2.ZERO), float(dv.get("still", 0.0)) > 0.25)
						print("  digger: still %.2f clr %.2f soil %s narrow %s trail %d lat %.2f" % [float(dv.get("still", 0.0)), float(dv.get("clr", 0.0)), dcl, nest_view._cell_narrow(dv.cell), (dv.get("trail", PackedVector3Array()) as PackedVector3Array).size(), float(dv.get("lat", 0.0))])
				if _opts.has("follow-soil") and mode == "nest":
					# watch a nestmate with part of its body in the soil (the --trace-crowd check), the same one while it lasts
					var sm = _pushed if _pushed != null and nest_view._mates.has(_pushed) and nest_view._ant_in_soil(_pushed) else null
					if sm == null:
						for m in nest_view._mates:
							if nest_view._ant_in_soil(m) and nest_view._visible((m.xf as Transform3D).origin):
								sm = m
								break
					if sm != null:
						_pushed = sm
						nest_view.target_t = (sm.xf as Transform3D).origin
						nest_view.target = nest_view.target_t
				if _opts.has("follow-wall") and mode == "nest":
					# watch a walking nestmate being shifted out of a tunnel wall (nest_contact._soil_push), the same one
					var wm = _pushed if _pushed != null and nest_view._mates.has(_pushed) else null
					if wm == null:
						for m in nest_view._mates:
							if m.has("xf") and (m.get("soil_off", Vector3.ZERO) as Vector3).length() > 0.15 and float(m.get("mv", 0.0)) > 0.3:
								wm = m
								break
					if wm != null:
						_pushed = wm
						nest_view.target_t = (wm.xf as Transform3D).origin
						nest_view.target = nest_view.target_t
						if i == 0:
							print("  wall: shift %.2f turn %.2f in-soil %s" % [(wm.get("soil_off", Vector3.ZERO) as Vector3).length(), float(wm.get("soil_yaw", 0.0)), nest_view._ant_in_soil(wm)])
				if _opts.has("follow-pushed") and mode == "nest":
					# watch a nestmate being pushed aside (stepping aside on its legs), the same one while it lasts
					var pm = _pushed if _pushed != null and nest_view._mates.has(_pushed) else null
					if pm == null or float(pm.get("sgr", 0.0)) == 0.0 and (pm.get("sepv", Vector3.ZERO) as Vector3).length() < 0.02:
						pm = null
						for m in nest_view._mates:
							if float(m.get("sgr", 0.0)) > 0.0 and (m.get("sepv", Vector3.ZERO) as Vector3).length() > 0.1 and m.has("xf") and m.get("rest", 0) > 0 and nest_view._visible((m.xf as Transform3D).origin):
								pm = m
								break
					if i == 0:
						print("  stepping aside: %d (resting %d)" % [nest_view._mates.filter(func(q): return float(q.get("sgr", 0.0)) > 0.0).size(), nest_view._mates.filter(func(q): return float(q.get("sgr", 0.0)) > 0.0 and q.rest > 0).size()])
					if pm != null:
						_pushed = pm
						nest_view.target_t = (pm.xf as Transform3D).origin
						nest_view.target = nest_view.target_t
						if i == 0 or pm != _pushed_said:
							_pushed_said = pm
							print("  pushed ant: sepv %.2f mv %.2f gait %.2f rest %d" % [(pm.sepv as Vector3).length(), pm.get("mv", 0.0), pm.get("gait", 0.0), pm.rest])
				if _opts.has("stage-groom") and mode == "nest" and k == 1 and i == 0:
					# (--stage-groom: two nestmates on open floor, one set to lick the other clean - the pose seen from all round)
					var best = null
					var bd := INF
					for m in nest_view._mates:
						if m.role != "idle" or m.has("script") or not m.has("vp") or (m.vu as Vector3).y < 0.9:
							continue
						var crowd := 0
						for o in nest_view._mates:
							if o.has("vp") and (o.vp as Vector3).distance_to(m.vp) < 4.0:
								crowd += 1
						if crowd < bd:
							bd = crowd
							best = m
					var other = null
					if best != null:
						var od := INF
						for o in nest_view._mates:
							if o != best and o.has("vp") and not o.has("script") and (o.vu as Vector3).y > 0.85 and (o.vp as Vector3).distance_to(best.vp) < od:
								od = (o.vp as Vector3).distance_to(best.vp)
								other = o
					if other != null:
						# the groomer brought beside it (as if it had walked up), then the licking starts
						other.vp = (best.vp as Vector3) + Vector3(2.0, 0, 0.6)
						print("  staged groom: ", nest_view._start_groom(other, best), " crowd ", bd)
				if _opts.has("follow-duty") and mode == "nest":
					# (--follow-duty=groom|feed: the camera on a nestmate licking another clean / giving a drop, once one starts)
					var want: String = String(_opts["follow-duty"])
					var on = null
					for an in nest_view._anims:
						if an.k == want and nest_view._mates.has(an.giver) and an.giver.has("xf"):
							on = an
					if on != null:
						if on != _duty_seen:
							_duty_seen = on
							print("  %s starts at frame %d" % [want, k])
						nest_view.target_t = ((on.giver.xf as Transform3D).origin + (on.taker.xf as Transform3D).origin) * 0.5 if on.taker.has("xf") else (on.giver.xf as Transform3D).origin
						nest_view.dist_t = float(_opts.get("dist", "9"))
				if _opts.has("follow-crossing") and mode == "nest":
					# watch a nestmate up on the brood pile (crossing it), once one is
					for m in nest_view._mates:
						if float(m.get("over", 0.0)) > 0.05 and not m.has("over_on") and m.has("xf"):
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
			if _opts.has("duty-log") and mode == "nest":
				print(nest_view.debug_summary().left(220))       # (--duty-log: the nest acting out its duties, frame by frame)
				print(nest_view.duty_trace())
			if _opts.has("trace") and mode == "nest":
				for an in nest_view._anims:
					print("  anim %s u %.2f p %s vis %s cocoons-fx %d" % [an.k, an.t / an.d, an.get("p"), nest_view._visible(an.get("p", Vector3.ZERO)), nest_view._fx_cocoon_mm.instance_count])
					if an.k == "feed" and an.giver.has("xf") and an.taker.has("xf"):
						var gx: Transform3D = an.giver.xf
						var tx: Transform3D = an.taker.xf
						var gmo: Vector3 = gx * nest_view.MOUTH
						var tmo: Vector3 = tx * nest_view.MOUTH
						print("    mouths %.2f apart; giver faces taker %.2f, taker faces giver %.2f; heads %.2f apart" % [gmo.distance_to(tmo),
							gx.basis.x.normalized().dot((tx.origin - gx.origin).normalized()), tx.basis.x.normalized().dot((gx.origin - tx.origin).normalized()),
							(gx * Vector3(0.9, 0.4, 0)).distance_to(tx * Vector3(0.9, 0.4, 0))])
					if an.k == "feed":
						for side_k in ["giver", "taker"]:
							var q: Dictionary = an[side_k]
							if q.has("vf") and q.get("face") is Vector3 and q.face != Vector3.INF:
								var want3: Vector3 = (q.face as Vector3) - (q.vp as Vector3)
								want3.y = 0.0
								print("    %s vf %s want %s mv %.2f face %s" % [side_k, q.vf, want3.normalized(), q.get("mv", 0.0), q.face])
							var mm: Dictionary = an[side_k]
							print("    %s xf %s pos %s goal %s act %d in-mates %s" % [side_k, (mm.xf as Transform3D).origin if mm.has("xf") else null, mm.script.pos if mm.has("script") else null, mm.script.goal if mm.has("script") else null, mm.act, nest_view._mates.has(mm)])
					for hm in an.get("helpers", []):
						if hm.has("xf"):
							var hx: Transform3D = hm.xf
							var soil_pts := 0
							var which := ""
							for q in [Vector3(0.9, 0.45, 0), Vector3(0, 0.45, 0), Vector3(-1.2, 0.45, 0), Vector3(0, -0.1, 0)]:
								if nest_view._density_at(hx * q) >= 0.5:
									soil_pts += 1
									which += "%s " % q
							print("    helper at %s (from cocoon %.2f) act %d body-in-soil %d/3 %s floor-gap %.2f" % [hx.origin, hx.origin.distance_to(an.p), hm.act, soil_pts, which, hx.origin.y - nest_view._floor_cached(hx.origin)])
			if _opts.has("trace-crowd") and mode == "nest":
				print("%d: %s" % [k, nest_view.trace_crowd()])
			if _opts.has("trace-mates") and mode == "nest":
				print("%d: %s" % [k, nest_view.trace_mates()])
			if _opts.has("trace") and mode == "nest":
				print("%d: brood-overlaps %d mate-overlaps %d who %s | %s" % [k, nest_view.brood_overlaps(), nest_view.mate_overlaps(), nest_view._overlap_who, nest_view.trace_near_queen()])     # who is by the queen, doing what
		if _opts.has("orbit") and mode == "nest":
			# the last moment seen from all round, the clock held: <shot>_o0.png ... (--orbit=<n> [--orbit-pitch=<rad>])
			speed = 0
			var y0: float = nest_view.yaw
			for j in int(_opts["orbit"]):
				nest_view.yaw = y0 + TAU * j / float(_opts["orbit"])
				nest_view.yaw_t = nest_view.yaw
				if _opts.has("orbit-pitch"):
					nest_view.pitch = float(_opts["orbit-pitch"])
					nest_view.pitch_t = nest_view.pitch
				for f in 3:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(path.get_basename() + "_o%d.png" % j)
		if _opts.has("bodies"):
			print(BodyCheck.report(_bodies))
		if _opts.has("feet"):
			print(FootCheck.report(_feet))
		if _opts.has("buried"):
			print(BuriedCheck.report(_buried))
		if _opts.has("pops") and mode == "nest" and _jit_frames > 0:
			var secs := _jit_frames / 60.0
			print("jitter: %d turn flicks, %d bobs in %.0f ant-seconds (%.2f / %.2f per ant-minute)" % [_jit_turns, _jit_bobs, secs,
				_jit_turns / secs * 60.0, _jit_bobs / secs * 60.0])
			print("motion: skating sideways %.1f%%, gliding with legs still %.1f%% of ant-frames (speed %s)" % [100.0 * _jit_skate / _jit_frames,
				100.0 * _jit_glide / _jit_frames, speed])
		get_tree().quit()
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	get_viewport().get_texture().get_image().save_png(path)
	if hud.ant_tip.visible:
		print("selected: ", hud.ant_tip._text.text.replace(char(10), " | "))
	_save_now()
	print("saved ", path, "  fps ", Engine.get_frames_per_second(), "  process ms %.2f" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0))
	get_tree().quit()


const BodyCheck := preload("res://scripts/dev/body_check.gd")
const FootCheck := preload("res://scripts/dev/foot_check.gd")
const BuriedCheck := preload("res://scripts/dev/buried_check.gd")
var _buried := {}                 # (--buried: nestmates drawn whole inside the soil, see buried_check.gd)
var _feet := {}                   # (--feet: where the planted feet are, see foot_check.gd)
var _bodies := {}                 # (--bodies: bodies inside one another, see body_check.gd)
var _bodies_at := Vector3.INF
var _bodies_d := 0.0
var _pushed = null                # (--follow-pushed: the ant being watched)
var _pushed_said = null
var _pushed_t := 0.0             # (--follow-fit=over: how long since the one watched was last climbing)
var _pop_prev := []
var _pop_by := {}
var _jid_next := 0
var _jit_by := {}
var _jit_last := {}
var _skate_prev := {}
var _jit_skate := 0
var _jit_glide := 0
var _jit_parts := {}
var _jit_turns := 0
var _jit_bobs := 0
var _jit_frames := 0                 # ant-frames looked at
var _pop_moves := []
var _pop_n := 0
var _brood_prev := []
var _brood_moved := 0
var _brood_said := 0
var _buried_said := 0
var _float_said := 0
## Dev (--pops, with --seq): drawn ants that flick back and forth (moved more than 0.2 mm one frame, then
## back again the next: two bodies pushing each other, or a pose that cannot settle); prints each one.
func _count_pops() -> void:
	var mm: MultiMesh = nest_view._ant_mm if mode == "nest" else outworld._ant_mm
	var u := 1.0 / 1.5                                            # world units per mm (both views)
	if mode == "nest":
		# each nestmate followed by who it is (matching drawn ants by nearness swapped two that passed close)
		var pmin2 := float(_opts.get("pops-min", "0.2")) * u
		for m in nest_view._mates:
			if not m.has("xf") or not nest_view._shown(m.xf):
				if m.has("jid"):
					_jit_by.erase(m.jid)          # (not on screen: off screen ants are moved on only every 4th frame)
					_jit_last.erase(m.jid)
					_pop_by.erase(m.jid)
				continue
			var p2: Vector3 = (m.xf as Transform3D).origin
			# (keyed by the drawn body, not the worker: at high speed workers go out and come in many times a second,
			# and a drawn body is handed to another worker - that is no jump on screen)
			if not m.has("jid"):
				_jid_next += 1
				m.jid = _jid_next
			var id: int = m.jid
			if _pop_by.has(id):
				var mv2: Vector3 = p2 - (_pop_by[id][0] as Vector3)
				var was2: Vector3 = _pop_by[id][1]
				if mv2.length() < 3.0 * u and mv2.length() > pmin2 and was2.length() > pmin2 and mv2.dot(was2) < -0.5 * mv2.length() * was2.length():
					_pop_n += 1
					print("pop %d: flick at %s  %.2f mm then %.2f mm back  (%s act %d over %.2f sep %.2f)" % [_pop_n, p2, was2.length() / u, mv2.length() / u,
						m.role, m.act, float(m.get("over", 0.0)), (m.get("sep", Vector3.ZERO) as Vector3).length()])
				_pop_by[id] = [p2, mv2]
			else:
				_pop_by[id] = [p2, Vector3.ZERO]
			# turning one way then straight back (the body flicking round), and bobbing up then straight down
			var x2: Transform3D = m.xf
			var upv: Vector3 = x2.basis.y.normalized()
			var fw: Vector3 = x2.basis.x.normalized()
			var dt2 := maxf(get_process_delta_time(), 0.001)
			if _jit_by.has(id):
				var j: Array = _jit_by[id]
				var turn: float = atan2((j[0] as Vector3).cross(fw).dot(upv), (j[0] as Vector3).dot(fw)) / dt2
				var rise: float = (p2 - (j[1] as Vector3)).dot(upv) / dt2
				if absf(turn) > 3.0 and absf(float(j[2])) > 3.0 and signf(turn) != signf(float(j[2])):
					_jit_turns += 1
					if _opts.has("jitter-why"):
						print("   turn flick %.1f then %.1f rad/s: trail %d lat %.2f vel %.2f gfit-still %s | %s act %d rest %d mv %.2f sep %.2f sgr %.2f settle %d rest_dir %s face %s" % [float(j[2]), turn,
							(m.get("trail", PackedVector3Array()) as PackedVector3Array).size(), float(m.get("lat", 0.0)), (m.get("vel", Vector3.ZERO) as Vector3).length(), m.get("gfit_still", false), m.role, m.act, m.rest, float(m.get("mv", 0.0)),
							(m.get("sep", Vector3.ZERO) as Vector3).length(), float(m.get("sgr", 0.0)), (m.get("settle", []) as Array).size(), m.get("rest_dir", Vector3.ZERO) != Vector3.ZERO, m.get("face", Vector3.INF) != Vector3.INF])
				if absf(rise) > 1.5 and absf(float(j[3])) > 1.5 and signf(rise) != signf(float(j[3])):
					_jit_bobs += 1
					if _opts.has("jitter-why"):
						var gf: PackedFloat32Array = m.get("gfit", PackedFloat32Array([0, 0, 0, 0, 0]))
						var gp: Array = _jit_parts.get(id, [0.0, 0.0, 0.0, 0.0, Vector3.ZERO, Vector3.ZERO])
						var sepv: Vector3 = m.get("sep", Vector3.ZERO)
						var vpv: Vector3 = m.get("vp", Vector3.ZERO)
						print("   bob %.2f u/s: %s act %d rest %d | changes this frame: lift %+.3f clr %+.3f blift %+.3f over %+.3f sep-up %+.3f path-up %+.3f" % [rise, m.role, m.act, m.rest,
							gf[0] - float(gp[0]), float(m.get("clr", 0.0)) - float(gp[1]), float(m.get("blift", 0.0)) - float(gp[2]), float(m.get("over", 0.0)) - float(gp[3]),
							(sepv - (gp[4] as Vector3)).dot(upv), (vpv - (gp[5] as Vector3)).dot(upv)])
				var vfn: Vector3 = m.get("vf", fw)
				var vturn: float = atan2((j[4] as Vector3).cross(vfn).dot(upv), (j[4] as Vector3).dot(vfn)) / dt2 if j.size() > 4 else 0.0
				if _opts.has("jitter-why") and absf(turn) > 3.0 and absf(float(j[2])) > 3.0 and signf(turn) != signf(float(j[2])):
					print("      heading itself turned %.1f rad/s; up %s vu %s fit %s" % [vturn, (upv * 10).round() / 10, ((m.get("vu", upv) as Vector3) * 10).round() / 10, m.get("gfit")])
				_jit_by[id] = [fw, p2, turn, rise, vfn]
				var gf2: PackedFloat32Array = m.get("gfit", PackedFloat32Array([0, 0, 0, 0, 0]))
				_jit_parts[id] = [gf2[0], float(m.get("clr", 0.0)), float(m.get("blift", 0.0)), float(m.get("over", 0.0)), m.get("sep", Vector3.ZERO), m.get("vp", Vector3.ZERO), m.get("vu", upv)]
			else:
				_jit_by[id] = [fw, p2, 0.0, 0.0, m.get("vf", fw)]
			_jit_frames += 1
			# moving in a way its legs do not show: sideways (skating: its heading far off the way it moves) or with
			# its legs still (gliding); and its legs stepping while it stands (treading the air)
			if _jit_last.has(id):
				var mvd: Vector3 = p2 - (_jit_last[id] as Vector3)
				mvd -= upv * mvd.dot(upv)
				var spd := mvd.length() / dt2
				var stepping := float(m.get("mv", 0.0))
				if spd > 1.0 and absf(fw.angle_to(mvd)) > 0.9 and not m.has("script") and (m.get("face", Vector3.INF) as Vector3) == Vector3.INF:
					_jit_skate += 1
					if _opts.has("jitter-why"):
						print("   skate %.1f u/s %.0f deg: %s act %d rest %d mv %.2f sep %.2f sepv %.2f settle %d over %.2f vel %.2f wv %.2f" % [spd, rad_to_deg(fw.angle_to(mvd)), m.role, m.act, m.rest,
							stepping, (m.get("sep", Vector3.ZERO) as Vector3).length(), (m.get("sepv", Vector3.ZERO) as Vector3).length(), (m.get("settle", []) as Array).size(),
							float(m.get("over", 0.0)), (m.get("vel", Vector3.ZERO) as Vector3).length(), float(m.get("wv", 0.0))])
						var pp: Array = _skate_prev.get(id, [])
						if pp.size() >= 6:
							var gfn: PackedFloat32Array = m.get("gfit", PackedFloat32Array([0, 0, 0, 0, 0]))
							print("      this frame: path moved %.2f, sep %.2f, ground lift %+.2f, soil lift %+.2f, up turned %.1f deg, fit cell %s" % [
								((m.get("vp", Vector3.ZERO) as Vector3) - (pp[5] as Vector3)).length(), ((m.get("sep", Vector3.ZERO) as Vector3) - (pp[4] as Vector3)).length(),
								gfn[0] - float(pp[0]), float(m.get("clr", 0.0)) - float(pp[1]), rad_to_deg((m.get("vu", upv) as Vector3).angle_to(pp[6] if pp.size() > 6 else upv)), m.get("gfit_c")])
				if spd > 0.6 and stepping < 0.3 and not m.has("script"):
					_jit_glide += 1
			_jit_last[id] = p2
			var gf3: PackedFloat32Array = m.get("gfit", PackedFloat32Array([0, 0, 0, 0, 0]))
			_skate_prev[id] = [gf3[0], float(m.get("clr", 0.0)), 0.0, 0.0, m.get("sep", Vector3.ZERO), m.get("vp", Vector3.ZERO), m.get("vu", upv)]
		mm = MultiMesh.new()                 # (the drawn-ant matching below: skipped in the nest)
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
		var pmin := float(_opts.get("pops-min", "0.2"))
		if bj >= 0 and mv.length() < 3.0 * u and mv.length() > pmin * u:
			var was: Vector3 = _pop_moves[bj]
			if was.length() > pmin * u and mv.dot(was) < -0.5 * mv.length() * was.length():
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
		# eggs floating: the bottom of an egg more than 0.15 above the floor with no egg under it
		var floating := 0
		var eo := []
		for i in nest_view._egg_mm.instance_count:
			eo.append(nest_view._egg_mm.get_instance_transform(i).origin)
		for e in eo:
			var gap: float = (e as Vector3).y - 0.2 - nest_view._floor_cached(e)
			if gap > 0.15:
				var held := false
				for o in eo:
					if (o as Vector3).y < (e as Vector3).y - 0.1 and Vector2(o.x - e.x, o.z - e.z).length() < 0.45:
						held = true
						break
				if not held:
					floating += 1
					if _opts.has("trace"):
						print("  floating egg at %s gap %.2f" % [e, gap])
		if floating != _float_said:
			_float_said = floating
			print("eggs floating now: %d of %d" % [floating, eo.size()])
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
			sim.place_food("cricket", sim.food_spot(300.0, 560.0))
	if sim.sugar < sim.sugar_cap() * 0.3:
		for k in 1 + sim.workers.size() / 50:
			sim.place_food("honey", sim.food_spot(300.0, 560.0))


func _save_nest_png(path: String) -> void:
	# side view: darker = more open space along the depth axis; chamber centres in red
	var nv = sim.nest
	var s := 4
	var img := Image.create(nv.nx * s, nv.ny * s, false, Image.FORMAT_RGB8)
	for y in nv.ny:
		for x in nv.nx:
			var open := 0
			for z in nv.nz:
				if nv.is_open(Vector3i(x, y, z)):
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
		print("  ", sim.L.stamp(e), "  ", sim.L.entry_text(e))
	get_tree().quit()
