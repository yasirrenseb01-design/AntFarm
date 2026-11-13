extends "res://scripts/view/ui/parts/hud_stars.gd"
## HUD, layer 5 of 7: the colony's bar on the left (clock, speed, views), the tool bar and the camera pad.


# ---------------------------------------------------------------- layout

## The colony's bar on the left, top to bottom (the keeper, 2026-11-03: "the top bar to the left, a tab to fold it - folded,
## a Post-it with the day and the season"; along the top until v0.11.77): the species and the box, the days kept, the
## time, the date and the weather, the points, the speeds, the two views, then the panels and the menu. Folded away, a
## sticky note is left in its corner (_postit), the day and the season on it: a click opens the bar again.
const Toolbox := preload("res://scripts/view/ui/toolbox.gd")
const BAR_W := 250.0
const Desk := preload("res://scripts/view/ui/desk.gd")
const DeskDial := preload("res://scripts/view/ui/desk_dial.gd")
const DeskControls := preload("res://scripts/view/ui/desk_controls.gd")

var _dial                        # ui/desk_dial.gd: the speeds
var _view_strap                  # desk_controls.ViewStrap: outworld / nest
var _serif: SystemFont           # the desk look's words (the keeper's picture: a serif, the date in italics)
var _serif_i: SystemFont


## The desk look's fonts: a serif (Georgia, Cambria), Thai from the system's fallback.
func _desk_fonts() -> void:
	if _serif != null:
		return
	_serif = SystemFont.new()
	_serif.font_names = PackedStringArray(["Georgia", "Cambria", "Leelawadee UI"])
	_serif_i = SystemFont.new()
	_serif_i.font_names = PackedStringArray(["Georgia", "Cambria", "Leelawadee UI"])
	_serif_i.font_italic = true


## A button as stitched leather / a paper tag (desk_controls.gd).
func _leather_button(b: Button) -> void:
	DeskControls.leather(b)


func _tag_button(b: Button) -> void:
	DeskControls.tag(b)


