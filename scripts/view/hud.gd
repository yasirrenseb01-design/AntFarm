extends CanvasLayer
## Keeper's instrument panel: clock and speed on top, tools at the bottom, colony readout,
## nest cross-section, population chart and journal on the right.

const Ant := preload("res://scripts/sim/ant.gd")
const Kit := preload("res://scripts/view/draw_kit.gd")
const Store := preload("res://scripts/save_store.gd")

signal speed_changed(speed: float)
signal view_changed(mode: String)
signal colony_new(slot: int, nest_kind: String)
signal colony_play(slot: int)
signal settings_changed(settings: Dictionary)
signal save_requested
signal cam_action(action: String)

const PANEL_W := 352.0
const INK := Color("f1e6d6")
const MUTED := Color("b09a83")
const AMBER := Color("e9a23b")
const LEAF := Color("9cc565")
const DANGER := Color("e8664f")
const BG := Color(0.1, 0.075, 0.055, 0.92)
const LINE := Color(0.3, 0.22, 0.16)

var sim
var world
var _vals := {}
var _log: RichTextLabel
var _hum_bar: ProgressBar
var _nest: Control
var _chart: Control
var _clock: Label
var _weather: Label
var _mono: SystemFont
var _display: SystemFont
var _t := 0.0
var _frame := 0
var current_slot := 1
var settings := {}
var _colonies: Window
var _colonies_body: PanelContainer
var _confirm: ConfirmationDialog
var _report: AcceptDialog
var _pending := [1, "soil:queen"]
var _proj_tex: ImageTexture
var _proj_air := -1
var _spots_t := -10.0
var _crop := Rect2i(0, 0, 1, 1)
var nest_view
var _surface_tools: Array = []
var _cut_row: HBoxContainer
var _xray_btn: Button
var _cut_slider: HSlider
var _cam_surface: Array = []
var _cam_nest: Array = []
var _hint: Label
var _log_dirty := true
var _view_btns := {}
var _cam_3d: Array = []          # rotate buttons: both 3D views
var _cam_out: Array = []


func setup(s, w) -> void:
	sim = s
	world = w
	sim.logged.connect(func(_e): _log_dirty = true)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_top(root)
	_build_tools(root)
	_build_panel(root)
	_build_camera_pad(root)
	_build_colonies(root)
	_apply_mode("surface")
	refresh(1.0)


# ---------------------------------------------------------------- theme

