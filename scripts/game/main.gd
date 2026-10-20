extends "res://scripts/dev/dev_tools.gd"
const DesktopMode := preload("res://scripts/game/desktop_mode.gd")
var desktop                    # desktop mode: the nest as the wallpaper (PART 11)
## Entry point. Owns the simulation, the views, the camera and the HUD. Top of the chain:
## parts/main_base <- parts/main_camera <- dev/dev_tools <- main.
##
## Command-line options (after `--`), mostly for testing (see scripts/dev/dev_tools.gd):
##   --selftest=<days> [--autokeep] [--csv=<file>] [--every=<days>] [--nestpng=<png>] [--logs=<n>]
##                                    run headless and print colony stats, then quit
##   --shot=<png> [--warm=<days>] [--tod=<0..1>] [--frames=<n>] [--live]   fast-forward, screenshot, quit
##       --seq=<n> [--seq-every=<frames>]   a strip of frames with the clock running instead of one shot
##       --view=outworld|surface|nest   which view; camera: --yaw --pitch --dist --target=x,y,z --cut --xray
##       --look=queen|larvae|pupae|entrance (nest)   --anim=egg,pupate,eclose,care [--care=eggs|larvae|pupae] (act out life-cycle moments)   --queen-act=<id> (hold the queen in one activity)
##       --orbit=<n> [--orbit-pitch] (nest, after --seq: the last moment from n sides)   --follow-fit[=over|turn] [--side]
##       --follow-pushed   --follow-soil (nest: follow an ant on a slope / climbing over / bending round a turn / pushed /
##       with its body in the soil)   --select[=eggs|larvae|pupae] (nest: click one ant / one item of brood)   --pick-check (nest: do clicks pick the ant clicked)
##       --bodies (with --seq, nest: bodies inside one another, feet in the air - dev/body_check.gd)
##       --trace (with --seq, nest: print who is by the queen each frame: role, activity, rest, position)   --trace-mates (every nestmate each frame)   --pops (with --seq: print ants that jump between frames)
##       --at-ant=<i>|walker|act2|act9|act10 (outworld: look at a forager, or one busy at that kind of food)   --at-food=<kind> (drop one and look at it)
##       --food-left=<0..1> [--food-age=<days>] (cricket state)   --rain   --colonies (open the slots window)   --newcolony   --fridge
##       --enemy=wolf_spider [--enemy-at=x,y] [--fight=<ticks>] (stage a fight next to the nest)
##       --enemy-panel (the enemy panel open)   --release=<kind> [--fight=<ticks>] (let one in from the panel)
##   --seed=<n>   --workers=<n> (start with a young colony instead of a lone queen)   --nest=soil|glass
##   --scenario=keeper|wild (indoor formicarium, or a plot of ground with seasons and predators)
##   --substep=<n>   --sandbox [--pretend-away=<hours>]   use a separate save folder (tests)
##   --testsave=<name> [--slot=<year>]   open a colony grown by tests/year_run.gd (read-only)
##   --desktop   start as the desktop wallpaper (desktop_mode.gd; back to the game from the tray icon)
##       [--win=x,y,w,h,mode] (the game window to go back to: passed on when the game starts itself again)
##       [--no-cover-check] (dev: draw even under a full-screen app)   --quit-after=<s> (dev: close after s seconds)
##       --leave-after=<s> (dev: back to the game after s seconds, as the tray icon)
##       --gpu=<i> (dev: started again with D3D12 on that GPU: 1 = the RTX here)   --desktop-after=<s> (dev: as if the button were pressed)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	sim = Sim.new()
	_persist = not (_opts.has("selftest") or _opts.has("shot")) or _opts.has("sandbox")
	if _opts.has("sandbox"):
		Store.base = "user://sandbox/"
	if _opts.has("testsave"):
		# a colony grown by tests/year_run.gd: opened read-only, no time-away catch-up
		Store.base = "user://growtest/%s/" % _opts["testsave"]
		_persist = true
		next_slot = int(_opts.get("slot", "1"))
	var loaded := false
	if _persist:
		_settings = Store.settings()
		slot = next_slot if next_slot > 0 else int(_settings.get("slot", 1))
		next_slot = 0
		if next_nest == "":
			var data := Store.load_slot(slot)
			var v: int = int(data.sim.get("version", -1)) if data.has("sim") else -1
			if v > Sim.SAVE_VERSION:
				# saved by a newer game: play a scratch colony and never write over that save
				_persist = false
				_load_note = "รัง %d ถูกบันทึกด้วยเกมเวอร์ชันใหม่กว่านี้ (รูปแบบเซฟ %d) เกมนี้จึงเปิดรังทดลองให้แทน\nและจะไม่บันทึกทับรังนั้น — อัปเดตเกมแล้วรังจะกลับมาเหมือนเดิม" % [slot, v]
			elif v >= 1:
				if v < Sim.SAVE_VERSION:
					Store.backup(slot, "before-v%d" % Sim.SAVE_VERSION)
					data.sim = Migrations.migrate(data.sim, Sim.SAVE_VERSION)
				sim.from_dict(data.sim)
				loaded = true
				_plan_catchup(data.meta)
			elif Store.exists(slot):
				Store.backup(slot, "unreadable-%d" % int(Time.get_unix_time_from_system()))
				_load_note = "อ่านเซฟรัง %d ไม่ได้ เก็บไฟล์เดิมไว้ในโฟลเดอร์เซฟแล้ว (slot%d.unreadable-…) และเริ่มรังใหม่" % [slot, slot]
		_settings["slot"] = slot
		Store.save_settings(_settings)
	if not loaded:
		# a fresh colony: from the menu, or the very first launch (a lone founding queen)
		var choice: String = next_nest if next_nest != "" else "%s:%s" % [_opts.get("nest", "soil"), "young" if _opts.has("workers") else "queen"]
		next_nest = ""
		var parts := choice.split(":")
		var start: int = int(_opts.get("workers", "14")) if parts[1] == "young" else 0
		var scen: String = parts[2] if parts.size() > 2 else String(_opts.get("scenario", "keeper"))
		sim.setup(int(_opts.get("seed", "0")), start, parts[0] == "glass", scen)
		if parts.size() > 3:
			sim.set_enemy_rate(float(parts[3]))            # (the keeper's choice in the new-colony window)
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
	outworld = OutworldView.new()
	add_child(outworld)
	outworld.setup(sim, world)
	hud = Hud.new()
	add_child(hud)
	hud.nest_view = nest_view
	hud.outworld = outworld
	hud.setup(sim, world)
	hud.view_changed.connect(func(m):
		_set_mode(m)
		if _persist:
			_settings["view"] = m
			Store.save_settings(_settings))
	hud.cam_action.connect(_cam_action)
	hud.enemy_watch.connect(func(id):
		# (the enemy panel: watch it in the 3D outworld, the camera riding along)
		if mode != "outworld":
			hud._apply_mode("outworld")
			_set_mode("outworld")
		outworld.follow_creature(id))
	nest_view.cut_changed.connect(func(v): hud.set_cut(v))
	hud.current_slot = slot
	hud.settings = _settings
	hud.colony_new.connect(func(s, kind): _go_to(s, kind))
	hud.colony_play.connect(func(s): _go_to(s, ""))
	hud.settings_changed.connect(func(st):
		_settings.merge(st, true)
		Store.save_settings(_settings))
	hud.save_requested.connect(_save_now)
	desktop = DesktopMode.new()
	add_child(desktop)
	desktop.setup(self)
	hud.desktop_requested.connect(_enter_desktop)
	desktop.failed.connect(func(msg): hud.show_report("โหมดเดสก์ท็อป", msg))
	hud.speed_changed.connect(func(v):
		speed = v
		# at fast-forward each ant moves every few ticks with a longer stride to keep frame time flat
		sim.ant_substep = 1 if v <= 5 else (2 if v <= 20 else 4))
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()
	camera.position = _pos_t
	camera.zoom = Vector2.ONE * _zoom_t
	var start_view: String = _opts.get("view", _settings.get("view", "outworld"))
	if start_view != "nest" or not _opts.has("shot"):          # (a screenshot of the nest sets its own view below)
		hud._apply_mode(start_view)
		_set_mode(start_view)

	if _persist and not loaded:
		_save_now()
	if _load_note != "":
		hud.show_report("เซฟ", _load_note)
	if _catchup_left > 0:
		_show_catchup_overlay()
	if _opts.has("shot"):
		_take_shot()
	elif _opts.has("desktop-after"):
		get_tree().create_timer(float(_opts["desktop-after"])).timeout.connect(_enter_desktop)    # (dev: as the button does, mid-game)
	elif _opts.has("desktop"):
		_enter_desktop.call_deferred()          # (started as the wallpaper: --desktop)
		desktop.check_cover = not _opts.has("no-cover-check")
		if _opts.has("leave-after"):
			# (dev: back to the game after that many seconds, as a click on the tray icon does)
			get_tree().create_timer(float(_opts["leave-after"])).timeout.connect(desktop.leave)
	if _opts.has("quit-after") and not _opts.has("shot"):
		# (dev: close as the keeper would after that many seconds - desktop mode checked on the real desktop)
		get_tree().create_timer(float(_opts["quit-after"])).timeout.connect(func():
			_notification(NOTIFICATION_WM_CLOSE_REQUEST)
			if not desktop.on:
				get_tree().quit())


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
	var t0 := Time.get_ticks_usec()
	if speed > 0:
		_acc += delta * 60.0 * speed
		var n := mini(int(_acc), maxi(2, int(speed * 3.0)))
		_acc = minf(_acc - n, 60.0)
		# fast-forward (developer speeds) runs as fast as the machine allows while the picture stays at ~30 frames a
		# second: the simulation gets what is left of ~33 ms after the rest of the last frame (drawing, the ants'
		# bodies) - a fixed 30 ms on top of that left 100x at ~20 fps, the ants jumping from frame to frame; the steps
		# not taken are dropped, not owed (determinism is per step)
		var rest_us := maxf(0.0, delta * 1000000.0 - float(_sim_us))
		var budget := t0 + (int(clampf(33000.0 - rest_us, 6000.0, 30000.0)) if speed > 5.0 else 1000000)
		var done := 0
		for i in n:
			sim.step()
			done += 1
			if Time.get_ticks_usec() > budget:
				_acc = 0.0
				break
		_sim_us = Time.get_ticks_usec() - t0
		# the speed actually reached (steps a second / 60), shown with the frame rate (F3)
		if delta > 0.0:
			hud.real_speed = lerpf(hud.real_speed, done / delta / 60.0, minf(1.0, 2.0 * delta))
	t0 = _pt("sim", t0)
	if desktop != null and desktop.hidden:
		return                 # (the wallpaper, under a full-screen app: nothing to draw - the colony lives on)
	if mode == "surface":
		_ease_surface(delta)
		world.refresh(delta, speed)
	elif mode == "outworld":
		world.tick_pheromones()
	t0 = _pt("pheromones", t0)
	outworld.speed = speed
	outworld.refresh(delta)
	t0 = _pt("outworld view", t0)
	nest_view.speed = speed
	nest_view.refresh(delta)
	t0 = _pt("nest view", t0)
	hud.refresh(delta)
	_pt("hud", t0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_now()
		if desktop != null:
			desktop.close()             # (as the wallpaper: out of the wallpaper layer first, then it quits)


## The nest as the desktop wallpaper (desktop_mode.gd; what went wrong comes back by its `failed` signal). The
## wallpaper layer shows only what Direct3D 12 draws (Vulkan presents straight to the screen, past the layer: nothing
## showed, tested 2026-10-16), and the game draws with Vulkan (D3D12 lost the device on the Intel UHD here): so it is
## saved and started again with D3D12, as the wallpaper.
func _enter_desktop() -> void:
	if _persist and not bool(_settings.get("desk_told", false)) and not _opts.has("desktop") and not _opts.has("desktop-after"):
		# the first time: where the way back is (the tray icon - Windows 11 often hides a new one under the ^)
		hud.confirm("วอลเปเปอร์", "รังมดจะไปอยู่เป็นภาพพื้นหลังเดสก์ท็อป หลังไอคอน (เกมเซฟแล้วเปิดตัวเองใหม่ ครั้งแรกอาจใช้เวลาครึ่งนาที)\n\n" +
			"กลับมาเล่น: คลิกไอคอนมดที่ถาดระบบ มุมขวาล่างของจอ — Windows 11 มักซ่อนไอคอนใหม่ไว้ใต้ลูกศร ^\n" +
			"(ลากไอคอนมดออกมาวางข้างนาฬิกาจะหาง่ายขึ้น) · คลิกขวาที่ไอคอน: เมนูปิดเกม", "ตั้งเป็นวอลเปเปอร์", func():
				_settings["desk_told"] = true
				Store.save_settings(_settings)
				_enter_desktop())
		return
	if OS.get_name() == "Windows" and RenderingServer.get_current_rendering_driver_name() != _opts.get("desk-driver", "d3d12"):
		if not desktop.available():
			desktop.enter()                       # (says why it cannot)
			return
		_save_now()
		var args := []
		if not OS.has_feature("template"):
			args += ["--path", ProjectSettings.globalize_path("res://")]      # (running from the editor build)
		var drv: String = _opts.get("desk-driver", "d3d12")             # (dev: other drivers tried)
		args += ["--rendering-driver", drv, "--rendering-method", "gl_compatibility" if drv.begins_with("opengl3") else "mobile"]
		if _opts.has("gpu"):
			args += ["--gpu-index", str(_opts["gpu"])]                       # (dev: the RTX, not the Intel UHD)
		args.append("--")
		args.append("--desktop")
		for k in ["testsave", "slot", "sandbox", "no-cover-check", "quit-after", "leave-after", "view", "gpu", "desk-driver"]:
			if _opts.has(k):
				args.append("--%s=%s" % [k, _opts[k]])
		# the window as it is, to come back to (desktop_mode.gd)
		var wp := DisplayServer.window_get_position()
		var ws := DisplayServer.window_get_size()
		args.append("--win=%d,%d,%d,%d,%d" % [wp.x, wp.y, ws.x, ws.y, DisplayServer.window_get_mode()])
		OS.create_process(OS.get_executable_path(), args)
		# (quit after a moment: at once, in the first frames, the views' threads were still starting and it crashed)
		get_tree().create_timer(2.0).timeout.connect(func(): get_tree().quit())
		return
	desktop.enter()


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
