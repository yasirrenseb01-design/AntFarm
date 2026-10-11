extends Node2D
## Entry point. Owns the simulation, the world view, the camera and the HUD.
##
## Command-line options (after `--`):
##   --selftest=<days> [--autokeep]   run headless and print colony stats, then quit
##   --shot=<png> [--warm=<days>] [--tod=<0..1>]   fast-forward, save a screenshot, quit
##   --seed=<n>

const Sim := preload("res://scripts/sim/simulation.gd")
const WorldView := preload("res://scripts/view/world_view.gd")
const Hud := preload("res://scripts/view/hud.gd")
const NestView := preload("res://scripts/view/nest_view.gd")

var sim
var world
var hud
var nest_view
var mode := "surface"
static var next_nest := ""      # set before reloading the scene to start a fresh colony
var camera: Camera2D
var speed := 1.0
var _acc := 0.0
var _panning := false
var _zoom_t := 1.0
var _pos_t := Vector2.ZERO
var _opts := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	sim = Sim.new()
	# next_nest is "<soil|glass>:<queen|young>" from the new-colony menu
	var choice: String = next_nest if next_nest != "" else "%s:%s" % [_opts.get("nest", "soil"), "young" if _opts.has("workers") else "queen"]
	var parts := choice.split(":")
	var start: int = int(_opts.get("workers", "14")) if parts[1] == "young" else 0
	sim.setup(int(_opts.get("seed", "0")), start, parts[0] == "glass")
	sim.ant_substep = int(_opts.get("substep", "1"))
	if _opts.has("selftest"):
		_selftest(int(_opts["selftest"]), _opts.has("autokeep"))
		return

	camera = Camera2D.new()
	add_child(camera)
	world = WorldView.new()
	add_child(world)
	world.setup(sim)
	nest_view = NestView.new()
	add_child(nest_view)
	nest_view.setup(sim)
	hud = Hud.new()
	add_child(hud)
	hud.nest_view = nest_view
	hud.setup(sim, world)
	hud.view_changed.connect(_set_mode)
	hud.cam_action.connect(_cam_action)
	nest_view.cut_changed.connect(func(v): hud.set_cut(v))
	hud.new_colony.connect(func(kind):
		next_nest = kind
		get_tree().reload_current_scene())
	hud.speed_changed.connect(func(v):
		speed = v
		# at fast-forward each ant moves every few ticks with a longer stride to keep frame time flat
		sim.ant_substep = 1 if v <= 5 else (2 if v <= 20 else 4))
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()
	camera.position = _pos_t
	camera.zoom = Vector2.ONE * _zoom_t

	if _opts.has("shot"):
		_take_shot()


func _process(delta: float) -> void:
	if world == null:
		return
	if speed > 0:
		_acc += delta * 60.0 * speed
		var n := mini(int(_acc), maxi(2, int(speed * 3.0)))
		_acc = minf(_acc - n, 60.0)
		for i in n:
			sim.step()
	if mode == "surface":
		_ease_surface(delta)
		world.refresh(delta, speed)
	nest_view.speed = speed
	nest_view.refresh(delta)
	hud.refresh(delta)


func _set_mode(m: String) -> void:
	mode = m
	var surface := m == "surface"
	world.visible = surface
	world.set_process_unhandled_input(surface)
	camera.enabled = surface
	nest_view.set_active(not surface)


# ---------------------------------------------------------------- camera

func _view_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(Vector2.ZERO, Vector2(vp.x - hud.PANEL_W - 12, vp.y))


func _fit_zoom() -> float:
	var area := _view_rect()
	return minf(area.size.x / sim.WORLD.x, area.size.y / sim.WORLD.y) * 0.97


func _fit_camera() -> void:
	_zoom_t = _fit_zoom()
	_pos_t = _centre_offset(sim.WORLD * 0.5, _zoom_t)


func _centre_offset(p: Vector2, z: float) -> Vector2:
	# keep point p in the middle of the area left of the side panel
	var vp := get_viewport_rect().size
	return p + Vector2((vp.x * 0.5 - _view_rect().size.x * 0.5) / z, 0)


func _center_on(p: Vector2) -> void:
	_pos_t = _centre_offset(p, _zoom_t)
	camera.position = _pos_t
	camera.zoom = Vector2.ONE * _zoom_t


## World point under a screen position, using where the camera is heading (not where it is now).
func _screen_to_world_t(sp: Vector2) -> Vector2:
	return _pos_t + (sp - get_viewport_rect().size * 0.5) / _zoom_t


func surface_zoom(f: float, at_screen := Vector2.INF) -> void:
	var sp := at_screen if at_screen != Vector2.INF else _view_rect().get_center()
	var before := _screen_to_world_t(sp)
	_zoom_t = clampf(_zoom_t * f, _fit_zoom(), 8.0)
	_pos_t += before - _screen_to_world_t(sp)
	_clamp_camera()


func surface_focus(p: Vector2, zoom: float) -> void:
	_zoom_t = clampf(zoom, _fit_zoom(), 8.0)
	_pos_t = _centre_offset(p, _zoom_t)


func _ease_surface(delta: float) -> void:
	# keyboard: WASD / arrows move, +/- zoom
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv.y += 1
	if mv != Vector2.ZERO:
		_pos_t += mv * 700.0 * delta / _zoom_t
		_clamp_camera()
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		surface_zoom(1.0 + 1.6 * delta)
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		surface_zoom(1.0 / (1.0 + 1.6 * delta))
	var k := 1.0 - exp(-12.0 * delta)
	camera.zoom = Vector2.ONE * lerpf(camera.zoom.x, _zoom_t, k)
	camera.position = camera.position.lerp(_pos_t, k)


func _unhandled_input(e: InputEvent) -> void:
	if camera == null or mode != "surface":
		return
	if e is InputEventMouseButton:
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and e.pressed:
			surface_zoom(1.2 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2, e.position)
		elif e.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_panning = e.pressed
		elif e.button_index == MOUSE_BUTTON_LEFT and world.tool == "pan":
			_panning = e.pressed
			if e.pressed and e.double_click:
				surface_zoom(2.0, e.position)
	elif e is InputEventMouseMotion and _panning:
		_pos_t -= e.relative / _zoom_t
		_clamp_camera()
	elif e is InputEventKey and e.pressed and e.keycode == KEY_HOME:
		_fit_camera()


func _clamp_camera() -> void:
	var margin := Vector2(200, 200) / _zoom_t
	_pos_t = _pos_t.clamp(-margin, sim.WORLD + margin)


## Camera buttons on the HUD, shared by both views.
func _cam_action(a: String) -> void:
	if mode == "surface":
		match a:
			"zoom_in": surface_zoom(1.5)
			"zoom_out": surface_zoom(1.0 / 1.5)
			"reset": _fit_camera()
			"nest": surface_focus(sim.nest_pos, 3.0)
	else:
		match a:
			"zoom_in": nest_view.zoom_by(1.0 / 1.4)
			"zoom_out": nest_view.zoom_by(1.4)
			"left": nest_view.turn_by(0.5)
			"right": nest_view.turn_by(-0.5)
			"reset": nest_view.reset_view()
			_: nest_view.focus(a)


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
		if _opts.has("target"):
			var tp: PackedStringArray = String(_opts["target"]).split(",")
			nest_view.target = Vector3(float(tp[0]), float(tp[1]), float(tp[2]))
			nest_view.snap_camera()
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
