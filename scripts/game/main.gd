extends "res://scripts/dev/dev_tools.gd"
const DesktopMode := preload("res://scripts/game/desktop_mode.gd")
const SaveCheck := preload("res://scripts/sim/save_check.gd")
var desktop                    # desktop mode: the nest as the wallpaper (PART 11)
static var _window_set := false       # the window was maximized at this start (main._ready)
## Entry point. Owns the simulation, the views, the camera and the HUD. Top of the chain:
## parts/main_base <- parts/main_camera <- dev/dev_tools <- main.
##
## Command-line options (after `--`), mostly for testing (see scripts/dev/dev_tools.gd):
##   --selftest=<days> [--autokeep] [--csv=<file>] [--every=<days>] [--nestpng=<png>] [--logs=<n>]
##                                    run headless and print colony stats, then quit
##   --shot=<png> [--warm=<days>] [--tod=<0..1>] [--frames=<n>] [--live]   fast-forward, screenshot, quit
##       --seq=<n> [--seq-every=<frames>]   a strip of frames with the clock running instead of one shot
##       --view=outworld|nest   which view; camera: --yaw --pitch --dist --target=x,y,z --cut --xray
##       --look=queen|larvae|pupae|entrance (nest)   --anim=egg,pupate,eclose,care [--care=eggs|larvae|pupae] (act out life-cycle moments)   --queen-act=<id> (hold the queen in one activity)
##       --orbit=<n> [--orbit-pitch] (nest, after --seq: the last moment from n sides)   --follow-fit[=over|turn] [--side]
##       --follow-pushed   --follow-soil (nest: follow an ant on a slope / climbing over / bending round a turn / pushed /
##       with its body in the soil)   --select[=eggs|larvae|pupae] (nest: click one ant / one item of brood)   --pick-check (nest: do clicks pick the ant clicked)
##       --heater (the heat mat on)   --queen-to=<chamber> [--follow-queen] (nest: the queen walks to that chamber, the camera with her)
##       --feet (with --seq, nest: planted feet in the air, in the soil, in the brood - dev/foot_check.gd; standing still and legs straight - dev/still_check.gd)
##       --follow-carry (nest: the camera on a nestmate carrying a cocoon)   --follow-wid=<n> (nest: on worker #n, printing what it does and its soil)
##       --bodies (with --seq: bodies inside one another, feet in the air - dev/body_check.gd; outworld: foragers in one another, --trace-crowd prints the deep ones, --no-crowd draws them without keeping them apart)
##       --trace (with --seq, nest: print who is by the queen each frame: role, activity, rest, position)   --trace-mates (every nestmate each frame)   --pops (with --seq: print ants that jump between frames)   --turns (with --seq, outworld: foragers' heading swings and body tilts - dev/turn_check.gd)   --stacks (with --seq, nest: brood heaped on brood - dev/stack_check.gd)   --queen-soil (with --seq, nest: her gaster in the soil - dev/queen_check.gd)
##       --at-ant=<i>|walker|act2|act9|act10 (outworld: look at a forager, or one busy at that kind of food)   --at-food=<kind> [--food-age=<days>] (drop one and look at it; an aphid plant that old)   --brush-test[=off] (an ant's push in every tuft of grass)
##       --food-left=<0..1> [--food-age=<days>] (cricket state)   --rain   --colonies (open the slots window)   --newcolony   --fridge
##       --enemy=wolf_spider [--enemy-at=x,y] [--fight=<ticks>] (stage a fight next to the nest)
##       --quality=low|medium|high (graphics)   --guide[=<step>] (the first-colony guide)   --clip (clip mode, as F8)   --title [--title-hover=<i>] (the title screen, as the game opens on it; with --shot too; the pointer on word i)   --species   --settings (those windows open)   --enemy-panel (the enemy panel open)   --release=<kind> [--fight=<ticks>] (let one in from the panel)
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
	if OS.has_feature("template"):
		# (PART EA-R R5) the released game takes only what it passes itself when it starts again as the wallpaper and back
		# (_enter_desktop, desktop_mode.gd) - none of the developer's options: some write files wherever they are told
		# (--shot, --csv, --nestpng), others change the colony or open a test one
		for k in _opts.keys():
			if not k in RELEASE_OPTS:
				_opts.erase(k)
	sim = Sim.new()
	_persist = not (_opts.has("selftest") or _opts.has("shot")) or _opts.has("sandbox")
	if _opts.has("sandbox"):
		Store.base = "user://sandbox/"
	# one game at a time: a game running already (maybe as the wallpaper) is told to come forward, and this copy goes
	var one_port: int = SingleInstance.PORT + (1 if _opts.has("sandbox") else 0)
	if _persist and not _opts.has("testsave"):
		if not _opts.has("desktop") and SingleInstance.tell_running(one_port):
			_persist = false              # (this copy never saves: the one running has the colony)
			get_tree().quit()
			return
		one = SingleInstance.new()
		add_child(one)
		one.listen(one_port)
	# the game opens filling the screen (maximized, the taskbar still there); once per start - a reload for another colony
	# or language keeps the window as the keeper left it
	if _persist and not _window_set and not _opts.has("desktop") and not _opts.has("windowed"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	_window_set = true
	if _opts.has("testsave"):
		# a colony grown by tests/year_run.gd: opened read-only, no time-away catch-up
		Store.base = "user://growtest/%s/" % String(_opts["testsave"]).validate_filename()     # (a name, never a path out of user://)
		_persist = true
		next_slot = int(_opts.get("slot", "1"))
	# the language: the keeper's choice, else the machine's - Thai on a Thai machine, English elsewhere (--lang=th|en: dev)
	if _persist:
		_settings = Store.settings()
	var lang := String(_opts.get("lang", _settings.get("lang", "")))
	L.use(lang if lang != "" else L.default_lang())
	var loaded := false
	var first_run := false
	if _persist:
		_settings = Store.settings()
		slot = next_slot if next_slot > 0 else int(_settings.get("slot", 1))
		if not _opts.has("testsave"):
			home.load_layout()
			if next_slot <= 0:
				# (the last one played, unless it is hidden now - the keeper's slots 2 and 3 until there are more tanks)
				slot = home.pick(slot)
				first_run = slot == 0 and next_nest == ""
				if slot == 0:
					slot = home.tanks[0]
		Harmony.base = Store.base
		harmony.load_purse()
		next_slot = 0
		if next_nest == "":
			var data := Store.load_slot(slot)
			var ver = data.sim.get("version", -1) if data.has("sim") else -1
			var v: int = int(ver) if ver is int or ver is float else -1
			if v > Sim.SAVE_VERSION:
				# saved by a newer game: play a scratch colony and never write over that save
				_persist = false
				_load_note = tr("save_newer") % [slot, v]
			elif v >= 1:
				if v < Sim.SAVE_VERSION:
					Store.backup(slot, "before-v%d" % Sim.SAVE_VERSION)
					data.sim = Migrations.migrate(data.sim, Sim.SAVE_VERSION)
				# (PART EA-R R8: a save changed by hand or by another program is given up on as unreadable, never half loaded)
				var why := SaveCheck.problem(data.sim)
				if why == "":
					sim.from_dict(data.sim)
					loaded = true
					_plan_catchup(data.meta)
				else:
					push_warning("slot %d cannot be loaded: %s" % [slot, why])
					v = 0
			if v < 1 and Store.exists(slot):
				Store.backup(slot, "unreadable-%d" % int(Time.get_unix_time_from_system()))
				_load_note = tr("save_unreadable") % [slot, slot]
		_settings["slot"] = slot
		Store.save_settings(_settings)
	if not loaded:
		# a fresh colony: from the menu, or the very first launch (a lone founding queen)
		var choice: String = next_nest if next_nest != "" else "%s:%s" % [_opts.get("nest", "soil"), "young" if _opts.has("workers") else "queen"]
		if first_run and not _opts.has("workers"):
			# nothing saved yet: a young garden colony behind the title screen until the keeper starts their own
			_demo = true
			choice = "soil:young:wild"
		next_nest = ""
		var parts := choice.split(":")
		var start: int = int(_opts.get("workers", "14")) if parts[1] == "young" else 0
		var scen: String = parts[2] if parts.size() > 2 else String(_opts.get("scenario", "keeper"))
		# (the Home's bigger tank: a bigger box; --big-box: dev)
		var big_box: bool = _opts.has("big-box") or (_persist and not _opts.has("testsave") and home.big != 0 and home.big == slot)
		# (the species picked on the species page: its id, 5th - none before v0.11.55, and from the menu: the first one)
		var species: String = parts[4] if parts.size() > 4 and parts[4] != "" else String(_opts.get("species-id", "lasius_niger"))
		sim.setup(int(_opts.get("seed", "0")), start, parts[0] == "glass", scen, big_box, species)
		if parts.size() > 3:
			sim.set_enemy_rate(float(parts[3]))            # (the keeper's choice in the new-colony window)
	sim.ant_substep = int(_opts.get("substep", "1"))
	if _opts.has("selftest"):
		_selftest(int(_opts["selftest"]), _opts.has("autokeep"))
		return

	nest_view = NestView.new()
	add_child(nest_view)
	nest_view.setup(sim)
	outworld = OutworldView.new()
	add_child(outworld)
	outworld.room_info = _room_info()
	outworld.setup(sim)
	if sim.scenario != "wild":
		OutworldCard.prepare(outworld)          # (the box from above for the Home's tank, taken with each save)
	hud = Hud.new()
	add_child(hud)
	hud.nest_view = nest_view
	hud.outworld = outworld
	hud.setup(sim, outworld.ground)
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
	hud.home = home if _persist and not _opts.has("testsave") else null
	hud.settings = _settings
	hud.colony_new.connect(func(s, kind): _go_to(s, kind))
	hud.colony_play.connect(func(s): _go_to(s, ""))
	hud.language_changed.connect(_change_language)
	hud.settings_changed.connect(func(st):
		_settings.merge(st, true)
		Store.save_settings(_settings)
		_apply_graphics())
	_apply_graphics()
	hud.save_requested.connect(_save_now)
	hud.harmony_spent.connect(func(p):
		harmony.points = maxf(0.0, harmony.points - p)
		harmony.save_purse())
	desktop = DesktopMode.new()
	add_child(desktop)
	desktop.setup(self)
	title = Title.new()
	add_child(title)
	title.setup(self)
	home_room = HomeRoom.new()
	add_child(home_room)
	home_room.setup(self)
	hud.menu_requested.connect(func(): title.open(not _demo))
	if one != null:
		one.wake.connect(_wake)
	hud.desktop_requested.connect(_enter_desktop)
	desktop.failed.connect(func(msg): hud.show_report(tr("desk_title"), msg))
	hud.speed_changed.connect(func(v):
		speed = v
		# at fast-forward each ant moves every few ticks with a longer stride to keep frame time flat
		sim.ant_substep = 1 if v <= 5 else (2 if v <= 20 else 4))
	var start_view: String = _opts.get("view", _settings.get("view", "outworld"))
	if start_view != "nest":
		start_view = "outworld"                 # (a "surface" kept from before v0.11.5: the 2D view is gone)
	if start_view != "nest" or not _opts.has("shot"):          # (a screenshot of the nest sets its own view below)
		hud._apply_mode(start_view)
		_set_mode(start_view)

	if _persist and not loaded:
		_save_now()
	if _load_note != "":
		hud.show_report(tr("save_title"), _load_note)
	if _catchup_left > 0:
		_show_catchup_overlay()
	if _opts.has("clip"):
		title.open_clip.call_deferred()             # (dev: clip mode, as F8 starts it)
	elif _opts.has("title") or (_persist and not skip_title and not _opts.has("testsave") and not _opts.has("desktop") and not _opts.has("no-title")
			and not _opts.has("desktop-after")):
		title.open.call_deferred(not _demo)          # (what the game opens on; deferred: the views place their cameras first)
	if skip_title and _persist and not _demo and not _opts.has("testsave"):
		get_tree().create_timer(1.0).timeout.connect(hud.maybe_guide)
	if _opts.has("guide"):
		# (dev: --guide[=<step>]: the guide on screen, at that step)
		get_tree().create_timer(0.5).timeout.connect(func():
			hud.start_guide()
			hud._guide._show(int(_opts["guide"]) if String(_opts["guide"]).is_valid_int() else 0))
	skip_title = false
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
			quit_game())


