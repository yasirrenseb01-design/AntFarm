extends PanelContainer
## The Home's shop (the keeper, 2026-10-27): a page on the right of the room, opened from the bar at the top. Paid with
## Colony Harmony points (game/harmony.gd); what there is and what it costs in home_store.gd (PRICES, why_not, buy).
## A shelf is only somewhere to put tanks: each small tank is bought apart (one tank, one colony).

const Paper := preload("res://scripts/view/ui/paper.gd")
# what is sold, its name and its note (keys of lang/strings.csv, written out: tests/lang_test.gd finds them so)
const ITEMS := [["big", "shop_big", "shop_big_note"], ["small", "shop_small", "shop_small_note"],
	["shelf2", "shop_shelf2", "shop_shelf2_note"], ["shelf4", "shop_shelf4", "shop_shelf4_note"]]

var home_ui                    # game/home.gd
var _col: VBoxContainer
var purse: Label               # the points there are (home.gd keeps it up to date)


func setup(ui) -> void:
	home_ui = ui
	add_theme_stylebox_override("panel", Paper.page(20, 16))
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -430
	offset_right = -16
	offset_top = 62
	mouse_filter = Control.MOUSE_FILTER_STOP
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 6)
	add_child(_col)
	visible = false


static func num(v: float) -> String:
	var s := str(int(floorf(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func refresh() -> void:
	var h = home_ui.main.hud
	for c in _col.get_children():
		c.queue_free()
	_col.add_child(h._label(tr("shop_title"), 18, Paper.ACCENT))
	var have: float = home_ui.main.harmony.points
	purse = h._label(tr("home_purse") % num(have), 13, Paper.PENCIL)
	_col.add_child(purse)
	for row_of in ITEMS:
		var item: String = row_of[0]
		_col.add_child(HSeparator.new())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		info.add_child(h._label(tr(row_of[1]), 15, Paper.INK))
		var note: Label = h._label(tr(row_of[2]), 12, Paper.PENCIL)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 250
		info.add_child(note)
		var why: String = home_ui.main.home.why_not(item, have)
		if why != "":
			info.add_child(h._label(tr(why), 12, Paper.LEAF if why == "shop_owned" else Paper.DANGER))
		row.add_child(info)
		var right := VBoxContainer.new()
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		var price: float = home_ui.main.home.PRICES[item]
		right.add_child(h._label(tr("shop_price") % num(price), 13, Paper.ACCENT))
		var buy: Button = h._button(tr("shop_buy"), false)
		buy.disabled = why != ""
		var it: String = item
		buy.pressed.connect(func(): _ask(it))
		right.add_child(buy)
		row.add_child(right)
		_col.add_child(row)
	reset_size()


func _ask(item: String) -> void:
	var price: float = home_ui.main.home.PRICES[item]
	var left: float = home_ui.main.harmony.points - price
	home_ui.main.hud.confirm(tr("shop_title"), tr("shop_confirm") % [_name(item), num(price), num(left)],
		tr("shop_buy"), func(): _buy(item))


func _buy(item: String) -> void:
	var m = home_ui.main
	var price: float = m.home.PRICES[item]
	if m.home.why_not(item, m.harmony.points) != "" or not m.home.buy(item):
		refresh()
		return
	m.harmony.points -= price
	m.harmony.save_purse()
	home_ui.rebuild_room()
	home_ui.toast(tr("shop_bought") % _name(item))
	refresh()


func _name(item: String) -> String:
	for r in ITEMS:
		if r[0] == item:
			return tr(r[1])
	return item
