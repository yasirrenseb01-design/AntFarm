extends VBoxContainer
## The side panel's Statistics tab (the keeper, 2026-11-03: "a Statistics tab - plot anything from the colony's status,
## pick the X and Y axes, name and save what I set, so I need not set it again, for every colony"): one value along X
## (the day, or any other), one or more along Y, each a line of its own colour, from the colony's day-by-day record
## (sim.history: a snapshot a day, the last three years - days recorded before v0.11.78 hold only the population and
## the stores). The sets saved are the keeper's, not a colony's: user://charts.json {"v": 1, "sets": [{name, x, ys,
## own}]} - only names and keys from the list below are taken from it.

const Paper := preload("res://scripts/view/ui/paper.gd")
const SafeFile := preload("res://scripts/game/safe_file.gd")
const Store := preload("res://scripts/game/save_store.gd")
const MAX_SETS := 40
const MAX_TEXT := 65536
# what can be plotted: the key in sim.history (sim_base._snapshot), its name (lang/strings.csv)
const KEYS := [["day", "stat_day"], ["workers", "panel_workers"], ["brood", "stat_brood"], ["eggs", "eggs"],
	["larvae", "larvae"], ["pupae", "pupae"], ["out", "panel_out"], ["nurses", "panel_nurses"], ["callow", "panel_callow"],
	["sugar", "panel_sugar"], ["protein", "panel_protein"], ["fat", "panel_fat"], ["nest_t", "panel_nest_temp"],
	["air", "stat_air"], ["hum", "panel_humidity"], ["water", "stat_water"], ["dev", "panel_dev"], ["dead", "panel_dead"],
	["brood_dead", "panel_brood_dead"], ["vol", "panel_volume"], ["depth", "panel_depth"], ["size", "panel_size"]]
const COLOURS := [Color(0.66, 0.33, 0.03), Color(0.16, 0.11, 0.07), Color(0.2, 0.38, 0.14), Color(0.25, 0.4, 0.7),
	Color(0.62, 0.2, 0.1), Color(0.5, 0.3, 0.6), Color(0.15, 0.5, 0.5), Color(0.45, 0.4, 0.15)]
const DEFAULT_SET := {"name": "", "x": "day", "ys": ["workers", "brood"], "own": false}

var sim
var hud                          # (its helpers: _label, _button)
var x_key := "day"
var y_keys: Array = ["workers", "brood"]
var own_scale := false           # each line on its own scale (values of different sizes: workers and the nest's warmth)
var sets: Array = []             # the keeper's saved sets
var _x_pick: OptionButton
var _y_boxes := {}               # key -> CheckBox
var _own_box: CheckBox
var _canvas: Control
var _legend: RichTextLabel       # each line's name and today's value, a dot in its colour
var _set_pick: OptionButton
var _name_edit: LineEdit
var _days_n := -1                # the record's length when last drawn


static func path() -> String:
	return Store.base + "charts.json"


