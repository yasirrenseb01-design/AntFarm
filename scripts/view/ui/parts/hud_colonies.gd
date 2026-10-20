extends "res://scripts/view/ui/parts/hud_base.gd"
## HUD, layer 2 of 6: the "my colonies" window (save slots, time while closed) and report dialogs.


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
				"สวน" if m.get("scenario", "keeper") == "wild" else "ชุดเลี้ยง", m.get("day", 1), m.get("workers", 0),
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
	care.text = "ผู้ช่วยเติมน้ำและให้อาหารตอนที่ไม่อยู่ (เฉพาะชุดเลี้ยง)"
	care.button_pressed = settings.get("care", true)
	care.toggled.connect(func(on):
		settings["care"] = on
		settings_changed.emit(settings))
	col.add_child(care)
	var tune := HBoxContainer.new()
	tune.add_child(_label("เพลงพื้นหลัง", 13, MUTED))
	var vol := HSlider.new()
	vol.focus_mode = Control.FOCUS_NONE
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = float(settings.get("music", 0.6))
	vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vol_txt := _label("ปิด" if vol.value <= 0.0 else "%d%%" % roundi(vol.value * 100), 13, INK)
	vol_txt.custom_minimum_size.x = 44
	vol.value_changed.connect(func(v):
		settings["music"] = v
		vol_txt.text = "ปิด" if v <= 0.0 else "%d%%" % roundi(v * 100)
		if music != null:
			music.volume = v
		settings_changed.emit(settings))
	tune.add_child(vol)
	tune.add_child(vol_txt)
	col.add_child(tune)
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


## A slider for how often natural enemies come (sim.enemy_rate: 0 - 300% of the usual), saying about how many days apart
## that is - in the new-colony window and the enemy panel.
class EnemyRate extends VBoxContainer:
	signal changed(rate: float)
	var _hud
	var _slider: HSlider
	var _text: Label
	var _scen := "wild"

	func _init(hud, rate: float, scen: String) -> void:
		_hud = hud
		add_theme_constant_override("separation", 2)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(hud._label("ไม่มี", 12, hud.MUTED))
		_slider = HSlider.new()
		_slider.min_value = 0.0
		_slider.max_value = 3.0
		_slider.step = 0.25
		_slider.focus_mode = Control.FOCUS_NONE
		_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_slider)
		row.add_child(hud._label("บ่อยมาก", 12, hud.MUTED))
		add_child(row)
		_text = hud._label("", 12, hud.INK)
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
			_text.text = "0% · ไม่มีศัตรูมาเอง (ยังปล่อยมาดูได้จากปุ่ม \"ศัตรู\")"
			return
		var days: float = _hud.sim.enemy_days(v)
		var when := ("ราวๆ วันละ %.1f ตัว" % (1.0 / days)) if days < 1.0 else "ราวๆ ทุก %s วัน" % ("%.1f" % days if days < 3.0 else str(roundi(days)))
		var level := "น้อย" if v < 0.75 else ("ตามธรรมชาติ" if v <= 1.25 else ("บ่อย" if v <= 2.0 else "บ่อยมาก"))
		_text.text = "%d%% (%s) · %s%s" % [roundi(v * 100.0), level, when,
			" ในหน้าร้อน · ฤดูใบไม้ผลิ/ร่วงน้อยลง หน้าหนาวไม่มี" if _scen == "wild" else " ทั้งปี"]


## Choices for a new colony: where it lives, what it lives in, and how it starts.
const NEW_SCENARIOS := [
	["wild", "สวน/ทุ่งหญ้า (กลางแจ้ง)", "แปลงดินโล่งมีแดดแบบที่มดดำสวนชอบทำรัง สี่ฤดูแบบเขตอบอุ่น ไม่ต้องดูแล: ฝนให้น้ำ มดหาน้ำหวานจากเพลี้ยและล่าแมลงเอง หน้าหนาวต้องสะสมไขมันไว้จำศีล มีศัตรูธรรมชาติ (แมงมุม ตะขาบ ด้วงดิน) รังมีปีดีปีร้ายตามธรรมชาติ"],
	["keeper", "ชุดเลี้ยง (ในห้อง)", "ฟอร์มิคาเรียมบนชั้นในห้อง อุณหภูมิห้องทั้งปี มีแผ่นความร้อน ปกติไม่มีศัตรู (ตั้งได้ข้างล่าง) ราชินีที่ไม่ได้จำศีลจะวางไข่น้อยลงเรื่อยๆ"]]
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
	var rates := EnemyRate.new(self, 1.0, "wild")
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
				note.text = o[2]
				if key == "scenario":
					if not picked.has("rate_set"):
						picked["rate"] = 1.0 if o[0] == "wild" else 0.0       # (each scene's usual, until the keeper picks one;
					rates.set_rate(picked.rate, o[0]))                      # it showed 0% for the formicarium and sent 100%)
			row.add_child(b)
		col.add_child(note)
	col.add_child(_label("สัตว์ร้าย (แมงมุมหมาป่า ตะขาบหิน ด้วงดิน)", 15, AMBER))
	picked["rate"] = 1.0
	rates.changed.connect(func(v):
		picked["rate"] = v
		picked["rate_set"] = true)
	col.add_child(rates)
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
		colony_new.emit(slot, "%s:%s:%s:%s" % [picked.nest, picked.start, picked.scenario, picked.rate]))
	foot.add_child(go)
	col.add_child(foot)
	win.reset_size()
	win.popup_centered()


## Asks before doing something (a dialog with the keeper's own OK and "ยกเลิก").
func confirm(title: String, text: String, ok_text: String, on_ok: Callable) -> void:
	var d := ConfirmationDialog.new()
	d.theme = _report.theme
	d.title = title
	d.dialog_text = text
	d.ok_button_text = ok_text
	d.cancel_button_text = "ยกเลิก"
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
