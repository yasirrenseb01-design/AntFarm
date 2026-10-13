extends PanelContainer
## Click an ant to select it: a white outline follows it (drawn by the view) and this box stays open with who it
## is - its job in the colony, what it is doing now, its age and size, injuries, and its leanings (the thresholds
## that decide which work it takes up first). Click empty ground or press Esc to let it go. The views find the
## ant under the mouse (pick_ant) and report the selected one as it is now (info_for).

const Ant := preload("res://scripts/sim/ant.gd")

var sim
var views: Array = []            # the 3D views (pick_ant, info_for, can_select, sel_kind / sel_id)
var sel := {}                    # {"kind": "worker"|"digger"|"queen", "id": worker id (a digger: its own id)}
var test_mouse := Vector2.INF    # dev (--hover): select the ant at this screen position
var _press := Vector2.INF
var _text: Label
var _t := 0.0


func setup(s, view_list: Array, font: Font) -> void:
	sim = s
	views = view_list
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	position = Vector2(18, 140)
	_text = Label.new()
	if font != null:
		_text.add_theme_font_override("font", font)
	_text.add_theme_font_size_override("font_size", 14)
	add_child(_text)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press = e.position
		elif _press != Vector2.INF and _press.distance_to(e.position) < 6.0:      # a click, not a drag
			_click(e.position)
			_press = Vector2.INF
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and not sel.is_empty():
		_select({})


func _active_view():
	for v in views:
		if v != null and v.active:
			return v
	return null


func _click(at: Vector2) -> void:
	var v = _active_view()
	if v == null or not v.can_select():
		return
	_select(v.pick_ant(at))


func _select(info: Dictionary) -> void:
	if info.is_empty():
		sel = {}
	elif info.kind == "digger":
		sel = {"kind": "digger", "id": int(info.get("dig", -1))}
	elif info.kind == "queen":
		sel = {"kind": "queen", "id": -1}
	else:
		sel = {"kind": "worker", "id": info.w.id if info.get("w") != null else -1}
	for v in views:
		if v != null:
			v.sel_kind = sel.get("kind", "")
			v.sel_id = int(sel.get("id", -1))
	visible = not sel.is_empty()


