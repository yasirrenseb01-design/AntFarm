extends "res://scripts/view/ui/parts/hud_enemies.gd"
## HUD, layer 4 of 6: the top bar (clock, speed, views), the tool bar and the camera pad.


# ---------------------------------------------------------------- layout

func _build_top(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(14, 12)
	root.add_child(panel)
	_top = panel
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)

	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", 0)
	title.add_child(_label(sim.sp["name_th"], 22, INK, _display))
	title.add_child(_label("%s · รังเดี่ยว ราชินี 1 ตัว · %s 60×37 ซม. · v%s" % [sim.sp["name"], "แปลงสวน" if sim.scenario == "wild" else "กล่อง", ProjectSettings.get_setting("application/config/version", "dev")], 12, MUTED))
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
	# a calm pace for watching (0.5× is where a new game starts); longer stretches pass while the game is closed
	for pair in [["หยุด", 0.0], ["0.2×", 0.2], ["0.5×", 0.5], ["1×", 1.0], ["2×", 2.0], ["5×", 5.0]]:
		var b := _button(pair[0], true, g)
		b.button_pressed = pair[1] == 0.5
		var v: float = pair[1]
		b.pressed.connect(func(): speed_changed.emit(v))
		speeds.add_child(b)
	# developer speeds (F10 shows / hides them): fast-forward for testing, not for watching
	for pair in [["20×", 20.0], ["50×", 50.0], ["100×", 100.0]]:
		var b := _button(pair[0], true, g)
		var v: float = pair[1]
		b.pressed.connect(func(): speed_changed.emit(v))
		b.visible = false
		b.tooltip_text = "ความเร็วสำหรับนักพัฒนา (F10 ซ่อน/แสดง)"
		speeds.add_child(b)
		_dev_speed_buttons.append(b)
	var wrap := CenterContainer.new()
	wrap.add_child(speeds)
	row.add_child(wrap)

	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 4)
	var vg := ButtonGroup.new()
	for pair in [["พื้นดิน 3 มิติ", "outworld"], ["ในรัง 3 มิติ", "nest"]]:
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

	var foes := _button("ศัตรู", false)
	foes.tooltip_text = "ปล่อยแมงมุมหมาป่า ตะขาบหิน หรือด้วงดิน มาดูมดสู้"
	foes.pressed.connect(toggle_enemies)
	var ewrap := CenterContainer.new()
	ewrap.add_child(foes)
	row.add_child(ewrap)

	var mine := _button("รังของฉัน", false)
	mine.pressed.connect(open_colonies)
	var fwrap := CenterContainer.new()
	fwrap.add_child(mine)
	row.add_child(fwrap)

	# the nest as the desktop wallpaper, behind the icons (back: the ant icon in the system tray)
	var desk := _button("วอลเปเปอร์", false)
	desk.tooltip_text = "ให้รังมดเป็นภาพพื้นหลังเดสก์ท็อป อยู่หลังไอคอน\nกลับเข้าเกม: คลิกไอคอนมดที่ถาดระบบ (มุมขวาล่าง)"
	desk.pressed.connect(func(): desktop_requested.emit())
	var dwrap := CenterContainer.new()
	dwrap.add_child(desk)
	row.add_child(dwrap)

	var menu := _button("เมนู", false)
	menu.tooltip_text = "กลับหน้าแรก (Esc)"
	menu.pressed.connect(func(): menu_requested.emit())
	var mwrap := CenterContainer.new()
	mwrap.add_child(menu)
	row.add_child(mwrap)


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
	var place_label := _label("วางในแปลง" if sim.scenario == "wild" else "วางในกล่อง", 12, MUTED)
	row.add_child(place_label)
	_outside_tools.append(place_label)
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
	for pair in [["มือ (เลื่อนจอ)", "pan"]] + FoodKinds.tools() + [["ก้อนหิน", "rock"], ["ลบกลิ่น", "erase"]]:
		var b := _button(pair[0], true, g)
		b.button_pressed = pair[1] == ground.tool
		var t: String = pair[1]
		b.pressed.connect(func(): ground.tool = t)
		row.add_child(b)
		_outside_tools.append(b)
	row.add_child(VSeparator.new())
	var water := _button("เติมน้ำในรัง", false)
	water.pressed.connect(func(): sim.add_water())
	water.visible = sim.scenario == "keeper"     # outdoors the rain waters the nest
	row.add_child(water)
	var pher := _button("แสดงกลิ่น", true)
	pher.button_pressed = ground.show_pheromones
	pher.toggled.connect(func(on): ground.show_pheromones = on)
	row.add_child(pher)
	_outside_tools.append(pher)
	var heat := _button("แผ่นความร้อน", true)
	heat.toggled.connect(func(on):
		sim.heater = on
		sim._log("เปิดแผ่นความร้อนใต้รัง อุณหภูมิในรังจะค่อยๆ สูงขึ้น" if on else "ปิดแผ่นความร้อน"))
	heat.visible = sim.scenario == "keeper"      # outdoors there is no heat mat
	row.add_child(heat)
	var cold := _button("จำศีลในตู้เย็น", true)
	cold.button_pressed = sim.fridge_on
	cold.toggled.connect(func(on):
		sim.fridge_on = on
		sim._log(T.fridge_in if on else T.fridge_out))
	cold.visible = sim.scenario == "keeper"      # outdoors winter comes by itself
	row.add_child(cold)
	_hint = _label("", 12, MUTED)
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
	for spec in [["ปากรัง", "nest", "outworld"], ["ราชินี", "queen", "nest"], ["ตัวอ่อน", "larvae", "nest"],
			["ดักแด้", "pupae", "nest"], ["ปากรัง", "entrance", "nest"]]:
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
	_hint.text = ("ลากซ้าย หมุน · ลากขวา เลื่อน · ล้อเมาส์ ซูม · ดับเบิลคลิก ไปที่ห้องนั้น · W/S หน้า-หลัง · A/D ซ้าย-ขวา · Q/E ลง-ขึ้น · Z/C หมุน · R/F เอียง"
		if m == "nest" else "ลากซ้าย (มือ) หมุน · ลากขวา เลื่อน · ล้อเมาส์ ซูมตรงจุดที่ชี้ · ดับเบิลคลิก ซูมเข้า · WASD เลื่อน · Q/E ลง-ขึ้น · Z/C หมุน · R/F เอียง")
