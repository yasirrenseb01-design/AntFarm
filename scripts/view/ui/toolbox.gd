extends RefCounted
## The keeper's toolbox along the foot of the screen (v0.13.14, the keeper chose: "a tray with a tab for each kind of
## thing, a drawn icon and a short name in each slot, the on/off switches apart on the right"). Replaces the long row of
## buttons (hud_controls.gd _build_tools until v0.13.13).
##   [ hand | (Food | In the box) tabs over that kind's slots ]  [ Add water ] [ Heat mat ] [ Fridge ]  [ Scent ] [ X-ray ]
## The things to put in the box are a ButtonGroup of Slots (ground.tool); the switches are Switches (brass toggles with
## a lamp); in the nest view the slots give way to the cut-plane slider.

const Desk := preload("res://scripts/view/ui/desk.gd")
const DeskControls := preload("res://scripts/view/ui/desk_controls.gd")
const FoodKinds := preload("res://scripts/sim/food_kinds.gd")
const T := preload("res://scripts/sim/text_th.gd")
const INK := Color(0.2, 0.13, 0.08)
const PAPER := Color(0.95, 0.9, 0.78)

## which tab each thing is under, its short name (lang: tb_*) and icon
const TABS := [["food", "tb_food"], ["items", "tb_items"]]
const SHORT := {"pan": "tb_pan", "honey": "tb_honey", "cricket": "tb_cricket", "rock": "tb_rock", "rock_take": "tb_rock_take",
	"erase": "tb_erase"}


