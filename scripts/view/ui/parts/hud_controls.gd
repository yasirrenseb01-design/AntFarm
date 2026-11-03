extends "res://scripts/view/ui/parts/hud_stars.gd"
## HUD, layer 5 of 7: the colony's bar on the left (clock, speed, views), the tool bar and the camera pad.


# ---------------------------------------------------------------- layout

## The colony's bar on the left, top to bottom (the keeper, 2026-11-03: "the top bar to the left, a tab to fold it - folded,
## a Post-it with the day and the season"; along the top until v0.11.77): the species and the box, the days kept, the
## time, the date and the weather, the points, the speeds, the two views, then the panels and the menu. Folded away, a
## sticky note is left in its corner (_postit), the day and the season on it: a click opens the bar again.
const BAR_W := 236.0

func _build_top(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(14, 12)
	panel.custom_minimum_size.x = BAR_W
	root.add_child(panel)
	_top = panel
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	_top_row = col

	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", 0)
	var name_row := HBoxContainer.new()
	var name_l := _label(tr(sim.sp["name_th"]), 22, INK, _display)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_l)
	var fold := _button("‹", false)
	fold.tooltip_text = tr("bar_fold_tip")
	fold.pressed.connect(func(): set_bar_open(false))
	name_row.add_child(fold)
	title.add_child(name_row)
	var sub := _label(tr("top_subtitle") % [sim.sp["name"], tr("top_plot") if sim.scenario == "wild" else tr("top_box"),
		"%d×%d" % [int(sim.WORLD.x * 0.05), int(sim.WORLD.y * 0.05)], ProjectSettings.get_setting("application/config/version", "dev")], 12, MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = BAR_W - 28.0
	title.add_child(sub)
	col.add_child(title)
	_top_title = title

	# the days since the colony began, big, and the time; the year, date and season under them (the keeper,
	# 2026-10-28: "show how many days I have kept them")
	var clock := VBoxContainer.new()
	clock.add_theme_constant_override("separation", 0)
	_clock = _label("", 20, INK, _mono)
	_date = _label("", 13, MUTED)
	_date.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weather = _label("", 12, MUTED)
	_weather.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clock.add_child(_clock)
	clock.add_child(_date)
	clock.add_child(_weather)
	col.add_child(clock)
	# the points, in the bar (on a tab hung under the top bar until v0.11.77)
	_harmony_l = _label("", 13, AMBER)
	_harmony_row = with_harmony_icon(_harmony_l, 18)
	col.add_child(_harmony_row)
	# the food warning, on paper under the bar (the keeper, 2026-10-27: sugar or protein about to run out - food_warning)
	_food_warn = _label("", 13, Color(0.75, 0.33, 0.05))
	var fsb: StyleBox = Paper.page()
	fsb.content_margin_left = 12
	fsb.content_margin_right = 12
	fsb.content_margin_top = 4
	fsb.content_margin_bottom = 5
	_food_warn.add_theme_stylebox_override("normal", fsb)
	_food_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_food_warn.custom_minimum_size.x = BAR_W
	_food_warn.visible = false
	_food_warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_food_warn)

	col.add_child(HSeparator.new())
	var speeds := GridContainer.new()
	speeds.columns = 3
	speeds.add_theme_constant_override("h_separation", 4)
	speeds.add_theme_constant_override("v_separation", 4)
	guide_targets["speeds"] = speeds
	var g := ButtonGroup.new()
	# a calm pace for watching (0.5× is where a new game starts); longer stretches pass while the game is closed
	for pair in [[tr("speed_pause"), 0.0], ["0.2×", 0.2], ["0.5×", 0.5], ["1×", 1.0], ["2×", 2.0], ["5×", 5.0]]:
		var b := _button(pair[0], true, g)
		b.button_pressed = pair[1] == 0.5
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v: float = pair[1]
		b.pressed.connect(func(): speed_changed.emit(v))
		speeds.add_child(b)
	# developer speeds (F10 shows / hides them): fast-forward for testing, not for watching
	for pair in [["20×", 20.0], ["50×", 50.0], ["100×", 100.0]]:
		var b := _button(pair[0], true, g)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v: float = pair[1]
		b.pressed.connect(func(): speed_changed.emit(v))
		b.visible = false
		b.tooltip_text = tr("speed_dev")
		speeds.add_child(b)
		_dev_speed_buttons.append(b)
	col.add_child(speeds)

	var views := HBoxContainer.new()
	guide_targets["views"] = views
	views.add_theme_constant_override("separation", 4)
	var vg := ButtonGroup.new()
	for pair in [[tr("view_outworld"), "outworld"], [tr("view_nest"), "nest"]]:
		var b := _button(pair[0], true, vg)
		b.button_pressed = pair[1] == "outworld"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_view_btns[pair[1]] = b
		var m: String = pair[1]
		b.pressed.connect(func():
			_apply_mode(m)
			view_changed.emit(m))
		views.add_child(b)
	col.add_child(views)

	col.add_child(HSeparator.new())
	var more := GridContainer.new()
	more.columns = 2
	more.add_theme_constant_override("h_separation", 4)
	more.add_theme_constant_override("v_separation", 4)
	col.add_child(more)
	var foes := _button(tr("enemies"), false)
	foes.tooltip_text = tr("enemies_tip")
	foes.pressed.connect(toggle_enemies)
	var stars := _button(tr("stars"), false)
	guide_targets["stars"] = stars
	stars.tooltip_text = tr("stars_tip")
	stars.pressed.connect(toggle_stars)
	var mine := _button(tr("my_colonies"), false)
	mine.pressed.connect(func(): open_colonies())
	# the nest as the desktop wallpaper, behind the icons (back: the ant icon in the system tray)
	var desk := _button(tr("wallpaper"), false)
	desk.tooltip_text = tr("wallpaper_tip")
	desk.pressed.connect(func(): desktop_requested.emit())
	var menu := _button(tr("menu"), false)
	guide_targets["menu"] = menu
	menu.tooltip_text = tr("menu_tip")
	menu.pressed.connect(func(): menu_requested.emit())
	for b in [foes, stars, mine, desk, menu]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		more.add_child(b)

	_postit = _make_postit()
	root.add_child(_postit)


