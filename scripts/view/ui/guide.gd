extends Control
## The first-colony guide (PART EA-R R4): a few cards on notebook paper, one at a time, each with a pencilled arrow to the
## control it is about (the speed buttons, add water, the food, the views, the star ants, the menu). "Next" / "Skip";
## once through (or skipped) it does not come back unless the keeper asks for it again in the settings.
## The HUD owns it (hud.start_guide); the words are in lang/strings.csv (guide_*), the garden's where they differ.

const Paper := preload("res://scripts/view/ui/paper.gd")
const CARD_W := 400.0

signal finished

var hud
var _steps: Array = []                # [text key, target name in hud.guide_targets or ""]
var _i := 0
var _card: PanelContainer
var _text: Label
var _count: Label
var _next: Button


func setup(h) -> void:
	hud = h
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE           # (the game goes on underneath; only the card takes clicks)
	z_index = 70
	_card = PanelContainer.new()
	_card.theme = h._paper_theme
	_card.add_theme_stylebox_override("panel", Paper.page(18, 14))
	_card.custom_minimum_size.x = CARD_W
	add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_card.add_child(col)
	_count = h._label("", 12, Paper.ACCENT)
	col.add_child(_count)
	_text = h._label("", 15, Paper.INK)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = CARD_W - 36.0
	col.add_child(_text)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 8)
	var skip := Button.new()
	skip.text = tr("guide_skip")
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(_done)
	foot.add_child(skip)
	_next = Button.new()
	_next.focus_mode = Control.FOCUS_NONE
	_next.pressed.connect(func(): _show(_i + 1))
	foot.add_child(_next)
	col.add_child(foot)
	var wild: bool = h.sim.scenario == "wild"
	_steps = [["guide_welcome", "speeds"],
		["guide_water_wild" if wild else "guide_water", "" if wild else "water"],
		["guide_food_wild" if wild else "guide_food", "food"],
		["guide_views", "views"],
		["guide_ants", "stars"],
		["guide_stats", "stats"],
		["guide_away", "menu"],
		["guide_keys", "fold"]]
	_show(0)


func _show(i: int) -> void:
	if i >= _steps.size():
		_done()
		return
	_i = i
	_count.text = tr("guide_step") % [i + 1, _steps.size()]
	_text.text = tr(_steps[i][0])
	_next.text = tr("guide_next") if i < _steps.size() - 1 else tr("guide_done")
	if _steps[i][1] in ["water", "stats"] and not hud._side.visible:
		hud.set_side_open(true)              # (the water tube and the Statistics tab are in the side panel: folded away)
	if not hud._top.visible:
		hud.set_bar_open(true)               # (the bar folded to its note: most of what the guide shows is on it)
	_card.reset_size()
	_place.call_deferred()


func _target() -> Control:
	var name: String = _steps[_i][1]
	var t = hud.guide_targets.get(name)
	return t if t != null and is_instance_valid(t) and t.is_visible_in_tree() else null


## The card beside what it is about: under it near the top of the window, over it near the bottom; in the middle when
## it is about nothing on screen.
func _place() -> void:
	var vp := get_viewport_rect().size
	var cs := _card.get_combined_minimum_size()
	var t := _target()
	var at := (vp - cs) * 0.5
	_beside = false
	if t != null:
		var r := t.get_global_rect()
		var bar: Rect2 = hud._top.get_global_rect()
		if hud._top.visible and bar.encloses(r):
			# on the bar down the left (from v0.11.78): beside it, level with what it points at - under it, the card
			# lay over the bar's own buttons
			_beside = true
			at = Vector2(bar.end.x + 70.0, clampf(r.get_center().y - cs.y * 0.5, 14.0, vp.y - cs.y - 14.0))
			_card.position = at
			queue_redraw()
			return
		var side: Rect2 = hud._side.get_global_rect()
		if hud._side.visible and side.encloses(r):
			# (on the side panel: left of it, not over the colony's figures)
			_beside = true
			at = Vector2(side.position.x - cs.x - 70.0, clampf(r.get_center().y - cs.y * 0.5, 14.0, vp.y - cs.y - 14.0))
			_card.position = at
			queue_redraw()
			return
		at.x = clampf(r.get_center().x - cs.x * 0.5, 14.0, vp.x - cs.x - 14.0)
		at.y = r.end.y + 70.0 if r.get_center().y < vp.y * 0.5 else r.position.y - cs.y - 70.0
	# not over the ant's info box or a panel open on the left: along to where it is clear of them (it stays put while
	# nothing is in its way)
	var keep_out := _keep_out()
	var spots: Array = [at.x, vp.x - cs.x - 14.0, 14.0, (vp.x - cs.x) * 0.5]
	for x in spots:
		var rr := Rect2(Vector2(x, at.y), cs)
		if not keep_out.any(func(k): return (k as Rect2).intersects(rr)):
			at.x = x
			break
	_card.position = at
	queue_redraw()


## What the card keeps clear of: the ant's info box, the enemy or star ants panel on the left, the camera buttons.
func _keep_out() -> Array:
	var out := []
	for c in [hud.ant_tip, hud._enemies, hud._stars, hud._cam_pad]:
		if c != null and is_instance_valid(c) and c.is_visible_in_tree():
			out.append((c as Control).get_global_rect().grow(8.0))
	return out


var _seen_out := []
var _beside := false               # the card beside the bar or the side panel, the arrow across to it

func _process(_delta: float) -> void:
	var now := _keep_out()
	if str(now) != str(_seen_out):
		_seen_out = now
		_place()                                           # (a box or panel opened or closed: out of its way)
	queue_redraw()                                         # (the arrow follows the bar as it changes)


## A pencilled ring round the control and an arrow to it from the card.
func _draw() -> void:
	var t := _target()
	if t == null:
		return
	var r := t.get_global_rect().grow(5.0)
	var ink := Paper.ACCENT
	draw_rect(r, Color(ink, 0.9), false, 2.5)
	var c := _card.get_global_rect()
	if _beside:
		# (the card right of the bar: the arrow across to it)
		var left := r.get_center().x < c.position.x
		var f2 := Vector2(c.position.x if left else c.end.x, clampf(r.get_center().y, c.position.y + 16.0, c.end.y - 16.0))
		var t2 := Vector2(r.end.x + 4.0 if left else r.position.x - 4.0, r.get_center().y)
		draw_line(f2, t2, ink, 2.5, true)
		var d2 := (t2 - f2).normalized()
		var s2 := Vector2(-d2.y, d2.x)
		draw_colored_polygon(PackedVector2Array([t2, t2 - d2 * 14.0 + s2 * 7.0, t2 - d2 * 14.0 - s2 * 7.0]), ink)
		return
	var from := Vector2(clampf(r.get_center().x, c.position.x + 20.0, c.end.x - 20.0), c.position.y if r.get_center().y < c.position.y else c.end.y)
	var to := Vector2(r.get_center().x, r.end.y + 4.0 if r.get_center().y < c.position.y else r.position.y - 4.0)
	draw_line(from, to, ink, 2.5, true)
	var d := (to - from).normalized()
	var side := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([to, to - d * 14.0 + side * 7.0, to - d * 14.0 - side * 7.0]), ink)


func _done() -> void:
	finished.emit()
	queue_free()