func _box(bg: Color, border: Color, radius: int, pad_h: int, pad_v: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.anti_aliasing = true
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	var body := SystemFont.new()
	body.font_names = PackedStringArray(["Leelawadee UI", "Segoe UI", "Tahoma"])
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Leelawadee UI"])
	_display = SystemFont.new()
	_display.font_names = PackedStringArray(["Bahnschrift", "Leelawadee UI"])
	_display.font_weight = 600
	th.default_font = body
	th.default_font_size = 14
	th.set_stylebox("panel", "PanelContainer", _box(BG, LINE, 10, 14, 12))
	# dialogs (time-away report, confirmations) in the same dark keeper's-panel look
	for cls in ["AcceptDialog", "ConfirmationDialog", "PopupPanel"]:
		th.set_stylebox("panel", cls, _box(Color(0.1, 0.075, 0.055, 0.98), LINE, 10, 16, 14))
	th.set_stylebox("embedded_border", "Window", _box(Color(0.14, 0.1, 0.075), LINE, 10, 10, 32))
	th.set_color("title_color", "Window", INK)
	th.set_font("title_font", "Window", body)
	th.set_stylebox("normal", "OptionButton", _box(Color(0.17, 0.13, 0.1), LINE, 6, 10, 5))
	th.set_stylebox("normal", "MenuButton", _box(Color(0.17, 0.13, 0.1), LINE, 6, 10, 5))
	th.set_color("font_color", "MenuButton", INK)
	th.set_color("font_color", "CheckBox", INK)
	for st in ["normal", "pressed", "hover", "hover_pressed", "focus"]:
		th.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	th.set_color("font_pressed_color", "CheckBox", INK)
	th.set_color("font_hover_pressed_color", "CheckBox", INK)
	th.set_stylebox("normal", "Button", _box(Color(0.17, 0.13, 0.1), LINE, 6, 10, 5))
	th.set_stylebox("hover", "Button", _box(Color(0.22, 0.17, 0.12), MUTED, 6, 10, 5))
	th.set_stylebox("pressed", "Button", _box(AMBER, AMBER, 6, 10, 5))
	th.set_stylebox("hover_pressed", "Button", _box(AMBER.lightened(0.1), AMBER, 6, 10, 5))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", INK)
	th.set_color("font_hover_color", "Button", INK)
	th.set_color("font_pressed_color", "Button", Color("1d140b"))
	th.set_color("font_hover_pressed_color", "Button", Color("1d140b"))
	th.set_color("font_color", "Label", INK)
	th.set_stylebox("background", "ProgressBar", _box(Color(0.06, 0.045, 0.035), LINE, 4, 0, 0))
	th.set_stylebox("fill", "ProgressBar", _box(Color("5d9bd6"), Color("5d9bd6"), 4, 0, 0))
	th.set_constant("separation", "HBoxContainer", 8)
	th.set_constant("separation", "VBoxContainer", 8)
	return th


func _label(text: String, size := 14, color := INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l


func _button(text: String, toggle: bool, group: ButtonGroup = null) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	return b


# ---------------------------------------------------------------- layout

func _build_top(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(14, 12)
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)

	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", 0)
	title.add_child(_label(sim.sp["name_th"], 22, INK, _display))
	title.add_child(_label("%s · รังเดี่ยว ราชินี 1 ตัว · กล่อง 60×37 ซม. · v%s" % [sim.sp["name"], ProjectSettings.get_setting("application/config/version", "dev")], 12, MUTED))
	row.add_child(title)

	var clock := VBoxContainer.new()
	clock.add_theme_constant_override("separation", 0)
	_clock = _label("", 20, INK, _mono)
	_weather = _label("", 12, MUTED)
	clock.add_child(_clock)
	clock.add_child(_weather)
	row.add_child(clock)

	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 4)
	speeds.alignment = BoxContainer.ALIGNMENT_CENTER
	var g := ButtonGroup.new()
	for pair in [["หยุด", 0.0], ["0.5×", 0.5], ["1×", 1.0], ["5×", 5.0], ["20×", 20.0], ["60×", 60.0]]:
		var b := _button(pair[0], true, g)
		b.button_pressed = pair[1] == 1.0
		var v: float = pair[1]
		b.pressed.connect(func(): speed_changed.emit(v))
		speeds.add_child(b)
	var wrap := CenterContainer.new()
	wrap.add_child(speeds)
	row.add_child(wrap)

	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 4)
	var vg := ButtonGroup.new()
	for pair in [["พื้นดิน 3 มิติ", "outworld"], ["มุมบน 2 มิติ", "surface"], ["ในรัง 3 มิติ", "nest"]]:
		var b := _button(pair[0], true, vg)
		b.button_pressed = pair[1] == "outworld"
		_view_btns[pair[1]] = b
		var m: String = pair[1]
		b.pressed.connect(func():
			_apply_mode(m)
			view_changed.emit(m))
		views.add_child(b)
	var vwrap := CenterContainer.new()
	vwrap.add_child(views)
	row.add_child(vwrap)

	var mine := _button("รังของฉัน", false)
	mine.pressed.connect(open_colonies)
	var fwrap := CenterContainer.new()
	fwrap.add_child(mine)
	row.add_child(fwrap)


