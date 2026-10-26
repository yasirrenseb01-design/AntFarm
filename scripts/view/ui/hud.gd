extends "res://scripts/view/ui/parts/hud_panel.gd"
## Keeper's instrument panel: clock and speed on top, tools at the bottom, colony readout, nest
## cross-section, population chart and journal on the right. This file is the top of the chain.
## Layers: parts/hud_base <- hud_colonies <- hud_enemies <- hud_stars <- hud_controls <- hud_panel <- hud.

const AntTip := preload("res://scripts/view/ui/ant_tip.gd")
const Guide := preload("res://scripts/view/ui/guide.gd")
const Sounds := preload("res://scripts/view/ui/sounds.gd")
const Music := preload("res://scripts/view/ui/music.gd")


func setup(s, w) -> void:
	sim = s
	ground = w
	sim.logged.connect(_on_logged)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PANEL_W = 410.0 if TranslationServer.get_locale().left(2) == "en" else 352.0
	root.theme = _make_theme()
	_paper_theme = Paper.theme(root.theme)
	add_child(root)
	_build_top(root)
	_build_tools(root)
	_build_panel(root)
	_build_camera_pad(root)
	_build_colonies(root)
	_build_enemies(root)
	_build_stars(root)
	# a soft chime when the keeper must act (water), and the frame rate when asked for (F3)
	_chime = AudioStreamPlayer.new()
	_chime.stream = Sounds.chime()
	_chime.volume_db = -8.0
	add_child(_chime)
	_fps_label = _label("", 13, INK)
	_fps_label.position = Vector2(18, 112)
	_fps_label.visible = false              # (the keeper's choice is applied once the settings arrive)
	root.add_child(_fps_label)
	# hover over an ant for a moment: who it is and what it is doing
	var tip := AntTip.new()
	root.add_child(tip)
	tip.setup(sim, [nest_view, outworld], _display)
	ant_tip = tip
	_build_banner(root)
	_apply_mode("outworld")
	refresh(1.0)


func _on_logged(e: Dictionary) -> void:
	_log_dirty = true
	if e.get("key", "") in [T.warn_lowwater, T.warn_nowater, T.warn_lowhum] and _chime != null:
		_chime.play()
	if e.kind == "named":
		_named_news(L.entry_text(e))


# ---------------------------------------------------------------- a named ant has died (EA3b)

const BANNER_S := 9.0            # seconds the banner stays

var _banner: PanelContainer
var _banner_text: Label
var _banner_t := 0.0
var _banner_lines: Array = []    # (two at once in a bad night: both shown)


## A banner at the top of the view, over the game: the keeper named this ant (sim.name_ant), so its death is news.
func _build_banner(root: Control) -> void:
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", _box(Color(0.16, 0.07, 0.05, 0.94), AMBER, 8, 18, 10))
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.offset_top = 96
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.mouse_filter = Control.MOUSE_FILTER_STOP
	_banner.visible = false
	_banner.z_index = 60
	_banner.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			_banner_t = 0.0)                     # (a click puts it away)
	_banner_text = _label("", 16, INK, _display)
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_text)
	root.add_child(_banner)


func _named_news(text: String) -> void:
	if _banner == null:
		return
	if _banner_t <= 0.0:
		_banner_lines.clear()
	_banner_lines.append(text)
	_banner_lines = _banner_lines.slice(-3)
	_banner_text.text = "\n".join(_banner_lines)
	_banner_t = BANNER_S
	_banner.reset_size()
	_banner.offset_left = -_banner.size.x * 0.5
	_banner.offset_right = _banner.size.x * 0.5
	if _chime != null:
		_chime.play()


func _tick_banner(delta: float) -> void:
	if _banner == null:
		return
	if _banner_t > 0.0:
		_banner_t -= delta
	_banner.visible = _banner_t > 0.0 and visible
	_banner.modulate.a = clampf(_banner_t / 1.2, 0.0, 1.0)      # (fades out over its last second)


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F10:
		for b in _dev_speed_buttons:
			b.visible = not b.visible            # developer fast-forward speeds
			if not b.visible and b.button_pressed:
				# (hiding them while one is on drops back to 5×)
				for o in b.get_parent().get_children():
					if o is Button and o.text == "5×":
						o.button_pressed = true
				speed_changed.emit(5.0)
		return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F3:
		_fps_label.visible = not _fps_label.visible          # show / hide the frame rate
		settings["show_fps"] = _fps_label.visible
		settings_changed.emit(settings)


