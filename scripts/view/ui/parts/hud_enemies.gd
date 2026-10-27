extends "res://scripts/view/ui/parts/hud_colonies.gd"
## HUD, layer 3 of 7: the enemy panel - how often natural enemies come (sim.set_enemy_rate); the keeper lets a wolf
## spider, a stone centipede or a ground beetle into the outworld to watch how the ants fight it (sim.release_enemy),
## sees the ones in there now (health, ants holding on) and sends the camera after one (enemy_watch -> main.gd ->
## outworld.follow_creature).

signal enemy_watch(id: int)          # the camera should follow this enemy (sim.creatures id) in the 3D outworld

const ENEMY_W := 390.0

var _enemies: PanelContainer
var _enemies_scroll: ScrollContainer
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
	# (it scrolls when the window is too short for it: in 1366 x 768 its foot ran off the bottom, over the tools)
	_enemies_scroll = ScrollContainer.new()
	_enemies_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_enemies.add_child(_enemies_scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(ENEMY_W, 0)
	_enemies_scroll.add_child(col)
	var head := HBoxContainer.new()
	var title := _label(tr("en_title"), 17, INK, _display)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _button("×", false)
	close.pressed.connect(func(): _enemies.visible = false)
	head.add_child(close)
	col.add_child(head)
	col.add_child(_label(tr("en_rate"), 13, MUTED))
	var rates := EnemyRate.new(self, sim.enemy_rate, sim.scenario)
	rates.changed.connect(func(v): sim.set_enemy_rate(v))
	col.add_child(rates)
	col.add_child(HSeparator.new())
	col.add_child(_wrapped(tr("en_how"), 12, MUTED))
	for kind in sim.ENEMY_KINDS:
		var K = sim.ENEMY_KINDS[kind]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 1)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_row := HBoxContainer.new()
		name_row.add_child(_label(_cap(tr(K.NAME)), 15, AMBER))       # ("wolf spider" in a sentence, "Wolf spider" as a heading)
		name_row.add_child(_label(K.LATIN, 12, MUTED))
		info.add_child(name_row)
		info.add_child(_wrapped(tr(K.ABOUT), 12, INK))
		row.add_child(info)
		var go := _button(tr("en_release"), false)
		go.icon = load("res://assets/ui/harmony.png")
		go.expand_icon = false
		go.add_theme_constant_override("icon_max_width", 16)
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var k: String = kind
		go.pressed.connect(func(): _release_enemy(k))
		row.add_child(go)
		_enemy_release.append(go)
		col.add_child(row)
	_enemy_warn = _wrapped("", 12, DANGER)
	col.add_child(_enemy_warn)
	col.add_child(HSeparator.new())
	col.add_child(_label(tr("en_now"), 13, MUTED))
	_enemy_list = VBoxContainer.new()
	_enemy_list.add_theme_constant_override("separation", 4)
	col.add_child(_enemy_list)
	_enemy_clear = _button(tr("en_remove"), false)
	_enemy_clear.pressed.connect(func():
		sim.remove_enemies()
		_refresh_enemies())
	col.add_child(_enemy_clear)


## A panel on the left (its scroll box): as tall as its contents, but never down over the tools at the bottom of the
## window (from y 140 to ~150 px above the bottom; 620 at most).
func fit_left_panel(scroll: ScrollContainer, w: float) -> void:
	var room: float = get_viewport().get_visible_rect().size.y - 140.0 - 150.0
	var need: float = scroll.get_child(0).get_combined_minimum_size().y if scroll.get_child_count() > 0 else 0.0
	scroll.custom_minimum_size = Vector2(w, clampf(minf(need, 620.0), 200.0, maxf(room, 200.0)))
	(scroll.get_parent() as Control).reset_size()


func _wrapped(text: String, size: int, color: Color) -> Label:
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = ENEMY_W - 80.0
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func toggle_enemies() -> void:
	_enemies.visible = not _enemies.visible
	if _enemies.visible:
		if _stars != null:
			_stars.visible = false             # (one panel on the left at a time)
		_refresh_enemies()
		fit_left_panel(_enemies_scroll, ENEMY_W + 16.0)


## What letting one in costs in Colony Harmony points (the keeper, 2026-10-27): RELEASE_PRICE for each colony there is
## with ants in it (the Home's tanks and the wild mode's together, this one counted always) - more colonies earn more.
## 0 where there is no purse (a test colony, the one shown before the first is started).
const RELEASE_PRICE := 50.0

func release_price() -> float:
	if home == null or harmony < 0.0:
		return 0.0
	var n := 0
	for s in home.tanks + home.wild:
		var m: Dictionary = Store.meta(s)
		if s == current_slot or (not m.is_empty() and (bool(m.get("queen", true)) or int(m.get("workers", 0)) > 0)):
			n += 1
	return RELEASE_PRICE * maxi(1, n)


func _release_enemy(kind: String) -> void:
	var price := release_price()
	if price > 0.0:
		if harmony < price:
			_refresh_enemies()
			return
		harmony -= price
		harmony_spent.emit(price)
	var id: int = sim.release_enemy(kind)
	_refresh_enemies()
	if id != 0:
		enemy_watch.emit(id)


## The panel as things are now (called every 0.2 s while it is open).
func _refresh_enemies() -> void:
	if _enemies == null or not _enemies.visible:
		return
	var full: bool = sim.creatures.size() >= sim.RELEASE_MAX
	var price := release_price()
	var short := price > 0.0 and harmony < price
	for b in _enemy_release:
		b.disabled = full or short
		b.text = tr("en_release_cost") % _thousands(int(price)) if price > 0.0 else tr("en_release")
	var warn := []
	if full:
		warn.append(tr("en_full") % sim.RELEASE_MAX)
	if short:
		warn.append(tr("en_need_points") % _thousands(int(price)))
	if not sim.queen.alive and sim.workers.is_empty():
		warn.append(tr("en_no_ants"))
	elif sim.workers.size() < sim.FIGHT_FROM:
		warn.append(tr("en_small") % sim.FIGHT_FROM)
	if sim.activity <= 0.05:
		warn.append(tr("en_quiet"))
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
			var watch := _button(tr("go_see"), false)
			var cid: int = c.id
			watch.pressed.connect(func(): enemy_watch.emit(cid))
			row.add_child(watch)
			_enemy_list.add_child(row)
			_enemy_rows[c.id] = l
		if ids.is_empty():
			var none := _label(tr("none"), 12, MUTED)
			_enemy_list.add_child(none)
	for c in sim.creatures:
		var S: Dictionary = sim.ENEMY_KINDS[c.kind].STATS
		var held := int(c.get("held", 0))
		var doing := tr("en_fleeing") if c.get("fleeing", false) else (tr("en_pinned") if held >= int(S.pin) else (tr("en_mobbed") if held > 0 else tr("en_hunting")))
		_enemy_rows[c.id].text = tr("en_row") % [tr(sim.ENEMY_KINDS[c.kind].NAME), doing,
			roundi(maxf(0.0, float(c.hp)) / float(S.hp) * 100.0), held, int(c.get("kills", 0))]
	_enemy_clear.visible = not ids.is_empty()


## A name as a heading: its first letter a capital (English; Thai has none).
static func _cap(s: String) -> String:
	return s.left(1).to_upper() + s.substr(1)