func _process(delta: float) -> void:
	if outworld == null:
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED and not desktop.on:
		Engine.max_fps = Graphics.FPS_MINIMIZED                      # (minimized: next to nothing to draw)
	elif Engine.max_fps == Graphics.FPS_MINIMIZED and not desktop.on:
		Engine.max_fps = _fps_cap if _window_in_use else Graphics.FPS_IDLE
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
		_earn(speed * Harmony.GAME_DAYS_PER_HOUR_1X, true)
		# the speed actually reached (steps a second / 60), shown with the frame rate (F3)
		if delta > 0.0:
			hud.real_speed = lerpf(hud.real_speed, done / delta / 60.0, minf(1.0, 2.0 * delta))
	t0 = _pt("sim", t0)
	if desktop != null and desktop.hidden:
		return                 # (the wallpaper, under a full-screen app: nothing to draw - the colony lives on)
	if mode == "outworld":
		outworld.ground.tick_pheromones()
	t0 = _pt("pheromones", t0)
	outworld.speed = speed
	outworld.refresh(delta)
	t0 = _pt("outworld view", t0)
	nest_view.speed = speed
	nest_view.refresh(delta)
	t0 = _pt("nest view", t0)
	hud.harmony = harmony.points if _persist and not _demo and not _opts.has("testsave") else -1.0
	hud.refresh(delta)
	_pt("hud", t0)


