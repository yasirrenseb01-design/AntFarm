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
