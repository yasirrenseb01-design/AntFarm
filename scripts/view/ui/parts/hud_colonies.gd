extends "res://scripts/view/ui/parts/hud_base.gd"
## HUD, layer 2 of 7: the "my colonies" window (save slots), the settings window and report dialogs.


## "My colonies": the save slots (play one, start a new colony in one) and what happens to time
## while the game is closed.
func _build_colonies(root: Control) -> void:
	_colonies = Window.new()
	_colonies.title = tr("my_colonies")
	_colonies.theme = _paper_theme
	_colonies.transient = true
	_colonies.exclusive = true
	_colonies.unresizable = true
	_colonies.wrap_controls = true
	_colonies.visible = false
	_colonies.close_requested.connect(_colonies.hide)
	root.add_child(_colonies)
	_colonies_body = PanelContainer.new()
	_colonies_body.add_theme_stylebox_override("panel", Paper.page())
	_colonies_body.set_anchors_preset(Control.PRESET_FULL_RECT)          # (the paper fills the window: no dark strip under it)
	_colonies.add_child(_colonies_body)
	_settings_win = Window.new()
	_settings_win.title = tr("settings")
	_settings_win.theme = _paper_theme
	_settings_win.transient = true
	_settings_win.exclusive = true
	_settings_win.unresizable = true
	_settings_win.wrap_controls = true
	_settings_win.visible = false
	_settings_win.close_requested.connect(_settings_win.hide)
	root.add_child(_settings_win)
	_report = AcceptDialog.new()
	_report.theme = _paper_theme
	_report.ok_button_text = tr("report_ok")
	root.add_child(_report)


## The colonies of one kind (scen: "wild" - the wild mode's - or "keeper" - the Home's tanks; "": the kind being played).
func open_colonies(scen := "") -> void:
	if scen == "":
		scen = "wild" if sim.scenario == "wild" else "keeper"
	_colonies.title = tr("wild_colonies") if scen == "wild" else tr("tank_colonies")
	for c in _colonies_body.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(560, 0)
	_colonies_body.add_child(col)
	for s in slots_of(scen):
		var m: Dictionary = Store.meta(s)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label(tr("col_slot") % [slot_no(s), tr("col_playing") if s == current_slot else ""], 15, Paper.ACCENT if s == current_slot else Paper.INK))
		var desc := tr("col_empty")
		if not m.is_empty():
			var when := Time.get_datetime_string_from_unix_time(int(m.get("saved_unix", 0)) + _tz_offset(), true)
			desc = tr("col_desc") % [
				tr("col_wild") if m.get("scenario", "keeper") == "wild" else tr("col_keeper"), m.get("day", 1), m.get("workers", 0),
				tr("nest_glass") if m.get("glass", false) else tr("nest_soil"),
				"" if m.get("queen", true) else tr("title_queen_dead"), when.replace("T", " ").left(16)]
		info.add_child(_label(desc, 12, Paper.PENCIL))
		row.add_child(info)
		if not m.is_empty() and s != current_slot:
			var play := _button(tr("col_play"), false)
			var slot_n: int = s
			play.pressed.connect(func():
				_colonies.hide()
				colony_play.emit(slot_n))
			row.add_child(play)
		var fresh := _button(tr("col_restart"), false)
		var slot_k: int = s
		var occupied: bool = not m.is_empty()
		fresh.pressed.connect(func():
			_colonies.hide()
			open_species(slot_k, occupied, scen))
		row.add_child(fresh)
		col.add_child(row)
	col.add_child(HSeparator.new())
	var foot := HBoxContainer.new()
	var note := _label(tr("col_note"), 12, Paper.PENCIL)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(note)
	var save_now := _button(tr("col_save_now"), false)
	save_now.pressed.connect(func():
		save_requested.emit()
		save_now.text = tr("col_saved"))
	foot.add_child(save_now)
	col.add_child(foot)
	_colonies.reset_size()
	_colonies.popup_centered()


## The save slots of the wild mode ("wild") or of the Home's tanks (anything else), from home.json (main sets home).
func slots_of(scen: String) -> Array:
	if home == null:
		return [1, 2, 3]
	return home.wild if scen == "wild" else home.tanks