func setup(s, h) -> void:
	sim = s
	hud = h
	add_theme_constant_override("separation", 6)
	_load_sets()
	# the saved sets: pick one to use it; a name and Save keeps what is set now; Delete takes the picked one away
	var srow := HBoxContainer.new()
	srow.add_child(hud._label(tr("stat_sets"), 12, hud.MUTED))
	_set_pick = OptionButton.new()
	_set_pick.focus_mode = Control.FOCUS_NONE
	_set_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_pick.item_selected.connect(_use_set)
	srow.add_child(_set_pick)
	var del: Button = hud._button(tr("stat_delete"), false)
	del.pressed.connect(_delete_set)
	srow.add_child(del)
	add_child(srow)
	var nrow := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = tr("stat_name_hint")
	_name_edit.max_length = 40
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(_name_edit)
	var save: Button = hud._button(tr("stat_save"), false)
	save.pressed.connect(_save_set)
	nrow.add_child(save)
	add_child(nrow)

	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(0, 200)
	_canvas.draw.connect(_draw)
	add_child(_canvas)
	_legend = RichTextLabel.new()
	_legend.bbcode_enabled = true
	_legend.fit_content = true
	_legend.scroll_active = false
	_legend.add_theme_font_size_override("normal_font_size", 12)
	_legend.add_theme_color_override("default_color", hud.INK)
	add_child(_legend)
	_own_box = CheckBox.new()
	_own_box.text = tr("stat_own_scale")
	_own_box.focus_mode = Control.FOCUS_NONE
	_own_box.add_theme_font_size_override("font_size", 12)
	_own_box.toggled.connect(func(on):
		own_scale = on
		redraw())
	add_child(_own_box)

	var xrow := HBoxContainer.new()
	xrow.add_child(hud._label(tr("stat_x"), 13, hud.MUTED))
	_x_pick = OptionButton.new()
	_x_pick.focus_mode = Control.FOCUS_NONE
	_x_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in KEYS:
		_x_pick.add_item(tr(k[1]))
	_x_pick.item_selected.connect(func(i):
		x_key = KEYS[i][0]
		redraw())
	xrow.add_child(_x_pick)
	add_child(xrow)
	add_child(hud._label(tr("stat_y"), 13, hud.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("v_separation", 0)
	for k in KEYS:
		if k[0] == "day":
			continue
		var cb := CheckBox.new()
		cb.text = tr(k[1])
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 12)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = k[0]
		cb.toggled.connect(func(on):
			if on and not y_keys.has(key):
				y_keys.append(key)
			elif not on:
				y_keys.erase(key)
			redraw())
		grid.add_child(cb)
		_y_boxes[key] = cb
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	add_child(scroll)
	_fill_sets(0)
	_apply(DEFAULT_SET)


## Shows a set's axes in the pickers (without each one redrawing).
func _apply(st: Dictionary) -> void:
	x_key = String(st.x)
	y_keys = (st.ys as Array).duplicate()
	own_scale = bool(st.get("own", false))
	for i in KEYS.size():
		if KEYS[i][0] == x_key:
			_x_pick.select(i)
	for k in _y_boxes:
		_y_boxes[k].set_pressed_no_signal(y_keys.has(k))
	_own_box.set_pressed_no_signal(own_scale)
	redraw()


func redraw() -> void:
	_days_n = -1
	_canvas.queue_redraw()


## Called by the HUD now and then: drawn again once there is a new day in the record.
func refresh() -> void:
	if is_visible_in_tree() and sim.history.size() != _days_n:
		_canvas.queue_redraw()


func _name_of(key: String) -> String:
	for k in KEYS:
		if k[0] == key:
			return tr(k[1])
	return key


## The record, and today as its last point.
func _points() -> Array:
	var pts: Array = sim.history.duplicate()
	var now: Dictionary = sim._snapshot()
	pts.append(now)
	return pts


func _draw() -> void:
	var c := _canvas
	var font := c.get_theme_default_font()
	var pts := _points()
	_days_n = sim.history.size()
	var w := c.size.x
	var h := c.size.y
	var left := 34.0
	var bottom := h - 16.0
	var top := 6.0
	c.draw_rect(Rect2(left, top, w - left - 2.0, bottom - top), Color(1, 1, 1, 0.12))
	# only the days that have the X value and one of the Y values: a value recorded only from v0.11.78 has no line
	# over the days before it (the keeper, 2026-11-03: one dot at the right end of 370 days - "is the chart right?")
	var kept := []
	for p in pts:
		if (p as Dictionary).has(x_key) and y_keys.any(func(k): return (p as Dictionary).has(k)):
			kept.append(p)
	pts = kept
	var xs := []
	for p in pts:
		xs.append(float(p[x_key]))
	if xs.size() < 2 or y_keys.is_empty():
		var why := tr("stat_no_data") if y_keys.is_empty() or sim.history.size() < 2 else tr("stat_new_value")
		var lines := why.split("\n")
		for li in lines.size():
			c.draw_string(font, Vector2(left + 8, h * 0.5 + li * 16 - 8), lines[li], HORIZONTAL_ALIGNMENT_LEFT, w - left - 12, 12, hud.MUTED)
		_legend.text = ""
		return
	var x0: float = xs.min()
	var x1: float = xs.max()
	if x1 - x0 < 0.0001:
		x1 = x0 + 1.0
	# Y: one scale for all (from 0 when nothing is below it), or each its own
	var ranges := {}
	var all_lo := INF
	var all_hi := -INF
	for k in y_keys:
		var lo := INF
		var hi := -INF
		for p in pts:
			if (p as Dictionary).has(k) and (p as Dictionary).has(x_key):
				lo = minf(lo, float(p[k]))
				hi = maxf(hi, float(p[k]))
		if lo == INF:
			continue
		lo = minf(lo, 0.0)
		if hi - lo < 0.0001:
			hi = lo + 1.0
		ranges[k] = Vector2(lo, hi)
		all_lo = minf(all_lo, lo)
		all_hi = maxf(all_hi, hi)
	var shared := not own_scale or y_keys.size() == 1
	if shared and all_lo != INF:
		for v in [all_lo, (all_lo + all_hi) * 0.5, all_hi]:
			var y: float = bottom - (float(v) - all_lo) / (all_hi - all_lo) * (bottom - top)
			c.draw_line(Vector2(left, y), Vector2(w - 2.0, y), hud.LINE * Color(1, 1, 1, 0.5), 1.0)
			c.draw_string(font, Vector2(0, y + 4), _num(v), HORIZONTAL_ALIGNMENT_LEFT, left - 3, 10, hud.MUTED)
	c.draw_string(font, Vector2(left, h), _num(x0), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, hud.MUTED)
	c.draw_string(font, Vector2(w - 90, h), _num(x1), HORIZONTAL_ALIGNMENT_RIGHT, 88, 10, hud.MUTED)
	var legend := PackedStringArray()
	var by_day := x_key == "day"
	for ci in y_keys.size():
		var k: String = y_keys[ci]
		if not ranges.has(k):
			continue
		var r: Vector2 = Vector2(all_lo, all_hi) if shared else ranges[k]
		var col: Color = COLOURS[ci % COLOURS.size()]
		var line := []
		for p in pts:
			if (p as Dictionary).has(k) and (p as Dictionary).has(x_key):
				line.append(Vector2(left + (float(p[x_key]) - x0) / (x1 - x0) * (w - left - 4.0),
					bottom - (float(p[k]) - r.x) / (r.y - r.x) * (bottom - top)))
		if not by_day:
			line.sort_custom(func(a, b): return a.x < b.x)
			for q in line:
				c.draw_circle(q, 2.0, col)
		if line.size() >= 2:
			c.draw_polyline(PackedVector2Array(line), col * Color(1, 1, 1, 1.0 if by_day else 0.45), 2.0 if by_day else 1.0, true)
		if not line.is_empty() and by_day:
			c.draw_circle(line[line.size() - 1], 3.0, col)
		var last: Dictionary = pts[pts.size() - 1]
		legend.append("[color=#%s]●[/color] %s %s%s" % [col.to_html(false), _name_of(k), _num(float(last.get(k, 0.0))),
			"" if shared else " (%s–%s)" % [_num(r.x), _num(r.y)]])
	_legend.text = "\n".join(legend)


static func _num(v: float) -> String:
	if absf(v) >= 100.0 or is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return "%.1f" % v


# ---------------------------------------------------------------- the saved sets

func _fill_sets(select: int) -> void:
	_set_pick.clear()
	_set_pick.add_item(tr("stat_default"))
	for st in sets:
		_set_pick.add_item(String(st.name))
	_set_pick.select(clampi(select, 0, sets.size()))


func _use_set(i: int) -> void:
	if i == 0:
		_apply(DEFAULT_SET)
		_name_edit.text = ""
	elif i - 1 < sets.size():
		_apply(sets[i - 1])
		_name_edit.text = String(sets[i - 1].name)


func _save_set() -> void:
	var nm := _name_edit.text.strip_edges()
	if nm == "" or y_keys.is_empty():
		return
	var st := {"name": nm, "x": x_key, "ys": y_keys.duplicate(), "own": own_scale}
	var at := -1
	for i in sets.size():
		if String(sets[i].name) == nm:
			at = i
	if at >= 0:
		sets[at] = st                    # (the same name: saved over)
	elif sets.size() < MAX_SETS:
		sets.append(st)
		at = sets.size() - 1
	else:
		return
	_write_sets()
	_fill_sets(at + 1)


func _delete_set() -> void:
	var i := _set_pick.selected - 1
	if i < 0 or i >= sets.size():
		return
	sets.remove_at(i)
	_write_sets()
	_fill_sets(0)
	_use_set(0)


func _load_sets() -> void:
	sets = []
	# (only names and known keys are taken: nothing in it is run; a file cut short: its .bak - game/safe_file.gd)
	var d = SafeFile.read_text(path(), MAX_TEXT, func(t: String):
		var v = JSON.parse_string(t)
		return v if v is Dictionary and v.get("sets") is Array else null)
	if d == null:
		return
	var known := KEYS.map(func(k): return k[0])
	for st in d.sets:
		if sets.size() >= MAX_SETS or not st is Dictionary:
			continue
		var nm = st.get("name")
		var x = st.get("x")
		var ys = st.get("ys")
		if not nm is String or nm.strip_edges() == "" or not x is String or not known.has(x) or not ys is Array:
			continue
		var keep := []
		for y in ys:
			if y is String and known.has(y) and y != "day" and not keep.has(y):
				keep.append(y)
		if keep.is_empty():
			continue
		sets.append({"name": nm.left(40), "x": x, "ys": keep, "own": st.get("own") == true})


func _write_sets() -> void:
	SafeFile.write_text(path(), JSON.stringify({"v": 1, "sets": sets}))
