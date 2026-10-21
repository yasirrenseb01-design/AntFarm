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
		["guide_away", "menu"],
		["guide_keys", "menu"]]
	_show(0)


func _show(i: int) -> void:
	if i >= _steps.size():
		_done()
		return
	_i = i
	_count.text = tr("guide_step") % [i + 1, _steps.size()]
	_text.text = tr(_steps[i][0])
	_next.text = tr("guide_next") if i < _steps.size() - 1 else tr("guide_done")
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
	if t != null:
		var r := t.get_global_rect()
		at.x = clampf(r.get_center().x - cs.x * 0.5, 14.0, vp.x - cs.x - 14.0)
		at.y = r.end.y + 70.0 if r.get_center().y < vp.y * 0.5 else r.position.y - cs.y - 70.0
	_card.position = at
	queue_redraw()


func _process(_delta: float) -> void:
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
	var from := Vector2(clampf(r.get_center().x, c.position.x + 20.0, c.end.x - 20.0), c.position.y if r.get_center().y < c.position.y else c.end.y)
	var to := Vector2(r.get_center().x, r.end.y + 4.0 if r.get_center().y < c.position.y else r.position.y - 4.0)
	draw_line(from, to, ink, 2.5, true)
	var d := (to - from).normalized()
	var side := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([to, to - d * 14.0 + side * 7.0, to - d * 14.0 - side * 7.0]), ink)


func _done() -> void:
	finished.emit()
	queue_free()