static func build(h, root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 14
	panel.offset_top = -110
	panel.offset_bottom = -12
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", Desk.TrayBox.new(14, 10))
	root.add_child(panel)
	h._tools_bar = panel
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	# ---- the things put in the box: the hand, then a tab for each kind
	var put := HBoxContainer.new()
	put.add_theme_constant_override("separation", 6)
	row.add_child(put)
	h._outside_tools.append(put)
	var g := ButtonGroup.new()
	var hand := Slot.new("pan", h.tr("tb_pan"), h.tr("tool_pan"), g)
	hand.button_pressed = h.ground.tool == "pan"
	hand.pressed.connect(func(): h.ground.tool = "pan")
	put.add_child(hand)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	put.add_child(right)
	var strap = DeskControls.ViewStrap.new()
	strap.modes = ["food", "items"]
	strap.words = [h.tr("tb_food"), h.tr("tb_items")]
	strap.icons = ["food", "stone"]
	strap.mode = "food"
	strap.font = h._serif
	strap.custom_minimum_size = Vector2(250, 26)
	right.add_child(strap)
	var shelves := {}
	for t in TABS:
		var shelf := HBoxContainer.new()
		shelf.add_theme_constant_override("separation", 6)
		shelf.visible = t[0] == "food"
		right.add_child(shelf)
		shelves[t[0]] = shelf
	strap.chosen.connect(func(m):
		for k in shelves:
			shelves[k].visible = k == m)
	var things := []
	for pair in FoodKinds.tools():
		things.append(["food", pair[1], pair[0]])
	for pair in [["rock", "tool_rock"], ["rock_take", "tool_rock_take"], ["erase", "tool_erase"]]:
		things.append(["items", pair[0], pair[1]])
	for th in things:
		var key: String = th[1]
		var b := Slot.new(key, h.tr(SHORT.get(key, th[2])), h.tr(th[2]), g)
		b.button_pressed = h.ground.tool == key
		b.pressed.connect(func(): h.ground.tool = key)
		shelves[th[0]].add_child(b)
		if th[0] == "food" and not h.guide_targets.has("food"):
			h.guide_targets["food"] = b

	# ---- in the nest view: the cut plane's slider instead
	h._cut_row = HBoxContainer.new()
	h._cut_row.visible = false
	h._cut_row.add_child(h._label(h.tr("cut_plane"), 12, Color(0.95, 0.86, 0.7)))
	var cut := HSlider.new()
	h._cut_slider = cut
	cut.min_value = -32
	cut.max_value = 32
	cut.step = 0.5
	cut.custom_minimum_size = Vector2(220, 0)
	cut.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cut.focus_mode = Control.FOCUS_NONE
	cut.value_changed.connect(func(v): if h.nest_view: h.nest_view.cut_offset = v)
	h._cut_row.add_child(cut)
	row.add_child(h._cut_row)

	# ---- the switches, apart on the right: the nest's care, then what is shown
	var sep := VSeparator.new()
	row.add_child(sep)
	h._outside_tools.append(sep)              # (in the nest view nothing is left of it to part off)
	var keeper: bool = h.sim.scenario == "keeper"
	var water := Slot.new("water", h.tr("tb_water"), h.tr("add_water"), null)
	water.toggle_mode = false
	h.guide_targets["water"] = water
	water.pressed.connect(func():
		var before: float = h.sim.water
		h.sim.add_water()
		h.water_given.emit(before))
	water.visible = keeper                    # outdoors the rain waters the nest
	row.add_child(water)
	var heat := Switch.new("heat", h.tr("tb_heat"), h.tr("heater"))
	heat.button_pressed = h.sim.heater        # a colony saved with the mat on loads with it on (set before connecting)
	heat.toggled.connect(func(on):
		h.sim.heater = on
		h.sim._log(T.heater_on if on else T.heater_off))
	heat.visible = keeper                     # outdoors there is no heat mat
	row.add_child(heat)
	var cold := Switch.new("fridge", h.tr("tb_fridge"), h.tr("fridge"))
	cold.button_pressed = h.sim.fridge_on
	cold.toggled.connect(func(on):
		var other: String = h._fridge_taken() if on else ""
		if other != "":
			# the Home's fridge holds two tanks: other colonies are resting in it
			cold.set_pressed_no_signal(false)
			h.call("_named_news", h.tr("fridge_full") % other)
			return
		h.sim.fridge_on = on
		h.sim._log(T.fridge_in if on else T.fridge_out))
	cold.visible = keeper                     # outdoors winter comes by itself
	row.add_child(cold)
	row.add_child(VSeparator.new())
	var pher := Switch.new("scent", h.tr("tb_scent"), h.tr("show_scent"))
	pher.button_pressed = h.ground.show_pheromones
	pher.toggled.connect(func(on): h.ground.show_pheromones = on)
	row.add_child(pher)
	h._outside_tools.append(pher)
	h._xray_btn = Switch.new("xray", h.tr("tb_xray"), h.tr("xray"))
	h._xray_btn.visible = false
	h._xray_btn.toggled.connect(func(on):
		if h.nest_view:
			h.nest_view.set_xray(on)
		h._cut_row.visible = not on and not h.sim.nest.slab)
	row.add_child(h._xray_btn)
	h._xray_btn.button_pressed = true          # (the nest seen through the soil from the start)

	h._hint = h._label("", 12, Color(1, 1, 1, 0.85))     # (over the scene, not on paper: light, with a shadow)
	h._hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	h._hint.add_theme_constant_override("shadow_offset_x", 1)
	h._hint.add_theme_constant_override("shadow_offset_y", 1)
	h._hint.anchor_top = 1.0
	h._hint.anchor_bottom = 1.0
	h._hint.offset_left = 18
	root.add_child(h._hint)
	var place_hint := func():
		h._hint.offset_top = panel.offset_top - 24.0
		h._hint.offset_bottom = panel.offset_top - 6.0
	panel.resized.connect(place_hint)
	place_hint.call()


## The icons, drawn as a pencil sketch: ink lines, a little colour.
static func icon(ci: CanvasItem, kind: String, c: Vector2, s: float, on := false) -> void:
	var ink := INK
	match kind:
		"pan":                          # an open hand
			var palm := PackedVector2Array()
			for k in 12:
				var a := TAU * k / 12.0
				palm.append(c + Vector2(cos(a) * 6.0, sin(a) * 6.5 + 4.0) * s)
			ci.draw_colored_polygon(palm, Color(0.96, 0.84, 0.7))
			for f in 4:
				var x := (-4.5 + f * 3.0) * s
				var top := (-10.0 + absf(f - 1.5) * 1.6) * s
				ci.draw_line(c + Vector2(x, 0), c + Vector2(x, top), Color(0.96, 0.84, 0.7), 2.6 * s, true)
				ci.draw_line(c + Vector2(x - 1.3 * s, 0), c + Vector2(x - 1.3 * s, top), ink, 0.8, true)
				ci.draw_line(c + Vector2(x + 1.3 * s, 0), c + Vector2(x + 1.3 * s, top), ink, 0.8, true)
				ci.draw_arc(c + Vector2(x, top), 1.3 * s, PI, TAU, 6, ink, 0.8, true)
			ci.draw_line(c + Vector2(6.0, 4.0) * s, c + Vector2(10.0, -1.0) * s, Color(0.96, 0.84, 0.7), 2.6 * s, true)
			ci.draw_polyline(palm, ink, 0.9, true)
		"honey", "food":                # a drop of honey
			var drop := PackedVector2Array()
			for k in 16:
				var a := TAU * k / 16.0
				var p := Vector2(sin(a) * 6.0, -cos(a) * 6.0)
				if p.y < 0.0:
					p.x *= 1.0 + p.y / 7.0
					p.y *= 1.7
				drop.append(c + (p + Vector2(0, 2.5)) * s)
			ci.draw_colored_polygon(drop, Color(0.9, 0.58, 0.1))
			drop.append(drop[0])
			ci.draw_polyline(drop, ink, 0.9, true)
			ci.draw_circle(c + Vector2(-2.0, 3.0) * s, 1.4 * s, Color(1, 0.92, 0.6), true, -1.0, true)
		"cricket":                      # a cricket from the side, its big hind leg
			ci.draw_set_transform(c + Vector2(-1, 1) * s, -0.15, Vector2(1.0, 0.45))
			ci.draw_circle(Vector2.ZERO, 7.0 * s, Color(0.4, 0.27, 0.14), true, -1.0, true)
			ci.draw_arc(Vector2.ZERO, 7.0 * s, 0, TAU, 16, ink, 0.9, true)
			ci.draw_set_transform(Vector2.ZERO)
			ci.draw_circle(c + Vector2(6.5, -1) * s, 2.6 * s, Color(0.3, 0.2, 0.1), true, -1.0, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-2, 1) * s, c + Vector2(-6, -6) * s, c + Vector2(-9, 5) * s]), ink, 1.1, true)
			ci.draw_line(c + Vector2(8, -2) * s, c + Vector2(13, -9) * s, ink, 0.7, true)
			ci.draw_line(c + Vector2(8, -2) * s, c + Vector2(14, -5) * s, ink, 0.7, true)
			for k in 2:
				ci.draw_line(c + Vector2(2 + k * 3, 3) * s, c + Vector2(1 + k * 4, 7) * s, ink, 0.8, true)
		"rock", "stone", "rock_take":   # a stone (taken: lifted, an arrow up)
			var up := Vector2(0, -2.5) if kind == "rock_take" else Vector2(0, 1.0)
			var st := PackedVector2Array([Vector2(-8, 3), Vector2(-6, -3), Vector2(-1, -6), Vector2(5, -5), Vector2(8, 0),
				Vector2(6, 5), Vector2(-3, 6)])
			for k in st.size():
				st[k] = c + (st[k] + up) * s
			ci.draw_colored_polygon(st, Color(0.6, 0.58, 0.54))
			ci.draw_line(st[1] + Vector2(2, 1) * s, st[3] + Vector2(-1, 2) * s, Color(0.85, 0.84, 0.8), 1.2, true)
			st.append(st[0])
			ci.draw_polyline(st, ink, 0.9, true)
			if kind == "rock_take":
				ci.draw_line(c + Vector2(10, 7) * s, c + Vector2(10, -6) * s, Color(0.55, 0.15, 0.1), 1.4, true)
				ci.draw_polyline(PackedVector2Array([c + Vector2(7, -3) * s, c + Vector2(10, -7) * s, c + Vector2(13, -3) * s]),
					Color(0.55, 0.15, 0.1), 1.4, true)
		"erase":                        # a cloth wiping a scent trail away
			for k in 3:
				var y := (-3.0 + k * 3.5) * s
				ci.draw_polyline(PackedVector2Array([c + Vector2(-11, y), c + Vector2(-7, y - 2 * s), c + Vector2(-3, y)]),
					Color(0.8, 0.55, 0.2, 0.45), 1.2, true)
			var cl := PackedVector2Array([c + Vector2(-1, -6) * s, c + Vector2(9, -7) * s, c + Vector2(11, 4) * s, c + Vector2(0, 6) * s])
			ci.draw_colored_polygon(cl, Color(0.7, 0.82, 0.88))
			cl.append(cl[0])
			ci.draw_polyline(cl, ink, 0.9, true)
			ci.draw_line(c + Vector2(2, -3) * s, c + Vector2(8, -3.5) * s, ink * Color(1, 1, 1, 0.5), 0.7, true)
		"water":                        # a drop of water over a wet line
			var dw := PackedVector2Array()
			for k in 16:
				var a := TAU * k / 16.0
				var p := Vector2(sin(a) * 5.5, -cos(a) * 5.5)
				if p.y < 0.0:
					p.x *= 1.0 + p.y / 6.5
					p.y *= 1.8
				dw.append(c + (p + Vector2(0, 1.5)) * s)
			ci.draw_colored_polygon(dw, Color(0.35, 0.62, 0.88))
			dw.append(dw[0])
			ci.draw_polyline(dw, ink, 0.9, true)
			ci.draw_circle(c + Vector2(-1.8, 2.5) * s, 1.3 * s, Color(0.85, 0.95, 1.0), true, -1.0, true)
			ci.draw_line(c + Vector2(-9, 9) * s, c + Vector2(9, 9) * s, Color(0.35, 0.55, 0.75, 0.7), 1.2, true)
		"heat":                         # a mat with heat rising
			ci.draw_rect(Rect2(c + Vector2(-9, 4) * s, Vector2(18, 4) * s), Color(0.55, 0.2, 0.12) if on else Color(0.45, 0.35, 0.3))
			for k in 3:
				var x := (-5.0 + k * 5.0) * s
				ci.draw_polyline(PackedVector2Array([c + Vector2(x, 2 * s), c + Vector2(x + 2 * s, -2 * s), c + Vector2(x, -5 * s),
					c + Vector2(x + 2 * s, -9 * s)]), Color(0.85, 0.3, 0.1) if on else ink, 1.1, true)
		"fridge":                       # a snowflake
			var col := Color(0.25, 0.5, 0.8) if on else ink
			for k in 3:
				var d := Vector2.from_angle(PI / 3.0 * k) * 8.0 * s
				ci.draw_line(c - d, c + d, col, 1.2, true)
				for e in [-1.0, 1.0]:
					var tip: Vector2 = c + d * e * 0.6
					ci.draw_line(tip, tip + d.rotated(0.8) * e * 0.3, col, 0.9, true)
					ci.draw_line(tip, tip + d.rotated(-0.8) * e * 0.3, col, 0.9, true)
		"scent":                        # wavy scent lines
			for k in 3:
				var pts := PackedVector2Array()
				for j in 9:
					var x := (-9.0 + j * 2.25) * s
					pts.append(c + Vector2(x, (-5.0 + k * 5.0) * s + sin(j * 1.2 + k) * 1.8 * s))
				ci.draw_polyline(pts, Color(0.85, 0.5, 0.1) if on else ink, 1.1, true)
		"xray":                         # an eye over the soil's layers
			for k in 3:
				ci.draw_line(c + Vector2(-9, 3 + k * 2.5) * s, c + Vector2(9, 3 + k * 2.5) * s, Color(0.45, 0.3, 0.18, 0.8), 1.0, true)
			ci.draw_set_transform(c + Vector2(0, -3) * s, 0.0, Vector2(1.0, 0.55))
			ci.draw_circle(Vector2.ZERO, 7.0 * s, Color(1, 1, 1, 0.9), true, -1.0, true)
			ci.draw_arc(Vector2.ZERO, 7.0 * s, 0, TAU, 16, ink, 1.0, true)
			ci.draw_set_transform(Vector2.ZERO)
			ci.draw_circle(c + Vector2(0, -3) * s, 2.4 * s, Color(0.3, 0.45, 0.6) if on else ink, true, -1.0, true)