## Where this colony's box stands in the Home, for the outworld view to draw the room round it (keeper_room.gd): the
## Home's places and shelves and this slot - or only the slot (a test, the demo: its box on the desk by itself).
func _room_info() -> Dictionary:
	if home != null and _persist and not _opts.has("testsave"):
		return {"places": home.places(), "shelves": home.shelves, "slot": slot, "lamp": bool(_settings.get("home_lamp", true))}
	return {"slot": slot}


## Graphics quality and the frame-rate cap from the settings (game/graphics.gd); the first time, from the graphics card.
func _apply_graphics() -> void:
	if not _settings.has("quality"):
		_settings["quality"] = Graphics.auto_level()
		if _settings.quality == "low" and not _settings.has("fps_cap"):
			_settings["fps_cap"] = 0               # (30 fps: an integrated card's CPU is the limit in a big nest - steady, and half the work)
		if _persist:
			Store.save_settings(_settings)
	_fps_cap = Graphics.FPS_CAPS[clampi(int(_settings.get("fps_cap", 1)), 0, Graphics.FPS_CAPS.size() - 1)]
	if _opts.has("quality"):
		_settings["quality"] = String(_opts["quality"])     # (dev: --quality=low|medium|high)
	if _opts.has("shot") or _opts.has("selftest"):
		_fps_cap = 0                              # (screenshots and the speed checks: as fast as it goes)
	if desktop != null and desktop.on:
		return                                    # (the wallpaper keeps its own 30 fps; this comes back after)
	Graphics.apply(self, String(_settings.quality), _fps_cap if _window_in_use else mini(Graphics.FPS_IDLE, _fps_cap if _fps_cap > 0 else 999))


