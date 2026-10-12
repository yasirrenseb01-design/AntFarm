extends "res://scripts/dev/dev_tools.gd"
## Entry point. Owns the simulation, the views, the camera and the HUD. Top of the chain:
## parts/main_base <- parts/main_camera <- dev/dev_tools <- main.
##
## Command-line options (after `--`), mostly for testing (see scripts/dev/dev_tools.gd):
##   --selftest=<days> [--autokeep] [--csv=<file>] [--every=<days>] [--nestpng=<png>] [--logs=<n>]
##                                    run headless and print colony stats, then quit
##   --shot=<png> [--warm=<days>] [--tod=<0..1>] [--frames=<n>] [--live]   fast-forward, screenshot, quit
##       --seq=<n> [--seq-every=<frames>]   a strip of frames with the clock running instead of one shot
##       --view=outworld|surface|nest   which view; camera: --yaw --pitch --dist --target=x,y,z --cut --xray
##       --look=queen|larvae|pupae|entrance (nest)   --anim=egg,pupate,eclose (act out life-cycle moments)   --queen-act=<id> (hold the queen in one activity)
##       --trace (with --seq, nest: print who is by the queen each frame: role, activity, rest, position)   --pops (with --seq: print ants that jump between frames)
##       --at-ant=<i>|walker|act2|act9|act10 (outworld: look at a forager, or one busy at that kind of food)   --at-food=<kind> (drop one and look at it)
##       --food-left=<0..1> [--food-age=<days>] (cricket state)   --rain   --colonies (open the slots window)   --newcolony   --fridge
##       --enemy=wolf_spider [--enemy-at=x,y] [--fight=<ticks>] (stage a fight next to the nest)
##   --seed=<n>   --workers=<n> (start with a young colony instead of a lone queen)   --nest=soil|glass
##   --scenario=keeper|wild (indoor formicarium, or a plot of ground with seasons and predators)
##   --substep=<n>   --sandbox [--pretend-away=<hours>]   use a separate save folder (tests)
##   --testsave=<name> [--slot=<year>]   open a colony grown by tests/year_run.gd (read-only)


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
	var start_view: String = _opts.get("view", _settings.get("view", "outworld"))
	if start_view != "nest":          # a screenshot of the nest sets its own view below
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
		for i in n:
			sim.step()
	t0 = _pt("sim", t0)
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