## A slot of the tray: a paper card with the thing's icon and its short name; picked, it sits up with a brass edge.
class Slot extends Button:
	var kind := ""
	var word := ""

	func _init(k: String, short: String, tip: String, group: ButtonGroup) -> void:
		kind = k
		word = short
		tooltip_text = tip
		toggle_mode = group != null
		button_group = group
		focus_mode = Control.FOCUS_NONE
		flat = true
		custom_minimum_size = Vector2(62, 54)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
			queue_redraw()

	func _draw() -> void:
		var on := button_pressed and toggle_mode
		var down := is_pressed() and not toggle_mode and get_draw_mode() == DRAW_PRESSED
		var lift := -2.0 if on else (1.0 if down else 0.0)
		var r := Rect2(Vector2(2, 2 + lift), size - Vector2(4, 4))
		var sh := Rect2(r.position + Vector2(1.5, 2.5 - lift), r.size)
		Desk.poly(get_canvas_item(), Desk.round_rect(sh, 5), Color(0, 0, 0, 0.35 if on else 0.22))
		var card := Desk.round_rect(r, 5)
		var hover := is_hovered()
		Desk.poly_tex(get_canvas_item(), card, Desk.paper(), 128.0, Color(1.06, 1.04, 1.0) if hover or on else Color(0.96, 0.94, 0.9))
		if on:
			Desk.outline(get_canvas_item(), card, Desk.BRASS_LIGHT, 2.0)
			Desk.outline(get_canvas_item(), Desk.round_rect(r.grow(-2), 4), Desk.BRASS_DARK, 1.0)
		else:
			Desk.outline(get_canvas_item(), card, Color(0.4, 0.28, 0.15, 0.7), 1.0)
		var Box = load("res://scripts/view/ui/toolbox.gd")
		Box.icon(self, kind, Vector2(size.x * 0.5, r.position.y + 20.0), 1.2, on)
		var font := get_theme_default_font()
		draw_string(font, Vector2(r.position.x, r.end.y - 6.0), word, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, INK)