func _build_tools(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 14
	panel.offset_top = -64
	panel.offset_bottom = -12
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var place_label := _label("วางในกล่อง", 12, MUTED)
	row.add_child(place_label)
	_surface_tools.append(place_label)
	_cut_row = HBoxContainer.new()
	_cut_row.visible = false
	_cut_row.add_child(_label("ระนาบตัด", 12, MUTED))
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
	_xray_btn = _button("มองทะลุดิน", true)
	_xray_btn.visible = false
	_xray_btn.toggled.connect(func(on):
		if nest_view:
			nest_view.set_xray(on)
		_cut_row.visible = not on and not sim.nest.slab)
	row.add_child(_xray_btn)
	var g := ButtonGroup.new()
	for pair in [["มือ (เลื่อนจอ)", "pan"], ["หยดน้ำผึ้ง", "honey"], ["จิ้งหรีดตาย", "cricket"], ["ก้อนหิน", "rock"], ["ลบกลิ่น", "erase"]]:
		var b := _button(pair[0], true, g)
		b.button_pressed = pair[1] == world.tool
		var t: String = pair[1]
		b.pressed.connect(func(): world.tool = t)
		row.add_child(b)
		_surface_tools.append(b)
	row.add_child(VSeparator.new())
	var water := _button("เติมน้ำในรัง", false)
	water.pressed.connect(func(): sim.add_water())
	row.add_child(water)
	var pher := _button("แสดงกลิ่น", true)
	pher.button_pressed = world.show_pheromones
	pher.toggled.connect(func(on): world.show_pheromones = on)
	row.add_child(pher)
	_surface_tools.append(pher)
	var heat := _button("แผ่นความร้อน", true)
	heat.toggled.connect(func(on):
		sim.heater = on
		sim._log("เปิดแผ่นความร้อนใต้รัง อุณหภูมิในรังจะค่อยๆ สูงขึ้น" if on else "ปิดแผ่นความร้อน"))
	row.add_child(heat)
	var enemy := _button("ศัตรูธรรมชาติ", true)
	enemy.button_pressed = sim.enemies
	enemy.toggled.connect(func(on):
		sim.enemies = on
		if not on:
			sim.remove_spider())
	row.add_child(enemy)
	_surface_tools.append(enemy)
	_hint = _label("", 12, MUTED)
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 18
	_hint.offset_top = -92
	root.add_child(_hint)
	_apply_mode("surface")


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
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	for spec in [["−", "zoom_out", "both"], ["+", "zoom_in", "both"], ["⟲", "left", "3d"], ["⟳", "right", "3d"],
			["มุมบน", "top", "out"], ["เต็มจอ", "reset", "both"]]:
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
	var lbl := _label("ไปที่", 12, MUTED)
	go.add_child(lbl)
	for spec in [["ปากรัง", "nest", "surface"], ["ราชินี", "queen", "nest"], ["ตัวอ่อน", "larvae", "nest"],
			["ดักแด้", "pupae", "nest"], ["ปากรัง", "entrance", "nest"]]:
		var b := _button(spec[0], false)
		var a: String = spec[1]
		b.pressed.connect(func(): cam_action.emit(a))
		go.add_child(b)
		if spec[2] == "nest":
			_cam_nest.append(b)
		else:
			_cam_surface.append(b)


## "My colonies": the save slots (play one, start a new colony in one) and what happens to time
## while the game is closed.
func _build_colonies(root: Control) -> void:
	_colonies = Window.new()
	_colonies.title = "รังของฉัน"
	_colonies.theme = root.theme
	_colonies.transient = true
	_colonies.exclusive = true
	_colonies.unresizable = true
	_colonies.wrap_controls = true
	_colonies.visible = false
	_colonies.close_requested.connect(_colonies.hide)
	root.add_child(_colonies)
	_colonies_body = PanelContainer.new()
	_colonies_body.add_theme_stylebox_override("panel", _box(Color(0.1, 0.075, 0.055, 0.98), LINE, 0, 16, 14))
	_colonies.add_child(_colonies_body)
	_confirm = ConfirmationDialog.new()
	_confirm.theme = root.theme
	_confirm.title = "เริ่มรังใหม่"
	_confirm.ok_button_text = "เริ่มใหม่"
	_confirm.cancel_button_text = "ยกเลิก"
	_confirm.confirmed.connect(func(): colony_new.emit(_pending[0], _pending[1]))
	root.add_child(_confirm)
	_report = AcceptDialog.new()
	_report.theme = root.theme
	_report.ok_button_text = "ดูรัง"
	root.add_child(_report)


func open_colonies() -> void:
	for c in _colonies_body.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(560, 0)
	_colonies_body.add_child(col)
	var kinds := [["ราชินีตัวเดียว · ก้อนดิน (เริ่มแบบธรรมชาติ)", "soil:queen"], ["ราชินีตัวเดียว · ตู้แอนท์ฟาร์ม", "glass:queen"],
		["รังอายุ 3 เดือน (14 ตัว) · ก้อนดิน", "soil:young"], ["รังอายุ 3 เดือน (14 ตัว) · ตู้แอนท์ฟาร์ม", "glass:young"]]
	for s in range(1, Store.SLOTS + 1):
		var m: Dictionary = Store.meta(s)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label("รัง %d%s" % [s, "  · กำลังเล่น" if s == current_slot else ""], 15, AMBER if s == current_slot else INK))
		var desc := "ว่าง"
		if not m.is_empty():
			var when := Time.get_datetime_string_from_unix_time(int(m.get("saved_unix", 0)) + _tz_offset(), true)
			desc = "วันที่ %d · มดงาน %d · %s%s · บันทึก %s" % [m.get("day", 1), m.get("workers", 0),
				"ตู้แอนท์ฟาร์ม" if m.get("glass", false) else "ก้อนดิน",
				"" if m.get("queen", true) else " · ราชินีตายแล้ว", when.replace("T", " ").left(16)]
		info.add_child(_label(desc, 12, MUTED))
		row.add_child(info)
		if not m.is_empty() and s != current_slot:
			var play := _button("เล่นรังนี้", false)
			var slot_n: int = s
			play.pressed.connect(func():
				_colonies.hide()
				colony_play.emit(slot_n))
			row.add_child(play)
		var fresh := MenuButton.new()
		fresh.text = "เริ่มใหม่ ▾"
		fresh.flat = false
		fresh.focus_mode = Control.FOCUS_NONE
		var pm := fresh.get_popup()
		for i in kinds.size():
			pm.add_item(kinds[i][0], i)
		var slot_k: int = s
		var occupied: bool = not m.is_empty()
		pm.id_pressed.connect(func(id):
			_colonies.hide()
			_pending = [slot_k, kinds[id][1]]
			if occupied:
				_confirm.dialog_text = "รัง %d ที่มีอยู่จะถูกลบและเริ่มใหม่เป็น\n%s\n\nแน่ใจไหม?" % [slot_k, kinds[id][0]]
				_confirm.popup_centered()
			else:
				colony_new.emit(slot_k, kinds[id][1]))
		row.add_child(fresh)
		col.add_child(row)
	col.add_child(HSeparator.new())
	var away := HBoxContainer.new()
	away.add_child(_label("ตอนปิดเกม", 13, MUTED))
	var opt := OptionButton.new()
	opt.focus_mode = Control.FOCUS_NONE
	for i in Store.AWAY_RATES.size():
		opt.add_item(Store.AWAY_RATES[i][0], i)
	opt.select(int(settings.get("away", 3)))
	opt.item_selected.connect(func(i):
		settings["away"] = i
		settings_changed.emit(settings))
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	away.add_child(opt)
	col.add_child(away)
	var care := CheckBox.new()
	care.text = "ผู้ช่วยเติมน้ำและให้อาหารตอนที่ไม่อยู่"
	care.button_pressed = settings.get("care", true)
	care.toggled.connect(func(on):
		settings["care"] = on
		settings_changed.emit(settings))
	col.add_child(care)
	var foot := HBoxContainer.new()
	var note := _label("เซฟอัตโนมัติทุก 1 นาทีและตอนปิดเกม · จำลองช่วงที่ปิดเกมได้สูงสุด %d วันในเกม" % int(Store.MAX_AWAY_DAYS), 12, MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(note)
	var save_now := _button("เซฟตอนนี้", false)
	save_now.pressed.connect(func():
		save_requested.emit()
		save_now.text = "เซฟแล้ว")
	foot.add_child(save_now)
	col.add_child(foot)
	_colonies.reset_size()
	_colonies.popup_centered()


func show_report(title: String, text: String) -> void:
	_report.title = title
	_report.dialog_text = text
	_report.popup_centered(Vector2i(520, 0))


func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func set_cut(v: float) -> void:
	if _cut_slider:
		_cut_slider.set_value_no_signal(v)


func _apply_mode(m: String) -> void:
	var outside := m != "nest"
	if _view_btns.has(m):
		_view_btns[m].button_pressed = true
	for c in _cam_nest:
		c.visible = m == "nest"
	for c in _cam_surface:
		c.visible = outside
	for c in _cam_3d:
		c.visible = m != "surface"
	for c in _cam_out:
		c.visible = m == "outworld"
	for c in _surface_tools:
		c.visible = outside
	_cut_row.visible = m == "nest" and not sim.nest.slab and not _xray_btn.button_pressed
	_xray_btn.visible = m == "nest"
	_hint.text = ("ลากซ้าย หมุน · ลากขวา เลื่อน · ล้อเมาส์ ซูม · ดับเบิลคลิก ไปที่ห้องนั้น · WASD เลื่อน · Q/E หมุน · R/F เอียง"
		if m == "nest" else "ลากซ้าย (มือ) หมุน · ลากขวา เลื่อน · ล้อเมาส์ ซูมตรงจุดที่ชี้ · ดับเบิลคลิก ซูมเข้า · WASD เลื่อน · Q/E หมุน · R/F เอียง"
		if m == "outworld" else "ลากซ้าย (มือ) หรือลากขวา เลื่อน · ล้อเมาส์ ซูมตรงจุดที่ชี้ · ดับเบิลคลิก ซูมเข้า · WASD เลื่อน · +/− ซูม")


func _section(parent: Control, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_label(title.to_upper(), 12, MUTED, _display))
	parent.add_child(box)
	return box


func _build_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_W
	panel.offset_right = -12
	panel.offset_top = 12
	panel.offset_bottom = -12
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var st := _section(col, "สถานะรัง")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	st.add_child(grid)
	for key in ["queen", "workers", "out", "nurses", "callow", "eggs", "larvae", "pupae", "sugar", "protein",
			"nest_t", "dev", "dead", "cycle", "vol", "depth", "size"]:
		var names := {"queen": "ราชินี", "workers": "มดงาน", "out": "นอกรัง", "nurses": "พี่เลี้ยง",
			"callow": "ตัวใหม่", "eggs": "ไข่", "larvae": "ตัวอ่อน", "pupae": "ดักแด้", "sugar": "น้ำตาล",
			"protein": "โปรตีน", "nest_t": "ในรัง", "dev": "พัฒนาการ", "dead": "ตาย", "cycle": "ไข่→มดงาน",
			"vol": "ปริมาตรรัง", "depth": "ลึก", "size": "ขนาดมดงาน"}
		var l := _label(names[key], 13, MUTED)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := _label("-", 13, INK, _mono)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size.x = 64
		grid.add_child(l)
		grid.add_child(v)
		_vals[key] = v
	var hum_row := HBoxContainer.new()
	hum_row.add_child(_label("ความชื้นในรัง", 13, MUTED))
	_hum_bar = ProgressBar.new()
	_hum_bar.min_value = 0
	_hum_bar.max_value = 100
	_hum_bar.show_percentage = false
	_hum_bar.custom_minimum_size = Vector2(0, 10)
	_hum_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hum_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hum_row.add_child(_hum_bar)
	var hv := _label("-", 13, INK, _mono)
	hv.custom_minimum_size.x = 44
	hv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_vals["hum"] = hv
	hum_row.add_child(hv)
	st.add_child(hum_row)

	var ns := _section(col, "ภาพตัดขวางรัง")
	_nest = Control.new()
	_nest.custom_minimum_size = Vector2(0, 190)
	_nest.clip_contents = true
	_nest.draw.connect(_draw_nest)
	ns.add_child(_nest)

	var cs := _section(col, "ประชากรรายวัน")
	_chart = Control.new()
	_chart.custom_minimum_size = Vector2(0, 92)
	_chart.draw.connect(_draw_chart)
	cs.add_child(_chart)

	var ls := _section(col, "บันทึกผู้เลี้ยง")
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_active = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_color_override("default_color", INK)
	ls.add_child(_log)


# ---------------------------------------------------------------- refresh

func refresh(delta: float) -> void:
	_t += delta
	_clock.text = "วันที่ %d  %s" % [sim.day(), sim.clock_text()]
	var m := int(sim.time_of_day() * 1440)
	var sky := "ฝนตก" if sim.climate.raining() else ("กลางคืน" if m < 360 or m > 1110 else "แจ่มใส")
	_weather.text = "อากาศ %.1f°C · %s · มดออกหากิน %d%%" % [sim.climate.air, sky, int(sim.activity * 100)]
	_frame += 1
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
	elif sim.founding():
		_show(q, "ไขมัน %d%%" % int(sim.queen.reserve / sim.QUEEN_RESERVE * 100.0), LEAF)   # sealed in, living on her reserves
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
	_show(_vals["sugar"], "%.1f" % sim.sugar, DANGER if sim.sugar < 2.0 and not fnd else INK)
	_show(_vals["protein"], "%.1f" % sim.protein, DANGER if sim.protein < 1.0 and not fnd else INK)
	_show(_vals["nest_t"], "%.1f°C" % sim.climate.nest, DANGER if sim.climate.nest > 34.0 else INK)
	_show(_vals["dev"], "%d%%" % int(sim.dev * 100))
	_show(_vals["dead"], str(sim.stats.dead + sim.stats.cannibalized))
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


func _show(l: Label, text: String, color := INK) -> void:
	l.text = text
	l.add_theme_color_override("font_color", color)


func _render_log() -> void:
	var lines := PackedStringArray()
	for e in sim.log_entries.slice(0, 40):
		var col := "#e8664f" if e.kind == "bad" else ("#9cc565" if e.kind == "ok" else "#f1e6d6")
		lines.append("[color=#8a7562]%s[/color]  [color=%s]%s[/color]" % [e.stamp, col, e.text])
	_log.text = "\n".join(lines)


# ---------------------------------------------------------------- nest cross-section

func _seeded(i: int, s: int) -> float:
	var x := sin(i * 12.9898 + s * 78.233) * 43758.5453
	return x - floor(x)


## Side view of the real excavated nest: open space projected through the depth of the block,
## coloured with the same soil layers as the 3D view. Rebuilt only when the ants have dug.
func _refresh_nest_image() -> void:
	var nv = sim.nest
	if nv.air == _proj_air and _proj_tex != null:
		return
	_proj_air = nv.air
	var img := Image.create(nv.nx, nv.ny, false, Image.FORMAT_RGBA8)
	var loam := Color(0.3, 0.2, 0.12)
	var clay := Color(0.55, 0.34, 0.2)
	var sand := Color(0.72, 0.59, 0.4)
	var hole := Color(0.2, 0.14, 0.1)        # open space: dark enough to read, light enough to see ants in it
	for y in nv.ny:
		var depth: int = nv.ny - 1 - y
		var soil := loam.lerp(clay, clampf((depth - 11) / 6.0, 0.0, 1.0)).lerp(sand, clampf((depth - 37) / 8.0, 0.0, 1.0))
		for x in nv.nx:
			var open: int = nv.proj[y * nv.nx + x]
			var tone := soil * (0.9 + 0.2 * _seeded(x * 131 + y, 3))
			tone.a = 1.0
			img.set_pixel(x, depth, tone if open == 0 else hole.lerp(tone, 0.25 / open))
	if _proj_tex == null:
		_proj_tex = ImageTexture.create_from_image(img)
	else:
		_proj_tex.update(img)
	# frame the dug part of the block (plus the surface above it) so the nest fills the panel
	var lo := Vector2i(nv.nx, nv.ny)
	var hi := Vector2i(-1, -1)
	for y in nv.ny:
		for x in nv.nx:
			if nv.proj[y * nv.nx + x] > 0:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		_crop = Rect2i(0, 0, nv.nx, nv.ny)
		return
	var cx: int = (lo.x + hi.x) / 2
	var half_w: int = maxi(16, (hi.x - lo.x) / 2 + 7)
	var top: int = nv.ny - 1                                   # always show up to the surface
	var bottom: int = maxi(0, lo.y - 7)
	var height: int = maxi(top - bottom + 1, 24)
	# keep roughly the panel's aspect (about 1.5 wide : 1 tall)
	half_w = maxi(half_w, int(height * 0.75))
	var x0: int = clampi(cx - half_w, 0, maxi(0, nv.nx - 2 * half_w))
	_crop = Rect2i(x0, nv.ny - 1 - top, mini(2 * half_w, nv.nx), mini(height, nv.ny))


func _draw_nest() -> void:
	var c := _nest
	var w := c.size.x
	var h := c.size.y
	var nv = sim.nest
	if nest_view and not nest_view.active and _t - _spots_t > 2.0:
		_spots_t = _t
		nest_view._refresh_spots()        # keep brood placement current while the 3D view is closed
	_refresh_nest_image()

	c.draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.06, 0.05))
	# keeper's water reservoir on the left: its level is the nest humidity
	var res := Rect2(6, 22, 26, h - 30)
	c.draw_rect(res, Color(0.12, 0.1, 0.09))
	var lvl: float = sim.humidity * (res.size.y - 6)
	c.draw_rect(Rect2(res.position.x + 3, res.end.y - 3 - lvl, res.size.x - 6, lvl), Color(0.3, 0.55, 0.8, 0.75))
	c.draw_rect(res, Color(0.55, 0.5, 0.45, 0.6), false, 1.0)
	_nest_label(c, "น้ำ", Vector2(8, 16))

	# the nest itself, fitted to the remaining space
	var area := Rect2(40, 12, w - 46, h - 16)
	var cr := _crop
	var s: float = minf(area.size.x / cr.size.x, area.size.y / cr.size.y)
	var size := Vector2(cr.size) * s
	var org := area.position + (area.size - size) * Vector2(0.5, 0.0)
	c.draw_rect(Rect2(org.x, org.y - 4, size.x, 4), Color("587a33"))          # turf on top
	c.draw_texture_rect_region(_proj_tex, Rect2(org, size), Rect2(cr))
	var to_screen := func(p: Vector3) -> Vector2:
		return org + Vector2(p.x + 0.5 - cr.position.x, nv.ny - 0.5 - p.y - cr.position.y) * s

	# brood where the 3D view puts it
	if nest_view:
		var sp: Dictionary = nest_view._spots
		_brood_dots(c, to_screen, sp.get("eggs", []), sim.eggs.size(), 90, Color("f4efe2"), 0.45, s, 1)
		_brood_dots(c, to_screen, sp.get("larvae", []), sim.larvae.size(), 70, Color("efe3c4"), 0.75, s, 3)
		_brood_dots(c, to_screen, sp.get("pupae", []), sim.pupae.size(), 60, Color("c9a97a"), 0.9, s, 5)
		var qp: Vector3 = sp.get("queen", Vector3.ZERO)
		if sim.queen.alive and qp != Vector3.ZERO:
			var qs: Vector2 = to_screen.call(qp)
			Kit.ant(c, qs, sin(_t * 0.3) * 0.25, 0.75 * s, 0.0, Ant.NONE, Color("24170e"), false)
			_nest_label(c, "ราชินี", qs + Vector2(-14, -2.4 * s))
		# nestmates: the same ants that walk the 3D nest, or a few resting in the chambers
		var body: Color = sim.sp["body_color"]
		if not nest_view._mates.is_empty():
			for m in nest_view._mates:
				var p: Vector3 = m.get("vp", m.to)
				var f: Vector3 = m.get("vf", Vector3.RIGHT)
				Kit.ant(c, to_screen.call(p), atan2(-f.y, f.x if absf(f.x) > 0.01 else 0.01), 0.32 * s, m.get("gait", 0.0), Ant.NONE, body, false)
		else:
			var all: Array = sp.get("all", [])
			var inside: int = mini(30, sim.workers.size() - sim.out_count)
			for i in (inside if not all.is_empty() else 0):
				var p: Vector3 = all[int(_seeded(i, 21) * all.size()) % all.size()]
				Kit.ant(c, to_screen.call(p), _seeded(i, 22) * TAU, 0.32 * s, _t * 3.0 + i, Ant.NONE, body, false)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	_nest_label(c, "ลึก %.1f ซม · %d ห้อง" % [nv.depth_cm(), nv.chambers.size()], Vector2(org.x + 4, org.y + 12))


