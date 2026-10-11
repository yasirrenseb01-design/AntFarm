extends Node2D
## Entry point. Owns the simulation, the world view, the camera and the HUD.
##
## Command-line options (after `--`):
##   --selftest=<days> [--autokeep]   run headless and print colony stats, then quit
##   --shot=<png> [--warm=<days>] [--tod=<0..1>]   fast-forward, save a screenshot, quit
##   --seed=<n>
##   --sandbox [--pretend-away=<hours>]   use a separate save folder (tests), optionally fake time away

const Sim := preload("res://scripts/sim/simulation.gd")
const WorldView := preload("res://scripts/view/world_view.gd")
const Hud := preload("res://scripts/view/hud.gd")
const NestView := preload("res://scripts/view/nest_view.gd")
const Store := preload("res://scripts/save_store.gd")

var sim
var world
var hud
var nest_view
var mode := "surface"
static var next_nest := ""      # "<soil|glass>:<queen|young>": start a fresh colony after the reload
static var next_slot := 0       # which save slot to open after the reload (0 = the last one played)
var slot := 1
var _persist := false           # tests and screenshots never touch the player's saves
var _settings := {}
var _autosave_t := 0.0
var _catchup_left := 0          # ticks still to simulate for the time the game was closed
var _catchup_total := 0
var _away_before := {}
var _away_events: Array = []
var _away_hours := 0.0
var _away_capped := false
var _overlay: CanvasLayer
var _overlay_label: Label
var _overlay_bar: ProgressBar
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
	_persist = not (_opts.has("selftest") or _opts.has("shot")) or _opts.has("sandbox")
	if _opts.has("sandbox"):
		Store.base = "user://sandbox/"
	var loaded := false
	if _persist:
		_settings = Store.settings()
		slot = next_slot if next_slot > 0 else int(_settings.get("slot", 1))
		next_slot = 0
		if next_nest == "":
			var data := Store.load_slot(slot)
			if not data.is_empty() and data.sim.get("version", -1) == Sim.SAVE_VERSION:
				sim.from_dict(data.sim)
				loaded = true
				_plan_catchup(data.meta)
		_settings["slot"] = slot
		Store.save_settings(_settings)
	if not loaded:
		# a fresh colony: from the menu, or the very first launch (a lone founding queen)
		var choice: String = next_nest if next_nest != "" else "%s:%s" % [_opts.get("nest", "soil"), "young" if _opts.has("workers") else "queen"]
		next_nest = ""
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
	hud.current_slot = slot
	hud.settings = _settings
	hud.colony_new.connect(func(s, kind): _go_to(s, kind))
	hud.colony_play.connect(func(s): _go_to(s, ""))
	hud.settings_changed.connect(func(st):
		_settings.merge(st, true)
		Store.save_settings(_settings))
	hud.save_requested.connect(_save_now)
	hud.speed_changed.connect(func(v):
		speed = v
		# at fast-forward each ant moves every few ticks with a longer stride to keep frame time flat
		sim.ant_substep = 1 if v <= 5 else (2 if v <= 20 else 4))
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()
	camera.position = _pos_t
	camera.zoom = Vector2.ONE * _zoom_t

	if _persist and not loaded:
		_save_now()
	if _catchup_left > 0:
		_show_catchup_overlay()
	if _opts.has("shot"):
		_take_shot()


func _process(delta: float) -> void:
	if world == null:
		return
	if _catchup_left > 0:
		_run_catchup()
		return
	if _persist:
		_autosave_t += delta
		if _autosave_t >= 60.0:
			_save_now()
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


# ---------------------------------------------------------------- saving and time away

func _save_now() -> void:
	if _persist and sim != null:
		Store.save(slot, sim)
		_autosave_t = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_now()


## Switch to another slot, or start a fresh colony in one: save the current colony, then reload.
func _go_to(target_slot: int, kind: String) -> void:
	_save_now()
	if kind != "":
		Store.delete(target_slot)
	next_slot = target_slot
	next_nest = kind
	get_tree().reload_current_scene()