var _fps_cap := 60
var _window_in_use := true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# another window in front: fewer frames (the colony lives on just the same); back to the cap when in use again
		_window_in_use = what == NOTIFICATION_APPLICATION_FOCUS_IN
		if desktop != null and not desktop.on and outworld != null and not _opts.has("shot"):
			Engine.max_fps = _fps_cap if _window_in_use else mini(Graphics.FPS_IDLE, _fps_cap if _fps_cap > 0 else 999)
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _closing:
			return                      # (saved once: the window's close and Quit both came here, and it saved twice)
		_closing = true
		_save_now()
		if desktop != null and desktop.close():
			return                      # (as the wallpaper: out of the wallpaper layer first, then it quits)
		# the views freed here, before the engine's own shutdown: left to it, quitting from the Home took ~4 s, the window
		# standing there (the keeper, 2026-10-29: 5-8 s) - freed first, it is gone in ~0.5 s
		get_tree().auto_accept_quit = false
		_finish_quit.call_deferred()



func _finish_quit() -> void:
	for c in get_children():
		c.free()
	get_tree().quit()


## "Quit" on the title page: saved as when the window is closed, then the game ends. (Until v0.11.44 it only sent the
## window's close notice round the nodes - the colony was saved, but nothing quits on that notice: the game stayed.)
func quit_game() -> void:
	_notification(NOTIFICATION_WM_CLOSE_REQUEST)


## The nest as the desktop wallpaper (desktop_mode.gd; what went wrong comes back by its `failed` signal). The
## wallpaper layer shows only what Direct3D 12 draws (Vulkan presents straight to the screen, past the layer: nothing
## showed, tested 2026-10-16), and the game draws with Vulkan (D3D12 lost the device on the Intel UHD here): so it is
## saved and started again with D3D12, as the wallpaper.
func _enter_desktop() -> void:
	if _persist and not bool(_settings.get("desk_told", false)) and not _opts.has("desktop") and not _opts.has("desktop-after"):
		# the first time: where the way back is (the tray icon - Windows 11 often hides a new one under the ^)
		hud.confirm(tr("wallpaper"), tr("desk_intro_1") +
			tr("desk_intro_2") +
			tr("desk_intro_3"), tr("desk_go"), func():
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
		if one != null:
			one.stop()                            # (the new copy listens for the shortcut from now on)
		OS.create_process(OS.get_executable_path(), args)
		# (quit after a moment: at once, in the first frames, the views' threads were still starting and it crashed)
		get_tree().create_timer(2.0).timeout.connect(func(): get_tree().quit())
		return
	desktop.enter()


## The desktop shortcut was used while this game runs (single_instance.gd): out of the wallpaper, or the window forward.
func _wake() -> void:
	if desktop.on:
		desktop.leave()
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()


## The keeper picked another language (settings): saved, and the game starts its scene again in it - back where the
## keeper was (the title page if it was open, else the colony).
func _change_language(lang: String) -> void:
	_settings["lang"] = lang
	if _persist:
		Store.save_settings(_settings)
	_save_now()
	next_slot = slot
	skip_title = title == null or not title.is_open
	get_tree().reload_current_scene()
