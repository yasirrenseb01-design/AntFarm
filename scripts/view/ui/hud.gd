extends "res://scripts/view/ui/parts/hud_panel.gd"
## Keeper's instrument panel: clock and speed on top, tools at the bottom, colony readout, nest
## cross-section, population chart and journal on the right. This file is the top of the chain.
## Layers: parts/hud_base <- hud_colonies <- hud_enemies <- hud_stars <- hud_controls <- hud_panel <- hud.

const AntTip := preload("res://scripts/view/ui/ant_tip.gd")
const Sounds := preload("res://scripts/view/ui/sounds.gd")
const Lofi := preload("res://scripts/view/ui/lofi.gd")


func setup(s, w) -> void:
	sim = s
	ground = w
	sim.logged.connect(_on_logged)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	if e.text in [T.warn_lowwater, T.warn_nowater, T.warn_lowhum] and _chime != null:
		_chime.play()
	if e.kind == "named":
		_named_news(e.text)


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

func refresh(delta: float) -> void:
	_t += delta
	_tick_banner(delta)
	_tick_stars()
	_clock.text = "ปีที่ %d · %s · %s  %s" % [sim.year(), sim.date_text(), sim.season_name(), sim.clock_text()]
	var sky := "ฝนตก" if sim.climate.raining() else ("กลางคืน" if sim.sun_height() < -0.05 else "แจ่มใส")
	_weather.text = "อากาศ %.1f°C · %s · มดออกหากิน %d%%" % [sim.climate.air, sky, int(sim.activity * 100)]
	_frame += 1
	if _frame == 2:
		_fps_label.visible = bool(settings.get("show_fps", false))
		set_side_open(bool(settings.get("side_open", not _crowded())), false)     # (the top bar has its size by now)
		# background music, at the keeper's volume (not in test shots and runs)
		var testing := Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--shot") or a.begins_with("--selftest"))
		if not testing:
			music = Lofi.new()
			music.volume = float(settings.get("music", 0.6))
			add_child(music)
	if _fps_label != null and _fps_label.visible:
		_fps_label.text = "%d FPS · จริง %.1f×" % [Engine.get_frames_per_second(), real_speed]
	if _frame % 4 == 0 and _nest.is_visible_in_tree():
		_nest.queue_redraw()
	if _log_dirty:
		_log_dirty = false
		_render_log()
	if fmod(_t, 0.2) > delta:
		return
	var q: Label = _vals["queen"]
	if not sim.queen.alive:
		_show(q, "ตายแล้ว", DANGER)
	elif sim.hibernating() or sim.climate.nest < 6.0:
		# winter rest: by season (outdoors) or the fridge (indoors), not by the hour
		_show(q, "จำศีล", INK)
	elif sim.founding():
		_show(q, "ไขมัน %d%%" % int(sim.queen.reserve / float(sim.sp["queen_reserve"]) * 100.0), LEAF)   # sealed in, living on her reserves
	elif sim.starving or sim.queen.starve > 0.5:
		_show(q, "หยุดวางไข่", DANGER)
	else:
		_show(q, "วางไข่", LEAF)
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
	_show(_vals["dev"], "%d%%" % int(sim.dev * 100))
	_show(_vals["dead"], str(sim.stats.dead))
	_show(_vals["brood_dead"], str(sim.stats.brood_dead + sim.stats.cannibalized))
	var by: Dictionary = sim.stats.dead_by
	var causes := []
	for k in [["starve", "อดอาหาร"], ["thirst", "ขาดน้ำ"], ["old", "แก่ตาย"], ["out", "หายตอนออกหากิน"], ["enemy", "ศัตรูกัด"], ["other", "ไม่ทราบ (เซฟเก่า)"]]:
		if int(by.get(k[0], 0)) > 0:
			causes.append("%s %d" % [k[1], by[k[0]]])
	_vals["dead"].tooltip_text = "สาเหตุ: " + (", ".join(causes) if not causes.is_empty() else "-")
	_vals["brood_dead"].tooltip_text = "ไข่/ตัวอ่อน/ดักแด้ที่ตายเพราะแห้ง ราขึ้น หรือร้อนเกิน %d · ตัวอ่อนที่มดงานกินตอนขาดโปรตีน %d" % [
		sim.stats.brood_dead, sim.stats.cannibalized]
	var cyc: float = sim.cycle_days()
	_show(_vals["cycle"], "หยุด" if cyc == INF else "%d วัน" % int(cyc))
	_show(_vals["vol"], "%.1f ซม³" % sim.nest.volume_cm3(), DANGER if sim.nest.air < sim.target_air() * 0.7 and not fnd else INK)
	_show(_vals["depth"], "%.1f ซม · %d ห้อง" % [sim.nest.depth_cm(), sim.nest.chambers.size()])
	_show(_vals["size"], "%.1f มม." % sim.mean_worker_mm() if not sim.workers.is_empty() else "ยังไม่มี")
	var hum: float = sim.humidity
	_hum_bar.value = hum * 100.0
	var ok: bool = hum >= sim.sp["humidity_ok_min"] and hum <= sim.sp["humidity_ok_max"]
	_show(_vals["hum"], "%d%%" % int(hum * 100), INK if ok else DANGER)
	_chart.queue_redraw()
	_refresh_enemies()
	_refresh_stars()
