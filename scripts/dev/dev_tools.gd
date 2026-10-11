extends "res://scripts/game/parts/main_camera.gd"
## Game, layer 3 of 4: developer tools — screenshots (--shot), headless self-tests (--selftest),
## the test keeper and the nest side-view PNG. Options are listed at the top of scripts/game/main.gd.


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
	if _opts.has("enemy"):
		# stage a fight: an enemy beside the nest, then let it run for --fight=<ticks>
		sim.enemies = false
		sim._spawn_creature(_opts["enemy"])
		var ep: PackedStringArray = String(_opts.get("enemy-at", "%d,%d" % [sim.nest_pos.x + 120, sim.nest_pos.y + 40])).split(",")
		sim.creatures[-1].pos = Vector2(float(ep[0]), float(ep[1]))
		sim.creatures[-1].ang = float(_opts.get("enemy-ang", "3.1"))
		for i in int(_opts.get("fight", "0")):
			sim.step()
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
		elif _opts.has("at-ant") and not sim.outside.is_empty():
			var a = sim.outside[int(_opts["at-ant"]) % sim.outside.size()]
			outworld.target_t = Vector3(a.pos.x, 0, a.pos.y) * outworld.U
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
		# act out life-cycle moments on demand: --anim=egg,pupate,eclose
		for k in String(_opts.get("anim", "")).split(",", false):
			nest_view._refresh_spots()
			match k:
				"egg": nest_view._start_egg()
				"pupate": nest_view._start_pupate(1.0)
				"eclose": nest_view._start_eclose(1.0)
		if _opts.has("target"):
			var tp: PackedStringArray = String(_opts["target"]).split(",")
			nest_view.target = Vector3(float(tp[0]), float(tp[1]), float(tp[2]))
			nest_view.snap_camera()
	if _opts.has("colonies"):
		hud.open_colonies()
	if _opts.has("newcolony"):
		hud._open_new_colony(1, true)
	var keep := speed
	if not _opts.has("live"):
		speed = 0        # hold the clock still; _process keeps rendering
	for i in int(_opts.get("frames", "40")):
		await get_tree().process_frame
		if _opts.has("live") and i % 120 == 0 and mode == "nest":
			print(nest_view.debug_summary())
	speed = keep
	await RenderingServer.frame_post_draw
	var path: String = _opts["shot"]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	get_viewport().get_texture().get_image().save_png(path)
	_save_now()
	print("saved ", path, "  fps ", Engine.get_frames_per_second(), "  process ms %.2f" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0))
	get_tree().quit()


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