## What the keeper calls a slot: its place among the tanks or among the wild mode's colonies (1, 2...).
func slot_no(slot: int) -> int:
	if home == null:
		return slot
	return (home.wild.find(slot) if home.wild.has(slot) else home.tanks.find(slot)) + 1


## A new colony, step 1: which ant (view/ui/species_window.gd), then where and how it starts (_open_new_colony).
func open_species(slot: int, occupied: bool, scen := "") -> Window:
	var w := SpeciesWindow.new()
	_colonies.get_parent().add_child(w)
	w.setup(self)
	w.chosen.connect(func(_id): _open_new_colony(slot, occupied, scen))
	w.reset_size()
	w.popup_centered()
	return w


## Settings (from the title screen): time while the game is closed, the helper, music, the frame rate.
func open_settings() -> void:
	for c in _settings_win.get_children():
		c.queue_free()
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", Paper.page())
	body.set_anchors_preset(Control.PRESET_FULL_RECT)          # (the paper fills the window: no dark strip under it)
	_settings_win.add_child(body)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(520, 0)
	body.add_child(col)
	# the language first (each named in its own words, so it can be found in a language one cannot read)
	var lang_row := HBoxContainer.new()
	lang_row.add_child(_label(tr("set_language"), 13, Paper.PENCIL))
	var langs := OptionButton.new()
	langs.focus_mode = Control.FOCUS_NONE
	for i in L.LANGS.size():
		langs.add_item(L.LANGS[i][1], i)
		if L.LANGS[i][0] == L.current():
			langs.select(i)
	langs.item_selected.connect(func(i):
		if L.LANGS[i][0] != L.current():
			language_changed.emit(L.LANGS[i][0]))
	langs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_row.add_child(langs)
	col.add_child(lang_row)
	var away := HBoxContainer.new()
	away.add_child(_label(tr("set_away"), 13, Paper.PENCIL))
	var opt := OptionButton.new()
	opt.focus_mode = Control.FOCUS_NONE
	for i in Store.AWAY_RATES.size():
		opt.add_item(tr(Store.AWAY_RATES[i][0]), i)
	opt.select(int(settings.get("away", 3)))
	opt.item_selected.connect(func(i):
		settings["away"] = i
		settings_changed.emit(settings))
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	away.add_child(opt)
	col.add_child(away)
	# (two clocks: the colony's, cut short, and the ants' own pace - said here once, the time away being the one that differs)
	var clocks := _label(tr("set_time_1") + " " +
		tr("set_time_2"), 12, Paper.PENCIL)
	clocks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clocks.custom_minimum_size.x = 500
	col.add_child(clocks)
	var care := CheckBox.new()
	care.text = tr("set_care")
	care.button_pressed = settings.get("care", true)
	care.toggled.connect(func(on):
		settings["care"] = on
		settings_changed.emit(settings))
	col.add_child(care)
	var tune := HBoxContainer.new()
	tune.add_child(_label(tr("set_music"), 13, Paper.PENCIL))
	var vol := HSlider.new()
	vol.focus_mode = Control.FOCUS_NONE
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = float(settings.get("music", 0.6))
	vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vol_txt := _label(tr("off") if vol.value <= 0.0 else "%d%%" % roundi(vol.value * 100), 13, Paper.INK)
	vol_txt.custom_minimum_size.x = 44
	vol.value_changed.connect(func(v):
		settings["music"] = v
		vol_txt.text = tr("off") if v <= 0.0 else "%d%%" % roundi(v * 100)
		if music != null:
			music.volume = v
		settings_changed.emit(settings))
	tune.add_child(vol)
	tune.add_child(vol_txt)
	col.add_child(tune)
	var fps := CheckBox.new()
	fps.text = tr("set_fps")
	fps.button_pressed = bool(settings.get("show_fps", false))
	fps.toggled.connect(func(on):
		settings["show_fps"] = on
		if _fps_label != null:
			_fps_label.visible = on
		settings_changed.emit(settings))
	col.add_child(fps)
	# graphics quality and the frame-rate cap (game/graphics.gd; main applies them as the settings change)
	var gfx := HBoxContainer.new()
	gfx.add_theme_constant_override("separation", 8)
	gfx.add_child(_label(tr("set_quality"), 13, Paper.PENCIL))
	var q := OptionButton.new()
	q.focus_mode = Control.FOCUS_NONE
	for k in ["quality_low", "quality_medium", "quality_high"]:
		q.add_item(tr(k))
	q.select(maxi(0, ["low", "medium", "high"].find(String(settings.get("quality", "medium")))))
	q.item_selected.connect(func(i):
		settings["quality"] = ["low", "medium", "high"][i]
		settings_changed.emit(settings))
	gfx.add_child(q)
	gfx.add_child(_label(tr("set_fps_cap"), 13, Paper.PENCIL))
	var f := OptionButton.new()
	f.focus_mode = Control.FOCUS_NONE
	for k in ["fps_30", "fps_60", "fps_free"]:
		f.add_item(tr(k))
	f.select(clampi(int(settings.get("fps_cap", 1)), 0, 2))
	f.item_selected.connect(func(i):
		settings["fps_cap"] = i
		settings_changed.emit(settings))
	gfx.add_child(f)
	col.add_child(gfx)
	col.add_child(_label(tr("set_quality_note"), 12, Paper.PENCIL))
	var again_row := HBoxContainer.new()
	again_row.add_theme_constant_override("separation", 10)
	var again := _button(tr("settings_guide"), false)
	var again_note := _label("", 12, Paper.PENCIL)
	again.pressed.connect(func():
		settings["guide_done"] = false              # (main / title.close start it once the game is on screen)
		settings_changed.emit(settings)
		again_note.text = tr("settings_guide_note"))
	again_row.add_child(again)
	again_row.add_child(again_note)
	col.add_child(again_row)
	col.add_child(_label(tr("set_note") % int(Store.MAX_AWAY_DAYS), 12, Paper.PENCIL))
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	var done := _button(tr("done"), false)
	done.pressed.connect(_settings_win.hide)
	foot.add_child(done)
	col.add_child(foot)
	_settings_win.reset_size()
	_settings_win.popup_centered()


