extends "res://scripts/view/ui/parts/hud_colonies.gd"
## HUD, layer 3 of 6: the enemy panel - the keeper lets a wolf spider, a stone centipede or a ground beetle into
## the outworld to watch how the ants fight it (sim.release_enemy), sees the ones in there now (health, ants
## holding on) and sends the camera after one (enemy_watch -> main.gd -> outworld.follow_creature).

signal enemy_watch(id: int)          # the camera should follow this enemy (sim.creatures id) in the 3D outworld

const ENEMY_W := 390.0

var _enemies: PanelContainer
var _enemy_release: Array = []       # the release buttons (off while the outworld is full)
var _enemy_warn: Label
var _enemy_list: VBoxContainer
var _enemy_rows := {}                # creature id -> its status label
var _enemy_shown: Array = [-1]       # the ids the rows were built for (-1: not built yet)
var _enemy_clear: Button


func _build_enemies(root: Control) -> void:
	_enemies = PanelContainer.new()
	_enemies.position = Vector2(14, 140)
	_enemies.visible = false
	root.add_child(_enemies)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(ENEMY_W, 0)
	_enemies.add_child(col)
	var head := HBoxContainer.new()
	var title := _label("ศัตรู · ปล่อยมาดูมดสู้", 17, INK, _display)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _button("×", false)
	close.pressed.connect(func(): _enemies.visible = false)
	head.add_child(close)
	col.add_child(head)
	col.add_child(_wrapped("ศัตรูเดินเข้ามาจากขอบพื้นที่หาอาหาร ล่าอยู่ราวครึ่งวันในเกมแล้วจากไป ถ้ามดไม่รุมฆ่าหรือไล่ไปก่อน · มดที่เจอจะปล่อยกลิ่นเตือนภัย พวกพ้องกรูมากัดและพ่นกรดฟอร์มิก · ศัตรูที่ตายกลายเป็นอาหารของรัง", 12, MUTED))
	for kind in sim.ENEMY_KINDS:
		var K = sim.ENEMY_KINDS[kind]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 1)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_row := HBoxContainer.new()
		name_row.add_child(_label(K.NAME, 15, AMBER))
		name_row.add_child(_label(K.LATIN, 12, MUTED))
		info.add_child(name_row)
		info.add_child(_wrapped(K.ABOUT, 12, INK))
		row.add_child(info)
		var go := _button("ปล่อย", false)
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var k: String = kind
		go.pressed.connect(func(): _release_enemy(k))
		row.add_child(go)
		_enemy_release.append(go)
		col.add_child(row)
	_enemy_warn = _wrapped("", 12, DANGER)
	col.add_child(_enemy_warn)
	col.add_child(HSeparator.new())
	col.add_child(_label("ในพื้นที่หาอาหารตอนนี้", 13, MUTED))
	_enemy_list = VBoxContainer.new()
	_enemy_list.add_theme_constant_override("separation", 4)
	col.add_child(_enemy_list)
	_enemy_clear = _button("เอาศัตรูออกทั้งหมด", false)
	_enemy_clear.pressed.connect(func():
		sim.remove_enemies()
		_refresh_enemies())
	col.add_child(_enemy_clear)


func _wrapped(text: String, size: int, color: Color) -> Label:
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = ENEMY_W - 80.0
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func toggle_enemies() -> void:
	_enemies.visible = not _enemies.visible
	if _enemies.visible:
		_refresh_enemies()


func _release_enemy(kind: String) -> void:
	var id: int = sim.release_enemy(kind)
	_refresh_enemies()
	if id != 0:
		enemy_watch.emit(id)


## The panel as things are now (called every 0.2 s while it is open).
func _refresh_enemies() -> void:
	if _enemies == null or not _enemies.visible:
		return
	var full: bool = sim.creatures.size() >= sim.RELEASE_MAX
	for b in _enemy_release:
		b.disabled = full
	var warn := []
	if full:
		warn.append("มีศัตรูในพื้นที่ครบ %d ตัวแล้ว" % sim.RELEASE_MAX)
	if not sim.queen.alive and sim.workers.is_empty():
		warn.append("รังนี้ไม่มีมดเหลือแล้ว")
	elif sim.workers.size() < sim.FIGHT_FROM:
		warn.append("รังยังมีมดงานไม่ถึง %d ตัว: มดจะหลบ ไม่รุมสู้ ศัตรูจับมดที่ออกหากินได้ง่าย" % sim.FIGHT_FROM)
	if sim.activity <= 0.05:
		warn.append("ตอนนี้มดแทบไม่ออกจากรัง (หนาว กลางคืน หรือจำศีล) จะไม่ค่อยได้เห็นการต่อสู้")
	_enemy_warn.text = "\n".join(warn)
	_enemy_warn.visible = not warn.is_empty()
	# one row per enemy in the outworld: rebuilt when one comes or goes, its numbers updated in place
	var ids := []
	for c in sim.creatures:
		ids.append(c.id)
	if ids != _enemy_shown:
		_enemy_shown = ids
		for r in _enemy_list.get_children():
			r.queue_free()
		_enemy_rows.clear()
		for c in sim.creatures:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var l := _label("", 12, INK)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var watch := _button("ไปดู", false)
			var cid: int = c.id
			watch.pressed.connect(func(): enemy_watch.emit(cid))
			row.add_child(watch)
			_enemy_list.add_child(row)
			_enemy_rows[c.id] = l
		if ids.is_empty():
			var none := _label("ไม่มี", 12, MUTED)
			_enemy_list.add_child(none)
	for c in sim.creatures:
		var S: Dictionary = sim.ENEMY_KINDS[c.kind].STATS
		var held := int(c.get("held", 0))
		var doing := "กำลังหนี" if c.get("fleeing", false) else ("ถูกมดตรึงไว้" if held >= int(S.pin) else ("มดรุมอยู่" if held > 0 else "กำลังล่า"))
		_enemy_rows[c.id].text = "%s · %s · พลังเหลือ %d%% · มดเกาะ %d · จับมดได้ %d" % [sim.ENEMY_KINDS[c.kind].NAME, doing,
			roundi(maxf(0.0, float(c.hp)) / float(S.hp) * 100.0), held, int(c.get("kills", 0))]
	_enemy_clear.visible = not ids.is_empty()
