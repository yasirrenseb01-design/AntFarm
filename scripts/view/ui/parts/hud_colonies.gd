extends "res://scripts/view/ui/parts/hud_base.gd"
## HUD, layer 2 of 5: the "my colonies" window (save slots, time while closed) and report dialogs.


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
			desc = "%s · วันที่ %d · มดงาน %d · %s%s · บันทึก %s" % [
				"ป่า" if m.get("scenario", "keeper") == "wild" else "ชุดเลี้ยง", m.get("day", 1), m.get("workers", 0),
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
		var fresh := _button("เริ่มใหม่…", false)
		var slot_k: int = s
		var occupied: bool = not m.is_empty()
		fresh.pressed.connect(func():
			_colonies.hide()
			_open_new_colony(slot_k, occupied))
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


## Choices for a new colony: where it lives, what it lives in, and how it starts.
const NEW_SCENARIOS := [
	["wild", "ป่า (แปลงดินกลางแจ้ง)", "สี่ฤดูแบบเขตอบอุ่นที่มดดำสวนอาศัยอยู่จริง หน้าหนาวดินเย็นจัด มดต้องสะสมไขมันไว้จำศีล เพลี้ยและแมลงมีแค่ช่วงอากาศอุ่น และมีศัตรูธรรมชาติ (แมงมุม ตะขาบ ด้วงดิน)"],
	["keeper", "ชุดเลี้ยง (ในห้อง)", "ฟอร์มิคาเรียมบนชั้นในห้อง อุณหภูมิห้องทั้งปี มีแผ่นความร้อน ไม่มีศัตรูธรรมชาติ ราชินีที่ไม่ได้จำศีลจะวางไข่น้อยลงเรื่อยๆ"]]
const NEW_NESTS := [["soil", "ก้อนดิน", "มดขุดอุโมงค์เองในดินทั้งก้อน"], ["glass", "ตู้แอนท์ฟาร์ม", "ดินแผ่นบางระหว่างกระจกสองแผ่น มองเห็นทุกห้อง"]]
const NEW_STARTS := [["queen", "ราชินีตัวเดียว", "ราชินีหลังบินผสมพันธุ์ปลายเดือนกรกฎาคม ขังตัวเองเลี้ยงลูกชุดแรกด้วยไขมันในตัว"],
	["young", "รังอายุ 3 เดือน (14 ตัว)", "ราชินีกับมดงาน 14 ตัว เริ่มกลางเดือนเมษายน"]]


## The new-colony window: pick a scenario, a nest and a start, then start it in this slot.
func _open_new_colony(slot: int, occupied: bool) -> void:
	var win := Window.new()
	win.title = "เริ่มรังใหม่ในรัง %d" % slot
	win.theme = _colonies.theme
	win.transient = true
	win.exclusive = true
	win.unresizable = true
	win.wrap_controls = true
	win.close_requested.connect(win.queue_free)
	_colonies.get_parent().add_child(win)
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", _box(Color(0.1, 0.075, 0.055, 0.98), LINE, 0, 16, 14))
	win.add_child(body)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(540, 0)
	body.add_child(col)
	var picked := {}
	for group in [["scenario", "ฉาก", NEW_SCENARIOS], ["nest", "รัง", NEW_NESTS], ["start", "เริ่มจาก", NEW_STARTS]]:
		var key: String = group[0]
		var opts: Array = group[2]
		col.add_child(_label(group[1], 15, AMBER))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		var note := _label(opts[0][2], 12, MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(540, 0)
		var bg := ButtonGroup.new()
		picked[key] = opts[0][0]
		for o in opts:
			var b := _button(o[1], true)
			b.button_group = bg
			b.button_pressed = o == opts[0]
			b.pressed.connect(func():
				picked[key] = o[0]
				note.text = o[2])
			row.add_child(b)
		col.add_child(note)
	col.add_child(HSeparator.new())
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 10)
	if occupied:
		var warn := _label("รังเดิมในช่องนี้จะถูกลบ", 12, DANGER)
		warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(warn)
	var cancel := _button("ยกเลิก", false)
	cancel.pressed.connect(win.queue_free)
	foot.add_child(cancel)
	var go := _button("เริ่มรังนี้", false)
	go.pressed.connect(func():
		win.queue_free()
		colony_new.emit(slot, "%s:%s:%s" % [picked.nest, picked.start, picked.scenario]))
	foot.add_child(go)
	col.add_child(foot)
	win.reset_size()
	win.popup_centered()


func show_report(title: String, text: String) -> void:
	_report.title = title
	_report.dialog_text = text
	_report.popup_centered(Vector2i(520, 0))