## A slider for how often natural enemies come (sim.enemy_rate: 0 - 300% of the usual), saying about how many days apart
## that is - in the new-colony window and the enemy panel.
class EnemyRate extends VBoxContainer:
	signal changed(rate: float)
	var _hud
	var _slider: HSlider
	var _text: Label
	var _scen := "wild"

	var _ink: Color
	var _pencil: Color

	func _init(hud, rate: float, scen: String, paper := false) -> void:
		_hud = hud
		_ink = hud.Paper.INK if paper else hud.INK
		_pencil = hud.Paper.PENCIL if paper else hud.MUTED
		add_theme_constant_override("separation", 2)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(hud._label(tr("none"), 12, _pencil))
		_slider = HSlider.new()
		_slider.min_value = 0.0
		_slider.max_value = 3.0
		_slider.step = 0.25
		_slider.focus_mode = Control.FOCUS_NONE
		_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_slider)
		row.add_child(hud._label(tr("rate_very_often"), 12, _pencil))
		add_child(row)
		_text = hud._label("", 12, _ink)
		_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_text.custom_minimum_size.x = 300
		add_child(_text)
		set_rate(rate, scen)
		_slider.value_changed.connect(func(v):
			_show()
			changed.emit(v))

	## Shows a rate without telling anyone (a new scene's usual, or the colony's own).
	func set_rate(rate: float, scen: String) -> void:
		_scen = scen
		_slider.set_value_no_signal(rate)
		_show()

	func _show() -> void:
		var v := _slider.value
		if v <= 0.0:
			_text.text = tr("rate_none")
			return
		var days: float = _hud.sim.enemy_days(v)
		var when := (tr("rate_per_day") % (1.0 / days)) if days < 1.0 else tr("rate_every") % ("%.1f" % days if days < 3.0 else str(roundi(days)))
		var level := tr("rate_low") if v < 0.75 else (tr("rate_natural") if v <= 1.25 else (tr("rate_often") if v <= 2.0 else tr("rate_very_often")))
		_text.text = "%d%% (%s) · %s%s" % [roundi(v * 100.0), level, when,
			tr("rate_seasons") if _scen == "wild" else tr("rate_all_year")]


## Choices for a new colony: where it lives, what it lives in, and how it starts (words: keys of lang/strings.csv).
const NEW_SCENARIOS := [
	["wild", "scen_wild", "scen_wild_note"],
	["keeper", "scen_keeper", "scen_keeper_note"]]
