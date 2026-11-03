extends PanelContainer
## The Home's water card (the keeper, 2026-11-03: "fill the water from the Home - see each tank's water going down, and
## fill many tanks at once without going in and out"): on the left of the room, each tank with a colony, its water tank's
## level and a button to fill it; "Fill all" once there are two or more. The colony open in the game (it runs on behind
## the Home) is filled at once; the others are not running - the time goes in their slotN.json (save_store.add_refill)
## and the time away fills it at that moment when the colony is opened. Their level here is worked out from their last
## save (save_store.water_now). Filling a tank that was under 30 % pays Colony Harmony (harmony.gd pay_water).

const Paper := preload("res://scripts/view/ui/paper.gd")
const Store := preload("res://scripts/game/save_store.gd")
const LOW := 0.15                # under this the bar turns red (the colony's own warning: sim_colony "lowwater")

var home_ui                      # game/home.gd
var _col: VBoxContainer
var _bars := {}                  # slot -> [ProgressBar, Label]
var _t := 0.0


func setup(ui) -> void:
	home_ui = ui
	add_theme_stylebox_override("panel", Paper.page(14, 10))
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 20
	offset_top = -44
	offset_bottom = -44
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 4)
	add_child(_col)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t -= delta
	if _t <= 0.0:
		_t = 1.0
		_levels()


## The tanks with a colony: [{"slot", "number"}], as the Home places them.
func _tanks() -> Array:
	var out := []
	for p in home_ui.main.home.places():
		if Store.exists(int(p.slot)) or _live(int(p.slot)):
			out.append({"slot": int(p.slot), "number": int(p.number)})
	return out


## The colony open in the game, running behind the Home (its water read from the simulation itself).
func _live(slot: int) -> bool:
	var m = home_ui.main
	return slot == m.slot and m.sim != null and not m._demo and m.sim.scenario == "keeper"


func level(slot: int) -> float:
	var m = home_ui.main
	if _live(slot):
		return m.sim.water
	return Store.water_now(Store.meta(slot), Store.away_rate(int(m._settings.get("away", 3))), bool(m._settings.get("care", true)))


## Built again each time the Home opens (tanks bought, colonies started).
func refresh() -> void:
	var h = home_ui.main.hud
	for c in _col.get_children():
		c.free()
	_bars.clear()
	var tanks := _tanks()
	visible = not tanks.is_empty()
	if tanks.is_empty():
		return
	_col.add_child(h._label(tr("home_water"), 14, Paper.ACCENT))
	for t in tanks:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(h._label(tr("home_water_tank") % t.number, 13, Paper.INK))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(110, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.001
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.45, 0.36, 0.26, 0.35)
		bg.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", bg)
		row.add_child(bar)
		var pct: Label = h._label("", 12, Paper.PENCIL)
		pct.custom_minimum_size.x = 38
		row.add_child(pct)
		var b: Button = h._button(tr("home_water_fill"), false)
		var s: int = t.slot
		var n: int = t.number
		b.pressed.connect(func(): fill([s], [n]))
		row.add_child(b)
		_col.add_child(row)
		_bars[s] = [bar, pct]
	if tanks.size() >= 2:
		var all: Button = h._button(tr("home_water_all"), false)
		all.pressed.connect(func():
			fill(tanks.map(func(x): return x.slot), tanks.map(func(x): return x.number)))
		_col.add_child(all)
	_levels()
	_place.call_deferred()


## Its foot above the help line, as tall as its rows (it grows up from there).
func _place() -> void:
	var h := get_combined_minimum_size().y
	offset_top = -44.0 - h
	offset_bottom = -44.0


func _levels() -> void:
	for s in _bars:
		var v := level(s)
		var bar: ProgressBar = _bars[s][0]
		bar.value = v
		var fill_sb := StyleBoxFlat.new()
		fill_sb.bg_color = Color(0.75, 0.2, 0.12) if v < LOW else Color(0.25, 0.5, 0.78)
		fill_sb.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill_sb)
		_bars[s][1].text = "%d%%" % roundi(v * 100.0)


## Fills those tanks' water (numbers: as the keeper knows them, for the note).
func fill(slots: Array, numbers: Array) -> void:
	var m = home_ui.main
	var got := 0.0
	var now := Time.get_unix_time_from_system()
	for s in slots:
		var before := level(s)
		if _live(s):
			m.sim.add_water()
		else:
			Store.add_refill(s, now)
		got += m.harmony.pay_water(s, before)
	_levels()
	var text: String = tr("home_water_done") % ", ".join(numbers.map(func(x): return str(x)))
	if got > 0.0:
		text += " · " + tr("water_paid") % int(got)
	home_ui.toast(text)
