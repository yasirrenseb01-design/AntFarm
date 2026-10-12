extends PanelContainer
## Hover over an ant for a moment to see who it is: its job in the colony, what it is doing now, its age and
## size, injuries, and its leanings (the thresholds that decide which work it takes up first). The views find
## the ant under the mouse (pick_ant); this box only words it.

const Ant := preload("res://scripts/sim/ant.gd")
const HOVER_S := 0.45            # seconds the mouse rests on an ant before the box opens

var sim
var views: Array = []            # the 3D views that can be asked pick_ant(screen_pos)
var _rest := 0.0
var _last := Vector2.INF
var _text: Label
var test_mouse := Vector2.INF  # dev (--hover): a mouse position to use instead of the real one


func setup(s, view_list: Array, font: Font) -> void:
	sim = s
	views = view_list
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	_text = Label.new()
	if font != null:
		_text.add_theme_font_override("font", font)
	_text.add_theme_font_size_override("font_size", 14)
	add_child(_text)


func _process(delta: float) -> void:
	var mp := get_viewport().get_mouse_position() if test_mouse == Vector2.INF else test_mouse
	if mp.distance_to(_last) > 4.0:
		_last = mp
		_rest = 0.0
		visible = false
		return
	_rest += delta
	if _rest < HOVER_S:
		return
	var hovered := get_viewport().gui_get_hovered_control() if test_mouse == Vector2.INF else null
	if hovered != null and hovered != self and hovered.mouse_filter == Control.MOUSE_FILTER_STOP:
		visible = false                       # over the panels, not the colony
		return
	if visible and fmod(_rest, 0.5) > delta:
		return                                # (refresh the words twice a second while it stays open)
	var info := {}
	for v in views:
		if v.active:
			info = v.pick_ant(mp)
	if info.is_empty():
		visible = false
		return
	_text.text = describe(info)
	visible = true
	reset_size()
	var at := mp + Vector2(18, 18)
	var vs := get_viewport_rect().size
	at.x = minf(at.x, vs.x - size.x - 8.0)
	at.y = minf(at.y, vs.y - size.y - 8.0)
	position = at


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
	return "-"