func _brood_dots(c: Control, to_screen: Callable, spots: Array, count: int, cap: int, col: Color, r: float,
		s: float, seed: int) -> void:
	if spots.is_empty():
		return
	for i in mini(count, cap):
		var p: Vector3 = spots[i % spots.size()]
		var q: Vector2 = to_screen.call(p) + Vector2(_seeded(i, seed) - 0.5, -(i / spots.size()) * 0.5 - _seeded(i, seed + 1) * 0.4) * s
		Kit.ellipse(c, q, Vector2(r, r * 0.7) * s, col, _seeded(i, seed + 2) * 3.0)


func _nest_label(c: Control, text: String, p: Vector2) -> void:
	c.draw_string(c.get_theme_default_font(), p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MUTED)


# ---------------------------------------------------------------- chart

func _draw_chart() -> void:
	var c := _chart
	var w := c.size.x
	var h := c.size.y
	var pts: Array = sim.history.duplicate()
	pts.append({"workers": sim.workers.size(), "brood": sim.eggs.size() + sim.larvae.size() + sim.pupae.size()})
	var top := 10
	for p in pts:
		top = maxi(top, maxi(p.workers, p.brood))
	top = int(ceil(top / 10.0)) * 10
	var left := 30.0
	var font := c.get_theme_default_font()
	for v in [0, top / 2, top]:
		var y := h - 12 - float(v) / top * (h - 20)
		c.draw_line(Vector2(left, y), Vector2(w, y), LINE, 1.0)
		c.draw_string(font, Vector2(0, y + 4), str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, MUTED)
	var n := pts.size()
	for series in [["brood", INK], ["workers", AMBER]]:
		var line := PackedVector2Array()
		for i in n:
			var x := left + (0.0 if n < 2 else float(i) / (n - 1)) * (w - left - 4)
			line.append(Vector2(x, h - 12 - float(pts[i][series[0]]) / top * (h - 20)))
		if line.size() >= 2:
			c.draw_polyline(line, series[1], 2.0, true)
		c.draw_circle(line[line.size() - 1], 3.0, series[1])
	c.draw_string(font, Vector2(left, h), "วันที่ %d" % maxi(1, sim.day() - n + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, MUTED)
	c.draw_string(font, Vector2(w - 60, h), "วันนี้", HORIZONTAL_ALIGNMENT_RIGHT, 60, 10, MUTED)