## The folded bar: a yellow sticky note, a little askew, the day and the season pencilled on it (the keeper's sketch,
## 2026-11-03: "Day : 581 / Season : Autumn").
func _make_postit() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.position = Vector2(16, 14)
	b.rotation = deg_to_rad(-2.0)
	b.tooltip_text = tr("bar_open_tip")
	_style_postit(b)
	b.add_theme_font_size_override("font_size", 15)
	b.visible = false
	b.pressed.connect(func(): set_bar_open(true))
	return b


## A button drawn as a yellow sticky note (the folded bar; the folded side panel's tab - the keeper, 2026-11-03: dark on
## the dark scene it could hardly be seen).
func _style_postit(b: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = POSTIT
	sb.content_margin_left = 16
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(2, 3)
	sb.corner_radius_bottom_right = 10
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var s2: StyleBoxFlat = sb.duplicate()
		if st.begins_with("hover"):
			s2.bg_color = POSTIT.lightened(0.15)
		b.add_theme_stylebox_override(st, s2)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, INK)


## Opens or folds the bar (kept in the settings, "bar_open").
func set_bar_open(open: bool, keep := true) -> void:
	_top.visible = open
	_postit.visible = not open
	_refresh_postit()
	if keep:
		settings["bar_open"] = open
		settings_changed.emit(settings)
	_place_tab()


func _refresh_postit() -> void:
	if _postit != null and _postit.visible:
		_postit.text = tr("postit_text") % [sim.day(), sim.season_name()]


## Where a panel on the left goes (the enemies, the star ants, an ant's card): right of the bar, or of the note.
func left_pos() -> Vector2:
	var bar: Control = _top if _top.visible else _postit
	return Vector2(bar.position.x + bar.size.x + 12.0, 12.0)


## The food warning under the bar (or the note), and the panels on the left beside it.
func _place_tab() -> void:
	if _top == null or _postit == null:
		return
	var bar: Control = _top if _top.visible else _postit
	if _food_warn != null:
		_food_warn.position = Vector2(bar.position.x, bar.position.y + bar.size.y + 8.0)
	var at := left_pos()
	for p in [_enemies, _stars, ant_tip]:
		if p != null and is_instance_valid(p):
			p.position = at