## Work out how much game time passed while the game was closed.
func _plan_catchup(meta: Dictionary) -> void:
	var rate := Store.away_rate(int(_settings.get("away", 3)))
	var real_s: float = maxf(0.0, Time.get_unix_time_from_system() - float(meta.get("saved_unix", 0.0)))
	real_s += float(_opts.get("pretend-away", "0")) * 3600.0
	var days := real_s / 3600.0 * rate
	_away_hours = real_s / 3600.0
	_away_capped = days > Store.MAX_AWAY_DAYS
	days = minf(days, Store.MAX_AWAY_DAYS)
	if days < 0.02:
		return
	_catchup_total = int(days * sim.TPD)
	_catchup_left = _catchup_total
	_away_before = sim.summary()
	sim.logged.connect(_collect_away_event)


func _collect_away_event(e: Dictionary) -> void:
	if _catchup_left > 0 and e.kind != "":
		_away_events.append(e)


func _show_catchup_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 20
	add_child(_overlay)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.045, 0.035, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520, 0)
	box.position = get_viewport_rect().size * 0.5 - Vector2(260, 60)
	box.add_theme_constant_override("separation", 12)
	_overlay.add_child(box)
	_overlay_label = Label.new()
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 18)
	_overlay_label.add_theme_color_override("font_color", Color("f1e6d6"))
	box.add_child(_overlay_label)
	_overlay_bar = ProgressBar.new()
	_overlay_bar.custom_minimum_size = Vector2(520, 14)
	_overlay_bar.show_percentage = false
	box.add_child(_overlay_bar)


## Simulate the time away in slices that fit in a frame, so the window stays responsive.
func _run_catchup() -> void:
	sim.ant_substep = 4      # fastest stride that stays unbiased against full-detail stepping (tested)
	var care: bool = _settings.get("care", true)
	var t0 := Time.get_ticks_msec()
	while _catchup_left > 0 and Time.get_ticks_msec() - t0 < 40:
		sim.step()
		_catchup_left -= 1
		if care and sim.tick % sim.TPD == sim.TPD / 4:
			sim.auto_care(sim.day())
	var done := _catchup_total - _catchup_left
	_overlay_label.text = "ระหว่างที่คุณไม่อยู่ รังยังมีชีวิตต่อ…\nกำลังจำลอง %.1f จาก %.1f วันในเกม" % [
		float(done) / sim.TPD, float(_catchup_total) / sim.TPD]
	_overlay_bar.value = 100.0 * done / maxf(1.0, _catchup_total)
	if _catchup_left <= 0:
		sim.ant_substep = 1
		_overlay.queue_free()
		_save_now()
		_report_away()


func _report_away() -> void:
	var b: Dictionary = _away_before
	var a: Dictionary = sim.summary()
	var lines := PackedStringArray()
	lines.append("คุณไม่อยู่ %s → ในรังผ่านไป %.1f วัน (วันที่ %d → %d)%s" % [_hours_text(_away_hours),
		float(_catchup_total) / sim.TPD, b.day, a.day, "\n(จำลองให้สูงสุด %d วันในเกม)" % int(Store.MAX_AWAY_DAYS) if _away_capped else ""])
	lines.append("")
	lines.append("มดงาน  %d → %d   (เกิดใหม่ %d · ตาย %d)" % [b.workers, a.workers, a.born - b.born, a.dead - b.dead])
	lines.append("ไข่ %d · ตัวอ่อน %d · ดักแด้ %d" % [a.eggs, a.larvae, a.pupae])
	lines.append("ห้องในรัง  %d → %d   · ปริมาตร %.1f ซม³" % [b.chambers, a.chambers, a.volume])
	lines.append("ความชื้นในรังตอนนี้ %d%%%s" % [int(a.humidity * 100), "  (ควรเติมน้ำ)" if a.humidity < 0.35 else ""])
	if not a.queen:
		lines.append("ราชินีตายระหว่างที่คุณไม่อยู่")
	if not _away_events.is_empty():
		lines.append("")
		lines.append("เรื่องที่เกิดขึ้น:")
		var shown := 0
		for e in _away_events:
			if shown >= 8:
				lines.append("…และอีก %d เรื่อง" % (_away_events.size() - shown))
				break
			lines.append("• %s  %s" % [e.stamp, e.text])
			shown += 1
	hud.show_report("ระหว่างที่คุณไม่อยู่", "\n".join(lines))


func _hours_text(h: float) -> String:
	if h < 1.0:
		return "%d นาที" % int(h * 60.0)
	if h < 48.0:
		return "%.1f ชั่วโมง" % h
	return "%.1f วัน" % (h / 24.0)


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
	if _opts.has("colonies"):
		hud.open_colonies()
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