func _process(delta: float) -> void:
	if test_mouse != Vector2.INF:
		_click(test_mouse)
		test_mouse = Vector2.INF
	if sel.is_empty():
		return
	_t += delta
	if _t < 0.25:
		return                                 # (the words are refreshed four times a second)
	_t = 0.0
	var v = _active_view()
	var info: Dictionary = v.info_for(sel.kind, sel.id) if v != null else {}
	if info.is_empty() and sel.kind == "worker":
		# not in this view (gone into the nest, or out): still say who it is and where
		for w in sim.workers:
			if w.id == sel.id:
				info = {"kind": "worker", "w": w, "act": w.act, "elsewhere": "อยู่ในรัง" if w.state == Ant.IN_NEST else "อยู่นอกรัง"}
	if info.is_empty():
		_text.text = "มดตัวที่เลือกไม่อยู่แล้ว (ตายหรือไม่อยู่ในมุมนี้)"
	else:
		_text.text = describe(info) + ("
(" + info.elsewhere + " — สลับมุมมองเพื่อดูตัว)" if info.has("elsewhere") else "")
	reset_size()


## The words for an ant found by a view: {"kind": "worker"|"queen"|"digger", "w": Ant or null, "role", "act"}.
func describe(info: Dictionary) -> String:
	if info.kind == "queen":
		var lines := ["ราชินี"]
		if not sim.queen.alive:
			lines.append("ตายแล้ว")
		elif sim.hibernating() or sim.climate.nest < 6.0:
			lines.append("จำศีล")
		elif sim.founding():
			lines.append("ปิดตัวเลี้ยงลูกรุ่นแรกด้วยไขมันของตัวเอง (เหลือ %d%%)" % int(sim.queen.reserve / float(sim.sp["queen_reserve"]) * 100.0))
		else:
			lines.append("วางไข่" if not (sim.starving or sim.queen.starve > 0.5) else "หยุดวางไข่ (อาหารไม่พอ)")
		lines.append("กำลังทำ: " + _act_name(int(info.get("act", 1))))
		return "\n".join(lines)
	var w = info.get("w")
	var lines := []
	lines.append("มดงาน #%d" % w.id if w != null else "มดงาน")
	lines.append("หน้าที่: " + _job(w, info))
	lines.append("กำลังทำ: " + _act_name(int(info.get("act", 0))))
	if w != null:
		lines.append("อายุ %d วัน · ยาว %.1f มม." % [int(w.age), w.size * 4.2])
		if w.carry == Ant.SUGAR:
			lines.append("กระเพาะพักเต็มไปด้วยน้ำหวาน")
		elif w.carry == Ant.PROTEIN:
			lines.append("คาบชิ้นเหยื่อ")
		elif w.carry == Ant.CORPSE:
			lines.append("แบกศพเพื่อนร่วมรัง")
		if w.hurt > 0.05:
			lines.append("บาดเจ็บ (ขาหรือหนวดขาด) เดินช้าลง")
		if w.energy < 0.6:
			lines.append("หิว / อ่อนแรง")
		var lean := _leanings(w)
		if lean != "":
			lines.append("นิสัย: " + lean)
	return "\n".join(lines)


func _job(w, info: Dictionary) -> String:
	if info.kind == "digger":
		return "ขุดรัง"
	if info.get("role", "") == "attend":
		return "ดูแลราชินี"
	if w == null:
		return "-"
	match w.state:
		Ant.SEARCH:
			return "ออกหาอาหาร"
		Ant.RETURN:
			return "ขนอาหารกลับรัง"
		Ant.HOME:
			return "เดินกลับรัง"
		Ant.UNDERTAKER:
			return "ขนศพไปกองขยะ"
		Ant.DEFEND:
			return "ป้องกันรัง"
		Ant.DRAG:
			return "ช่วยกันลากเหยื่อกลับรัง"
	match w.task:
		Ant.TASK_CALLOW:
			return "มดใหม่ (ตัวยังซีด เพิ่งออกจากรังไหม)"
		Ant.TASK_NURSE:
			return "พี่เลี้ยง (เลี้ยงไข่ ตัวอ่อน รังไหม)"
		Ant.TASK_DIG:
			return "ขุดรัง"
		Ant.TASK_RESERVE:
			return "เพิ่งกลับจากข้างนอก" if info.get("role", "") == "traffic" else "มดสำรองในรัง (พร้อมออกหากิน ขนศพ หรือสู้)"
	return "-"


## Its standing leanings from the response thresholds (only the clear ones).
func _leanings(w) -> String:
	var out := []
	if w.threshold(Ant.TH_FORAGE) < 0.8:
		out.append("ออกหากินก่อนตัวอื่น")
	elif w.threshold(Ant.TH_FORAGE) > 1.25:
		out.append("ไม่ค่อยออกนอกรัง")
	if w.threshold(Ant.TH_DIG) < 0.75:
		out.append("ชอบขุด")
	if w.threshold(Ant.TH_DEFEND) < 0.75:
		out.append("กล้าสู้")
	if w.threshold(Ant.TH_ATTEND) < 0.75:
		out.append("ชอบอยู่ใกล้ราชินี")
	if w.threshold(Ant.TH_AGE) > 1.25:
		out.append("เป็นพี่เลี้ยงนานกว่าตัวอื่น")
	return ", ".join(out)


func _act_name(act: int) -> String:
	match act % 100:
		0: return "เดิน"
		1: return "พัก"
		2: return "กัด / ขุดดิน"
		3: return "แตะหนวดทักทาย"
		4: return "ทำความสะอาดตัว"
		5: return "วางไข่"
		6: return "ป้อนอาหารปากต่อปาก"
		21: return "รับอาหารปากต่อปาก"
		7: return "เลียดูแลลูกมด / ราชินี"
		8: return "คาบของ"
		9: return "รีดน้ำหวานจากเพลี้ย"
		10: return "กินน้ำ / น้ำหวาน"
		13: return "สู้ (กัดและพ่นกรด)"
		14: return "ตื่นตัว วิ่งเข้าหาศัตรู"
		15: return "หยุดสำรวจรอบตัว"
		16: return "เดินตามทางกลิ่น"
		17: return "ยกไข่"
		18: return "ล้มหงาย กำลังพลิกตัว"
		19: return "ลากเหยื่อ"
		20: return "ปีนผนังกระจก"
		22: return "ออกไปหากินนอกแปลง"
	return "-"