## The numbers of the Home's tanks resting in the fridge now, if other colonies fill it ("": there is room).
func _fridge_taken() -> String:
	if home == null:
		return ""
	var nums := []
	for p in home.places():
		if int(p.slot) != current_slot and bool(Store.meta(int(p.slot)).get("fridge", false)):
			nums.append(str(p.number))
	return ", ".join(nums) if nums.size() >= Fridge.HOLDS else ""


var _food_said := ""                   # the warning shown last (the chime sounds as a new one comes up)
var _food_seen := false                # (the first look, as the colony opens: no chime - the keeper, 2026-11-03: "a
                                       # notification sound as the game loads")

func _testing() -> bool:
	return Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--selftest"))


const FOOD_WARN_DAYS := 2.0            # game days of sugar or protein left: warned (the keeper's choice, 2026-10-27)

## The keeper's colony about to run out of sugar or protein (sim.food_days: what is in the crops and stored, and the
## food still lying in the box): a note under the top bar, orange, red when it is under half a day. Not for a founding
## queen (she lives on her reserves) nor a garden plot (the ants find their own).
func food_warning() -> String:
	if sim.scenario == "wild" or sim.workers.is_empty() or sim.founding():
		return ""
	var fd: Vector2 = sim.food_days()
	var parts := []
	if fd.x < FOOD_WARN_DAYS:
		parts.append(tr("food_low_sugar") % ("%.1f" % fd.x))
	if fd.y < FOOD_WARN_DAYS:
		parts.append(tr("food_low_protein") % ("%.1f" % fd.y))
	return " · ".join(parts)


func _refresh_food_warn() -> void:
	if _food_warn == null:
		return
	var w := food_warning()
	if w != "" and _food_said == "" and _food_seen and not _testing() and not quiet:
		Chime.play(self, float(settings.get("music", 0.6)))        # (once, as it comes up: a sound made in code)
	_food_said = w
	_food_seen = true
	_food_warn.visible = w != ""
	if w != "":
		var fd: Vector2 = sim.food_days()
		_food_warn.text = "⚠ " + w
		_food_warn.add_theme_color_override("font_color", Color(0.72, 0.12, 0.08) if minf(fd.x, fd.y) < 0.5 else Color(0.75, 0.33, 0.05))
		_food_warn.reset_size()