## An on/off switch: a brass plate, its lever up (on) or down, a lamp lit while on, the icon and short name beside.
class Switch extends Button:
	var kind := ""
	var word := ""

	func _init(k: String, short: String, tip: String) -> void:
		kind = k
		word = short
		tooltip_text = tip
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		flat = true
		custom_minimum_size = Vector2(62, 54)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		toggled.connect(func(_on): queue_redraw())

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
			queue_redraw()

	func _draw() -> void:
		var ci := get_canvas_item()
		var on := button_pressed
		var plate := Rect2(Vector2(4, 3), Vector2(size.x - 8, 30))
		Desk.poly(ci, Desk.round_rect(Rect2(plate.position + Vector2(1.5, 2), plate.size), 5), Color(0, 0, 0, 0.3))
		Desk.brass(ci, Desk.round_rect(plate, 5))
		if is_hovered():
			Desk.poly(ci, Desk.round_rect(plate, 5), Color(1, 1, 1, 0.12))
		# the icon on the plate's left, the lever on its right with its lamp
		var Box = load("res://scripts/view/ui/toolbox.gd")
		Box.icon(self, kind, Vector2(plate.position.x + 15.0, plate.get_center().y), 0.75, on)
		var base := Vector2(plate.end.x - 14.0, plate.get_center().y)
		draw_circle(base, 4.0, Desk.BRASS_DARK, true, -1.0, true)
		var tip := base + Vector2(0, -10.0 if on else 10.0).rotated(0.25 if on else -0.25)
		draw_line(base, tip, Color(0.25, 0.2, 0.15), 3.0, true)
		draw_circle(tip, 2.6, Color(0.12, 0.1, 0.08), true, -1.0, true)
		var lamp := Vector2(plate.end.x - 26.0, plate.position.y + 7.0)
		draw_circle(lamp, 3.0, Color(0.45, 0.95, 0.4) if on else Color(0.2, 0.25, 0.18), true, -1.0, true)
		if on:
			draw_circle(lamp, 5.0, Color(0.45, 0.95, 0.4, 0.25), true, -1.0, true)
		var font := get_theme_default_font()
		draw_string(font, Vector2(0, size.y - 5.0), word, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(0.97, 0.9, 0.75))