const NEW_NESTS := [["soil", "nest_soil", "nest_soil_note"], ["glass", "nest_glass", "nest_glass_note"]]
const NEW_STARTS := [["queen", "start_queen", "start_queen_note"],
	["young", "start_young", "start_young_note"]]


## The new-colony window: pick a scenario, a nest and a start, then start it in this slot (scen: the scenario fixed -
## a tank is a formicarium, the wild mode a garden plot; "": the keeper picks).
func _open_new_colony(slot: int, occupied: bool, scen := "") -> void:
	var win := Window.new()
	win.title = (tr("new_title_wild") if scen == "wild" else tr("new_title_tank")) % slot_no(slot) if scen != "" else tr("new_title") % slot
	win.theme = _colonies.theme
	win.transient = true
	win.exclusive = true
	win.unresizable = true
	win.wrap_controls = true
	win.close_requested.connect(win.queue_free)
	_colonies.get_parent().add_child(win)
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", Paper.page())
	body.set_anchors_preset(Control.PRESET_FULL_RECT)          # (the paper fills the window: no dark strip under it)
	win.add_child(body)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(540, 0)
	body.add_child(col)
	var picked := {}
	var rates := EnemyRate.new(self, 0.0 if scen == "keeper" else 1.0, "keeper" if scen == "keeper" else "wild", true)
	var groups: Array = [["nest", "new_nest", NEW_NESTS], ["start", "new_start", NEW_STARTS]]
	if scen == "":
		groups.push_front(["scenario", "new_scene", NEW_SCENARIOS])
	else:
		picked["scenario"] = scen
	for group in groups:
		var key: String = group[0]
		var opts: Array = group[2]
		col.add_child(_label(tr(group[1]), 15, Paper.ACCENT))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		var note := _label(tr(opts[0][2]), 12, Paper.PENCIL)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(540, 0)
		var bg := ButtonGroup.new()
		picked[key] = opts[0][0]
		for o in opts:
			var b := _button(tr(o[1]), true)
			b.button_group = bg
			b.button_pressed = o == opts[0]
			b.pressed.connect(func():
				picked[key] = o[0]
				note.text = tr(o[2])
				if key == "scenario":
					if not picked.has("rate_set"):
						picked["rate"] = 1.0 if o[0] == "wild" else 0.0       # (each scene's usual, until the keeper picks one;
					rates.set_rate(picked.rate, o[0]))                      # it showed 0% for the formicarium and sent 100%)
			row.add_child(b)
		col.add_child(note)
	col.add_child(_label(tr("new_enemies"), 15, Paper.ACCENT))
	picked["rate"] = 0.0 if scen == "keeper" else 1.0
	rates.changed.connect(func(v):
		picked["rate"] = v
		picked["rate_set"] = true)
	col.add_child(rates)
	col.add_child(HSeparator.new())
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 10)
	if occupied:
		var warn := _label(tr("new_overwrite"), 12, Paper.DANGER)
		warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(warn)
	var cancel := _button(tr("cancel"), false)
	cancel.pressed.connect(win.queue_free)
	foot.add_child(cancel)
	var go := _button(tr("new_go"), false)
	go.pressed.connect(func():
		win.queue_free()
		colony_new.emit(slot, "%s:%s:%s:%s" % [picked.nest, picked.start, picked.scenario, picked.rate]))
	foot.add_child(go)
	col.add_child(foot)
	win.reset_size()
	win.popup_centered()


## Asks before doing something (a dialog with the keeper's own OK and tr("cancel")).
func confirm(title: String, text: String, ok_text: String, on_ok: Callable) -> void:
	var d := ConfirmationDialog.new()
	d.theme = _report.theme
	d.title = title
	d.dialog_text = text
	d.ok_button_text = ok_text
	d.cancel_button_text = tr("cancel")
	d.confirmed.connect(on_ok)
	d.visibility_changed.connect(func():
		if not d.visible:
			d.queue_free())
	_report.get_parent().add_child(d)
	d.popup_centered(Vector2i(560, 0))


func show_report(title: String, text: String) -> void:
	_report.title = title
	_report.dialog_text = text
	_report.popup_centered(Vector2i(520, 0))