func _build_tools(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 14
	panel.offset_top = -64
	panel.offset_bottom = -12
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	_tools_bar = panel
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var place_label := _label(tr("place_plot") if sim.scenario == "wild" else tr("place_box"), 12, MUTED)
	row.add_child(place_label)
	_outside_tools.append(place_label)
	_cut_row = HBoxContainer.new()
	_cut_row.visible = false
	_cut_row.add_child(_label(tr("cut_plane"), 12, MUTED))
	var cut := HSlider.new()
	_cut_slider = cut
	cut.min_value = -32
	cut.max_value = 32
	cut.step = 0.5
	cut.value = 0
	cut.custom_minimum_size = Vector2(220, 0)
	cut.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cut.focus_mode = Control.FOCUS_NONE
	cut.value_changed.connect(func(v): if nest_view: nest_view.cut_offset = v)
	_cut_row.add_child(cut)
	row.add_child(_cut_row)
	_xray_btn = _button(tr("xray"), true)
	_xray_btn.visible = false
	_xray_btn.toggled.connect(func(on):
		if nest_view:
			nest_view.set_xray(on)
		_cut_row.visible = not on and not sim.nest.slab)
	row.add_child(_xray_btn)
	# the nest seen through the soil from the start (the keeper, 2026-11-03: the cut face of bare soil first until v0.11.78)
	_xray_btn.button_pressed = true
	var g := ButtonGroup.new()
	for pair in [["tool_pan", "pan"]] + FoodKinds.tools() + [["tool_rock", "rock"], ["tool_rock_take", "rock_take"], ["tool_erase", "erase"]]:
		var b := _button(tr(pair[0]), true, g)
		b.button_pressed = pair[1] == ground.tool
		var t: String = pair[1]
		b.pressed.connect(func(): ground.tool = t)
		row.add_child(b)
		_outside_tools.append(b)
		if pair[1] != "pan" and not guide_targets.has("food"):
			guide_targets["food"] = b
	row.add_child(VSeparator.new())
	var water := _button(tr("add_water"), false)
	guide_targets["water"] = water
	water.pressed.connect(func():
		var before: float = sim.water
		sim.add_water()
		water_given.emit(before))
	water.visible = sim.scenario == "keeper"     # outdoors the rain waters the nest
	row.add_child(water)
	var pher := _button(tr("show_scent"), true)
	pher.button_pressed = ground.show_pheromones
	pher.toggled.connect(func(on): ground.show_pheromones = on)
	row.add_child(pher)
	_outside_tools.append(pher)
	var heat := _button(tr("heater"), true)
	heat.toggled.connect(func(on):
		sim.heater = on
		sim._log(T.heater_on if on else T.heater_off))
	heat.visible = sim.scenario == "keeper"      # outdoors there is no heat mat
	row.add_child(heat)
	var cold := _button(tr("fridge"), true)
	cold.button_pressed = sim.fridge_on
	cold.toggled.connect(func(on):
		var other := _fridge_taken() if on else ""
		if other != "":
			# the Home's fridge holds two tanks (one until v0.11.75): other colonies are resting in it
			cold.set_pressed_no_signal(false)
			call("_named_news", tr("fridge_full") % other)        # (the banner: hud.gd)
			return
		sim.fridge_on = on
		sim._log(T.fridge_in if on else T.fridge_out))
	cold.visible = sim.scenario == "keeper"      # outdoors winter comes by itself
	row.add_child(cold)
	_hint = _label("", 12, Color(1, 1, 1, 0.85))       # (over the scene, not on paper: light, with a shadow)
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("shadow_offset_x", 1)
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 18
	_hint.offset_top = -92
	root.add_child(_hint)
	_apply_mode("outworld")


## On-screen camera buttons, bottom-right of the view (left of the side panel).
func _build_camera_pad(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_right = -PANEL_W - 14
	panel.offset_bottom = -12
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	_cam_pad = panel
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	for spec in [["−", "zoom_out", "both"], ["+", "zoom_in", "both"], ["⟲", "left", "3d"], ["⟳", "right", "3d"],
			[tr("cam_top"), "top", "out"], [tr("cam_fit"), "reset", "both"]]:
		var b := _button(spec[0], false)
		b.custom_minimum_size = Vector2(34, 0)
		var a: String = spec[1]
		b.pressed.connect(func(): cam_action.emit(a))
		row.add_child(b)
		if spec[2] == "3d":
			_cam_3d.append(b)
		elif spec[2] == "out":
			_cam_out.append(b)
	var go := HBoxContainer.new()
	go.add_theme_constant_override("separation", 4)
	col.add_child(go)
	var lbl := _label(tr("cam_go"), 12, MUTED)
	go.add_child(lbl)
	for spec in [[tr("cam_entrance"), "nest", "outworld"], [tr("queen"), "queen", "nest"], [tr("larvae"), "larvae", "nest"],
			[tr("pupae"), "pupae", "nest"], [tr("cam_entrance"), "entrance", "nest"]]:
		var b := _button(spec[0], false)
		var a: String = spec[1]
		b.pressed.connect(func(): cam_action.emit(a))
		go.add_child(b)
		if spec[2] == "nest":
			_cam_nest.append(b)
		else:
			_cam_outside.append(b)


func set_cut(v: float) -> void:
	if _cut_slider:
		_cut_slider.set_value_no_signal(v)


func _apply_mode(m: String) -> void:
	var outside := m != "nest"
	if _view_btns.has(m):
		_view_btns[m].button_pressed = true
	for c in _cam_nest:
		c.visible = m == "nest"
	for c in _cam_outside:
		c.visible = outside
	for c in _cam_out:
		c.visible = m == "outworld"
	for c in _outside_tools:
		c.visible = outside
	_cut_row.visible = m == "nest" and not sim.nest.slab and not _xray_btn.button_pressed
	_xray_btn.visible = m == "nest"
	_hint.text = (tr("hint_nest")
		if m == "nest" else tr("hint_outworld"))
