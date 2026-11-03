extends PanelContainer
## The Home's first visit (the keeper, 2026-11-03: the guide to cover the Home too): a page in the middle of the room
## telling what is where - a tank clicked to go in, the water card, the shop, the fridge, Tab for the buttons - until
## the keeper presses OK (settings "home_tips_done"; the pointer is free while it is up: home.gd _pointer_free).

const Paper := preload("res://scripts/view/ui/paper.gd")
const Store := preload("res://scripts/game/save_store.gd")

var home_ui                      # game/home.gd


func setup(ui) -> void:
	home_ui = ui
	var h = ui.main.hud
	add_theme_stylebox_override("panel", Paper.page(26, 20))
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	col.add_child(h._label(tr("home_tips_title"), 20, Paper.ACCENT))
	for k in ["home_tip_tank", "home_tip_water", "home_tip_shop", "home_tip_fridge", "home_tip_keys"]:
		var l: Label = h._label("• " + tr(k), 15, Paper.INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 560
		col.add_child(l)
	var ok: Button = h._button(tr("home_tips_ok"), false)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func():
		visible = false
		home_ui.main._settings["home_tips_done"] = true
		Store.save_settings(home_ui.main._settings))
	col.add_child(ok)
	visible = false


## Up the first time the Home opens (not in test shots).
func maybe_show() -> void:
	var m = home_ui.main
	visible = not bool(m._settings.get("home_tips_done", false)) and not m._opts.has("shot") or m._opts.has("home-tips")
	if visible:
		reset_size()
		offset_left = -size.x * 0.5
		offset_right = size.x * 0.5
		offset_top = -size.y * 0.5
		offset_bottom = size.y * 0.5