# ---------------------------------------------------------------- refresh

## 12345 -> "12,345"
static func _thousands(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return ("-" if n < 0 else "") + t + out


func refresh(delta: float) -> void:
	_t += delta
	_tick_banner(delta)
	_tick_stars()
	_clock.text = tr("clock_line") % [sim.year(), sim.date_text(), sim.season_name(), sim.clock_text()]
	var sky := tr("sky_rain") if sim.climate.raining() else (tr("sky_night") if sim.sun_height() < -0.05 else tr("sky_clear"))
	_weather.text = tr("weather_line") % [sim.climate.air, sky, int(sim.activity * 100)]
	_harmony_l.visible = harmony >= 0.0
	if harmony >= 0.0:
		_harmony_l.text = tr("harmony_line") % _thousands(int(harmony))
	_frame += 1
	if _frame == 2:
		_fps_label.visible = bool(settings.get("show_fps", false))
		set_side_open(bool(settings.get("side_open", not _crowded())), false)     # (the top bar has its size by now)
		# background music, at the keeper's volume (not in test shots and runs)
		var testing := Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--shot") or a.begins_with("--selftest"))
		if not testing:
			music = Music.new()
			music.volume = float(settings.get("music", 0.6))
			add_child(music)
	if _fps_label != null and _fps_label.visible:
		_fps_label.text = tr("fps_line") % [Engine.get_frames_per_second(), real_speed]
	if _frame % 4 == 0 and _nest.is_visible_in_tree():
		_nest.queue_redraw()
	if _log_dirty:
		_log_dirty = false
		_render_log()
	if fmod(_t, 0.2) > delta:
		return
	var q: Label = _vals["queen"]
	if not sim.queen.alive:
		_show(q, tr("tip_dead"), DANGER)
	elif sim.hibernating() or sim.climate.nest < 6.0:
		# winter rest: by season (outdoors) or the fridge (indoors), not by the hour
		_show(q, tr("tip_hibernating"), INK)
	elif sim.founding():
		_show(q, tr("queen_fat") % int(sim.queen.reserve / float(sim.sp["queen_reserve"]) * 100.0), LEAF)   # sealed in, living on her reserves
	elif sim.starving or sim.queen.starve > 0.5:
		_show(q, tr("queen_not_laying"), DANGER)
	else:
		_show(q, tr("panel_laying"), LEAF)      # (short: the panel's narrow column)
	_show(_vals["workers"], str(sim.workers.size()))
	_show(_vals["out"], str(sim.out_count))
	_show(_vals["nurses"], str(sim.nurses))
	_show(_vals["callow"], str(sim.callow))
	_show(_vals["eggs"], str(sim.eggs.size()))
	_show(_vals["larvae"], str(sim.larvae.size()), DANGER if sim.protein < 0.5 and sim.larvae.size() > 0 else INK)
	_show(_vals["pupae"], str(sim.pupae.size()))
	var fnd: bool = sim.founding()      # a founding queen lives on her reserves: empty stores are normal
	_show(_vals["sugar"], "%.1f" % sim.sugar, DANGER if sim.sugar < 2.0 and sim.fat < 1.0 and not fnd else INK)
	_show(_vals["fat"], "%.1f" % sim.fat)
	_show(_vals["protein"], "%.1f" % sim.protein, DANGER if sim.protein < 1.0 and not fnd else INK)
	_show(_vals["nest_t"], "%.1f°C" % sim.climate.nest, DANGER if sim.climate.nest > 34.0 else INK)
	# each chamber's warmth by its depth, and who is kept where (sim_warmth)
	var rows := PackedStringArray([tr("nest_temp_tip")])
	for i in sim.nest.chambers.size():
		if not sim.nest.chambers[i].get("open", true):
			continue
		var who := PackedStringArray()
		if i == sim.queen_at and sim.queen.alive:
			who.append(tr("queen"))
		if i == int(sim.brood_at.get("larvae", -1)) and not sim.larvae.is_empty():
			who.append(tr("larvae"))
		if i == int(sim.brood_at.get("pupae", -1)) and not sim.pupae.is_empty():
			who.append(tr("pupae"))
		rows.append(tr("chamber_temp_row") % [sim.chamber_depth_cm(i), sim.chamber_temp(i), (" · ".join(who)) if not who.is_empty() else ""])
	_vals["nest_t"].tooltip_text = "
".join(rows)
	_show(_vals["dev"], "%d%%" % int(sim.dev * 100))
	_show(_vals["dead"], str(sim.stats.dead))
	_show(_vals["brood_dead"], str(sim.stats.brood_dead + sim.stats.cannibalized))
	var by: Dictionary = sim.stats.dead_by
	var causes := []
	for k in [["starve", tr("death_starve")], ["thirst", tr("death_thirst")], ["old", tr("death_old")], ["out", tr("death_out")], ["enemy", tr("death_enemy")], ["other", tr("death_other")]]:
		if int(by.get(k[0], 0)) > 0:
			causes.append("%s %d" % [k[1], by[k[0]]])
	_vals["dead"].tooltip_text = tr("death_causes") + (", ".join(causes) if not causes.is_empty() else "-")
	_vals["brood_dead"].tooltip_text = tr("brood_dead_tip") % [
		sim.stats.brood_dead, sim.stats.cannibalized]
	var cyc: float = sim.cycle_days()
	_show(_vals["cycle"], tr("cycle_stopped") if cyc == INF else tr("days_d") % int(cyc))
	_show(_vals["vol"], tr("cm3") % sim.nest.volume_cm3(), DANGER if sim.nest.air < sim.target_air() * 0.7 and not fnd else INK)
	_show(_vals["depth"], tr("depth_short") % sim.nest.depth_cm())        # (the chambers: in the cross-section's heading)
	_show(_vals["size"], tr("mm") % sim.mean_worker_mm() if not sim.workers.is_empty() else tr("not_yet"))
	var words := {"queen_hi": tr("trait_queen_hi"), "queen_lo": tr("trait_queen_lo"), "forage_hi": tr("trait_forage_hi"),
		"forage_lo": tr("trait_forage_lo"), "life_hi": tr("trait_life_hi"), "life_lo": tr("trait_life_lo"),
		"size_hi": tr("trait_size_hi"), "size_lo": tr("trait_size_lo"), "depth_hi": tr("trait_depth_hi"),
		"depth_lo": tr("trait_depth_lo"), "spread_hi": tr("trait_spread_hi"), "spread_lo": tr("trait_spread_lo")}
	var said: Array = sim.trait_words().map(func(w): return words.get(w, w))
	_vals["character"].text = tr("trait_title") + "  " + (" · ".join(said) if not said.is_empty() else tr("trait_plain"))
	var hum: float = sim.humidity
	_hum_bar.value = hum * 100.0
	var ok: bool = hum >= sim.sp["humidity_ok_min"] and hum <= sim.sp["humidity_ok_max"]
	_show(_vals["hum"], "%d%%" % int(hum * 100), INK if ok else DANGER)
	_chart.queue_redraw()
	_refresh_enemies()
	_refresh_stars()


# ---------------------------------------------------------------- the first-colony guide (PART EA-R R4)

var _guide = null


## Starts the guide (ui/guide.gd) over the game; done or skipped, it is not shown again (settings "guide_done").
func start_guide() -> void:
	if _guide != null and is_instance_valid(_guide):
		return
	if not sim.scenario in ["keeper", "wild"]:
		return
	_apply_mode("outworld")
	view_changed.emit("outworld")             # (the food and the tools are out there)
	_guide = Guide.new()
	get_child(0).add_child(_guide)
	_guide.setup(self)
	_guide.finished.connect(func():
		settings["guide_done"] = true
		settings_changed.emit(settings))


## Shows the guide if the keeper has not been through it yet.
func maybe_guide() -> void:
	if not bool(settings.get("guide_done", false)):
		start_guide()