func _build_top(root: Control) -> void:
	_desk_fonts()
	var panel := PanelContainer.new()
	panel.position = Vector2(14, 22)              # (room above for the clip's ring)
	panel.custom_minimum_size.x = BAR_W
	panel.add_theme_stylebox_override("panel", Desk.ClipboardBox.new(22, 38, 18))
	root.add_child(panel)
	_top = panel
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	_top_row = col

	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", 0)
	var name_row := HBoxContainer.new()
	var name_l := _label(tr(sim.sp["name_th"]), 22, INK, _serif)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_l)
	var fold := _button("‹", false)
	_leather_button(fold)
	fold.custom_minimum_size = Vector2(28, 26)
	fold.tooltip_text = tr("bar_fold_tip")
	fold.pressed.connect(func(): set_bar_open(false))
	guide_targets["fold"] = fold
	name_row.add_child(fold)
	title.add_child(name_row)
	var sub := _label(tr("top_subtitle") % [sim.sp["name"], tr("top_plot") if sim.scenario == "wild" else tr("top_box"),
		"%d×%d" % [int(sim.WORLD.x * 0.05), int(sim.WORLD.y * 0.05)], ProjectSettings.get_setting("application/config/version", "dev") + (" · " + tr("demo_badge") if load("res://scripts/game/demo.gd").on() else "")], 12, MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = BAR_W - 48.0
	title.add_child(sub)
	call("_album_sketch", title)          # (the queen's sketch, the album's way in: hud.gd)
	col.add_child(title)
	_top_title = title

	# the year, date and season, and the weather (the days kept and the time, big here from 2026-10-28 - "show how many
	# days I have kept them" - are on the time bar along the top since v0.12.12: ui/time_bar.gd)
	var clock := VBoxContainer.new()
	clock.add_theme_constant_override("separation", 0)
	_date = _label("", 14, INK.lerp(MUTED, 0.4), _serif_i)
	_date.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weather = _label("", 13, INK.lerp(MUTED, 0.4), _serif_i)
	_weather.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clock.add_child(_date)
	clock.add_child(_weather)
	col.add_child(clock)
	# the points, in the bar (on a tab hung under the top bar until v0.11.77)
	# (on a parchment ribbon beside the honey: the keeper's picture)
	_harmony_l = _label("", 14, Color(0.45, 0.25, 0.05), _serif_i)
	_harmony_l.add_theme_stylebox_override("normal", Desk.RibbonBox.new())
	_harmony_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_harmony_row = with_harmony_icon(_harmony_l, 26)
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

	# the speeds: a brass gauge (a calm pace for watching - 0.5× is where a new game starts; longer stretches pass while
	# the game is closed); developer speeds under it (F10 shows / hides them): fast-forward for testing, not for watching
	_dial = DeskDial.new()
	_dial.labels = [tr("speed_pause"), "0.2×", "0.5×", "1×", "2×", "5×"]
	_dial.font = _serif
	_dial.value = 0.5
	guide_targets["speeds"] = _dial
	_dial.picked.connect(func(v):
		for b in _dev_speed_buttons:
			b.set_pressed_no_signal(false)
		speed_changed.emit(v))
	col.add_child(_dial)
	var dev := HBoxContainer.new()
	dev.add_theme_constant_override("separation", 4)
	var g := ButtonGroup.new()
	for pair in [["20×", 20.0], ["50×", 50.0], ["100×", 100.0]]:
		var b := _button(pair[0], true, g)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v: float = pair[1]
		b.pressed.connect(func():
			_dial.show_speed(v)
			speed_changed.emit(v))
		b.visible = false
		b.tooltip_text = tr("speed_dev")
		dev.add_child(b)
		_dev_speed_buttons.append(b)
	col.add_child(dev)

	# the two views: a leather strap, the chosen half raised
	_view_strap = DeskControls.ViewStrap.new()
	_view_strap.words = [tr("view_outworld"), tr("view_nest")]
	_view_strap.font = _serif
	guide_targets["views"] = _view_strap
	_view_strap.chosen.connect(func(m):
		_apply_mode(m)
		view_changed.emit(m))
	col.add_child(_view_strap)

	var more := GridContainer.new()
	more.columns = 2
	more.add_theme_constant_override("h_separation", 6)
	more.add_theme_constant_override("v_separation", 6)
	col.add_child(more)
	var foes := _seal(tr("enemies"), "enemy", Color(0.6, 0.12, 0.09))
	foes.tooltip_text = tr("enemies_tip")
	foes.pressed.connect(toggle_enemies)
	var stars := _seal(tr("stars"), "ant", Color(0.55, 0.14, 0.1))
	guide_targets["stars"] = stars
	stars.tooltip_text = tr("stars_tip")
	stars.pressed.connect(toggle_stars)
	var mine := _seal(tr("my_colonies"), "home", Color(0.72, 0.52, 0.16))
	mine.pressed.connect(func(): open_colonies())
	# the nest as the desktop wallpaper, behind the icons (back: the ant icon in the system tray)
	var desk := _seal(tr("wallpaper"), "picture", Color(0.27, 0.23, 0.23))
	desk.tooltip_text = tr("wallpaper_tip")
	desk.pressed.connect(func(): desktop_requested.emit())
	var menu := _seal(tr("menu"), "menu", Color(0.42, 0.25, 0.14))
	guide_targets["menu"] = menu
	menu.tooltip_text = tr("menu_tip")
	menu.pressed.connect(func(): menu_requested.emit())
	# (two to a row; My colonies - the longest words - a row of its own: the bar stays as narrow as it was)
	for b in [foes, stars, desk, menu]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		more.add_child(b)
	mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(mine)

	_postit = _make_postit()
	root.add_child(_postit)


## A paper tag with a wax seal (the colony bar's buttons).
func _seal(text: String, kind: String, wax: Color) -> Button:
	var b = DeskControls.SealButton.new(kind, wax)
	b.text = text
	b.add_theme_font_override("font", _serif_i)
	b.add_theme_font_size_override("font_size", 13)
	return b


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
	Toolbox.build(self, root)                # (the keeper's toolbox: ui/toolbox.gd, v0.13.14)
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
	panel.add_theme_stylebox_override("panel", Desk.TrayBox.new(14, 10))
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
		_tag_button(b)
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
	var lbl := _label(tr("cam_go"), 12, Color(0.95, 0.86, 0.7))
	go.add_child(lbl)
	for spec in [[tr("cam_entrance"), "nest", "outworld"], [tr("queen"), "queen", "nest"], [tr("larvae"), "larvae", "nest"],
			[tr("pupae"), "pupae", "nest"], [tr("cam_entrance"), "entrance", "nest"]]:
		var b := _button(spec[0], false)
		var a: String = spec[1]
		b.pressed.connect(func(): cam_action.emit(a))
		_tag_button(b)
		go.add_child(b)
		if spec[2] == "nest":
			_cam_nest.append(b)
		else:
			_cam_outside.append(b)


func set_cut(v: float) -> void:
	if _cut_slider:
		_cut_slider.min_value = -nest_view.cut_reach() if nest_view else -32.0    # (as wide as the nest's box)
		_cut_slider.max_value = -_cut_slider.min_value
		_cut_slider.set_value_no_signal(v)


func _apply_mode(m: String) -> void:
	var outside := m != "nest"
	if _view_strap != null:
		_view_strap.select(m)
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
