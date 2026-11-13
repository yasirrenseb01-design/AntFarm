extends RefCounted
## The colony bar's other pieces in the desk look (ui/desk.gd): the leather strap that picks the view (outworld / nest)
## and the buttons as paper tags with a wax seal (the keeper's picture, 2026-11-12). Icons are drawn in code.

const D := preload("res://scripts/view/ui/desk.gd")


## A button as stitched leather (the side panel's tabs): cream words.
static func leather(b: Button) -> void:
	b.add_theme_stylebox_override("normal", D.LeatherBox.new(false, 12, 5, 7.0, Color(0.85, 0.83, 0.83)))
	b.add_theme_stylebox_override("hover", D.LeatherBox.new(false, 12, 5, 7.0, Color(1.0, 0.97, 0.95)))
	b.add_theme_stylebox_override("pressed", D.LeatherBox.new(true, 12, 5, 7.0))
	b.add_theme_stylebox_override("hover_pressed", D.LeatherBox.new(true, 12, 5, 7.0))
	for c in ["font_color", "font_hover_color"]:
		b.add_theme_color_override(c, Color(0.9, 0.8, 0.64))
	for c in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color(1.0, 0.94, 0.8))


## A button as a paper tag (the tray's tools, the camera's): honey-washed when on.
static func tag(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, D.TagBox.new(st, 10, 5))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, D.INK)


## A wax seal's icon, drawn at c in a seal of radius r (light on the wax).
static func icon(ci: CanvasItem, kind: String, c: Vector2, r: float, col: Color) -> void:
	var s := r / 10.0
	match kind:
		"enemy":                                 # a spider, struck through
			ci.draw_circle(c + Vector2(-1.5, 0) * s, 2.4 * s, col, true, -1.0, true)
			ci.draw_circle(c + Vector2(2.5, 0) * s, 3.0 * s, col, true, -1.0, true)
			for k in 4:
				var a := -0.9 + 0.6 * k
				for sd in [-1.0, 1.0]:
					var p0 := c + Vector2(-1.0 * s, 0)
					var kn := p0 + Vector2(cos(a) * 3.5, sd * (2.5 + abs(sin(a)) * 1.5)) * s
					ci.draw_polyline(PackedVector2Array([p0, kn, kn + Vector2(cos(a) * 2.5, sd * 2.5) * s]), col, 1.1 * s, true)
			ci.draw_line(c + Vector2(-6, 6) * s, c + Vector2(6, -6) * s, col, 1.6 * s, true)
		"ant":                                   # an ant from above
			for e in [[Vector2(-4.2, 0), Vector2(2.6, 2.0)], [Vector2(0.2, 0), Vector2(2.2, 1.3)], [Vector2(3.8, 0), Vector2(1.6, 1.5)]]:
				_oval(ci, c + e[0] * s, e[1] * s, col)
			for k in 3:
				for sd in [-1.0, 1.0]:
					var p0 := c + Vector2(0.2 + (k - 1) * 0.9, 0) * s
					var kn := p0 + Vector2((k - 1) * 2.2, sd * 3.0) * s
					ci.draw_polyline(PackedVector2Array([p0, kn, kn + Vector2((k - 1) * 1.6, sd * 2.4) * s]), col, 0.9 * s, true)
			for sd in [-1.0, 1.0]:
				ci.draw_polyline(PackedVector2Array([c + Vector2(5, sd * 0.8) * s, c + Vector2(7, sd * 2.5) * s, c + Vector2(8.5, sd * 2.0) * s]), col, 0.8 * s, true)
		"home":                                  # a house: the colonies kept
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -0.5) * s, c + Vector2(0, -6) * s, c + Vector2(6, -0.5) * s]), col)
			ci.draw_rect(Rect2(c + Vector2(-4.2, -1) * s, Vector2(8.4, 6.5) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-1.2, 1.8) * s, Vector2(2.4, 3.7) * s), col.darkened(0.6))
		"picture":                               # a framed picture: the wallpaper
			ci.draw_rect(Rect2(c + Vector2(-6, -4.5) * s, Vector2(12, 9) * s), col, false, 1.4 * s, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4.5, 3.2) * s, c + Vector2(-1.2, -1.5) * s, c + Vector2(1, 1) * s,
				c + Vector2(2.6, -0.5) * s, c + Vector2(4.5, 3.2) * s]), col)
			ci.draw_circle(c + Vector2(2.8, -2.3) * s, 1.1 * s, col, true, -1.0, true)
		"menu":                                  # three lines
			for k in 3:
				ci.draw_line(c + Vector2(-5, -3.5 + 3.5 * k) * s, c + Vector2(5, -3.5 + 3.5 * k) * s, col, 1.5 * s, true)
		"food", "stone":                         # the toolbox's tabs (ui/toolbox.gd draws them)
			load("res://scripts/view/ui/toolbox.gd").icon(ci, kind, c, r / 12.0)
		"ground":                                # the outworld: an ant over the ground, a blade of grass
			ci.draw_line(c + Vector2(-8, 4) * s, c + Vector2(8, 4) * s, col, 1.2 * s, true)
			for e in [[Vector2(-3.5, 1), Vector2(2.2, 1.6)], [Vector2(0, 1), Vector2(1.6, 1.0)], [Vector2(3, 0.6), Vector2(1.4, 1.3)]]:
				_oval(ci, c + e[0] * s, e[1] * s, col)
			for k in 3:
				var x := -1.5 + 1.5 * k
				ci.draw_line(c + Vector2(x - 0.5, 1.5) * s, c + Vector2(x - 1.5 + k, 4) * s, col, 0.8 * s, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(6.5, 4) * s, c + Vector2(6.0, -1) * s, c + Vector2(7.5, -4.5) * s]), col, 1.0 * s, true)
		"nest":                                  # the nest: a chamber under the ground with an ant in it
			ci.draw_line(c + Vector2(-8, -5) * s, c + Vector2(8, -5) * s, col, 1.2 * s, true)
			ci.draw_line(c + Vector2(-1, -5) * s, c + Vector2(0, -1.5) * s, col, 1.2 * s, true)
			ci.draw_arc(c + Vector2(0, 2) * s, 5.5 * s, PI * 1.05, TAU * 0.98, 16, col, 1.2 * s, true)
			ci.draw_line(c + Vector2(-5.5, 2) * s, c + Vector2(5.5, 2) * s, col, 1.2 * s, true)
			for e in [[Vector2(-2.2, 0.6), Vector2(1.5, 1.0)], [Vector2(0.2, 0.6), Vector2(1.0, 0.7)], [Vector2(2.2, 0.4), Vector2(1.0, 0.9)]]:
				_oval(ci, c + e[0] * s, e[1] * s, col)


static func _oval(ci: CanvasItem, c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 14:
		var a := TAU * k / 14.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	ci.draw_colored_polygon(pts, col)


## A wax seal: a round blob with a wavy edge, a pressed ring and the icon, lit from the top left.
static func seal(ci: CanvasItem, c: Vector2, r: float, wax: Color, kind: String, pressed := false) -> void:
	var edge := PackedVector2Array()
	for k in 36:
		var a := TAU * k / 36.0
		edge.append(c + Vector2.from_angle(a) * r * (1.0 + 0.06 * sin(a * 5.0 + 1.3) + 0.03 * sin(a * 11.0)))
	ci.draw_colored_polygon(D.moved(edge, Vector2(1.2, 2.0) if not pressed else Vector2(0.5, 1.0)), Color(0, 0, 0, 0.35))
	var cols := PackedColorArray()
	for p in edge:
		var u := clampf(((p - c).dot(Vector2(0.6, 0.8)) / r) * 0.5 + 0.5, 0.0, 1.0)
		cols.append(wax.lightened(0.25).lerp(wax.darkened(0.35), u))
	ci.draw_polygon(edge, cols)
	ci.draw_arc(c, r * 0.72, 0, TAU, 32, wax.darkened(0.4), 1.4, true)
	ci.draw_arc(c + Vector2(-0.6, -0.6), r * 0.72, PI * 0.9, PI * 1.6, 12, wax.lightened(0.35), 1.0, true)
	icon(ci, kind, c + Vector2(0, 0.5), r * 0.62, wax.lightened(0.55))


## A button as a paper tag with a wax seal at its left (the colony bar's Enemies, Top ants, My colonies...).
class SealButton extends Button:
	var kind := "menu"
	var wax := Color(0.6, 0.12, 0.1)

	func _init(k: String, w: Color) -> void:
		kind = k
		wax = w
		focus_mode = Control.FOCUS_NONE
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		clip_text = true
		text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		custom_minimum_size = Vector2(0, 32)
		var Desk = load("res://scripts/view/ui/desk.gd")
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var sb = Desk.TagBox.new(st, 6, 4)
			sb.content_margin_left = 31
			add_theme_stylebox_override(st, sb)
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			add_theme_color_override(c, Desk.INK)

	func _draw() -> void:
		var C = load("res://scripts/view/ui/desk_controls.gd")
		var r := 12.5
		C.seal(self, Vector2(14.0, size.y * 0.5 + (1.0 if button_pressed or is_pressed() else 0.0)), r, wax, kind, is_pressed())


## The leather strap that picks the view: two halves, the chosen one a raised piece with its icon and word.
class ViewStrap extends Control:
	signal chosen(mode: String)
	var modes: Array = ["outworld", "nest"]
	var words: Array = ["Outworld", "Nest"]
	var icons: Array = ["ground", "nest"]
	var mode := "outworld"
	var font: Font
	var _hover := -1

	func _init() -> void:
		custom_minimum_size = Vector2(0, 40)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func select(m: String) -> void:
		mode = m
		queue_redraw()

	func _half(i: int) -> Rect2:
		var w := size.x * 0.5
		return Rect2(Vector2(w * i, 0), Vector2(w, size.y))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			var h := 0 if e.position.x < size.x * 0.5 else 1
			if h != _hover:
				_hover = h
				queue_redraw()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var i := 0 if e.position.x < size.x * 0.5 else 1
			if modes[i] != mode:
				select(modes[i])
				chosen.emit(mode)
			accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			_hover = -1
			queue_redraw()

	func _draw() -> void:
		var Desk = load("res://scripts/view/ui/desk.gd")
		var C = load("res://scripts/view/ui/desk_controls.gd")
		draw_style_box(Desk.LeatherBox.new(false, 0, 0, 12.0, Color(0.8, 0.78, 0.78)), Rect2(Vector2.ZERO, size))
		var sel := modes.find(mode)
		for i in 2:
			var r := _half(i).grow(-3)
			if i == sel:
				draw_style_box(Desk.LeatherBox.new(true, 0, 0, 10.0), r)
			elif i == _hover:
				draw_style_box(Desk.LeatherBox.new(false, 0, 0, 10.0, Color(1.1, 1.06, 1.0)), r)
			var on := i == sel
			var ink := Color(0.98, 0.9, 0.72) if on else Color(0.85, 0.74, 0.58, 0.85)
			var fs := 13
			var w := font.get_string_size(words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font != null else 0.0
			var whole := 22.0 + 6.0 + w
			var x0 := r.position.x + (r.size.x - whole) * 0.5
			# the icon pressed into the leather: dark under, light over
			C.icon(self, icons[i], Vector2(x0 + 10.0, r.get_center().y + 0.8), 11.0, Color(0.15, 0.07, 0.03, 0.8))
			C.icon(self, icons[i], Vector2(x0 + 10.0, r.get_center().y), 11.0, ink)
			if font != null:
				draw_string(font, Vector2(x0 + 28.0, r.get_center().y + 5.0), words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


## A yellow pencil lying on the page (the album: the keeper, 2026-11-13 - "a yellow pencil, as on a desk"): drawn along
## its own x, the eraser at 0, the point at `size.x`; turned by the Control's rotation.
class Pencil extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(250, 18)

	func _draw() -> void:
		var L := size.x
		var h := size.y
		var y0 := 0.0
		var tip := L - h * 2.2              # where the sharpened wood begins
		# a soft shadow on the paper under it
		draw_colored_polygon(PackedVector2Array([Vector2(4, h + 3), Vector2(tip, h + 3), Vector2(L - 2, h * 0.5 + 4),
			Vector2(tip, h * 0.15 + 5), Vector2(4, h * 0.15 + 5)]), Color(0, 0, 0, 0.18))
		# the eraser and the metal ferrule
		draw_rect(Rect2(0, y0, h * 0.9, h), Color(0.86, 0.47, 0.5))
		draw_rect(Rect2(0, y0 + h * 0.62, h * 0.9, h * 0.38), Color(0.7, 0.36, 0.4))
		for k in 4:
			var x := h * 0.9 + k * h * 0.28
			draw_rect(Rect2(x, y0, h * 0.28, h), Color(0.72, 0.72, 0.7).lerp(Color(0.5, 0.5, 0.48), float(k % 2)))
		var fe := h * 0.9 + h * 1.12
		# the hexagonal body in three faces: light on top, the yellow middle, shade under
		draw_rect(Rect2(fe, y0, tip - fe, h * 0.33), Color(1.0, 0.86, 0.35))
		draw_rect(Rect2(fe, y0 + h * 0.33, tip - fe, h * 0.34), Color(0.96, 0.74, 0.12))
		draw_rect(Rect2(fe, y0 + h * 0.67, tip - fe, h * 0.33), Color(0.78, 0.55, 0.06))
		draw_line(Vector2(fe, y0 + h * 0.33), Vector2(tip, y0 + h * 0.33), Color(0.7, 0.5, 0.05, 0.6), 1.0)
		draw_line(Vector2(fe, y0 + h * 0.67), Vector2(tip, y0 + h * 0.67), Color(0.55, 0.38, 0.03, 0.6), 1.0)
		# the sharpened wood, its scalloped edge, and the graphite point
		var wood := PackedVector2Array([Vector2(tip, y0), Vector2(L - h * 0.55, y0 + h * 0.36), Vector2(L - h * 0.55, y0 + h * 0.64),
			Vector2(tip, y0 + h)])
		draw_colored_polygon(wood, Color(0.9, 0.74, 0.52))
		for k in 3:
			var c := Vector2(tip, y0 + h * (0.17 + 0.33 * k))
			draw_arc(c, h * 0.17, -PI * 0.5, PI * 0.5, 6, Color(0.96, 0.74, 0.12), h * 0.12)
		draw_colored_polygon(PackedVector2Array([Vector2(L - h * 0.55, y0 + h * 0.36), Vector2(L, y0 + h * 0.5),
			Vector2(L - h * 0.55, y0 + h * 0.64)]), Color(0.18, 0.18, 0.2))


## A small inked sketch before a figure in the side panel's readout (the keeper's picture, 2026-11-13): what it counts.
class StatIcon extends Control:
	var kind := ""
	const INK := Color(0.2, 0.13, 0.08)

	func _init(k: String) -> void:
		kind = k
		custom_minimum_size = Vector2(18, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ant(c: Vector2, s: float, col: Color, crown := false) -> void:
		for e in [[Vector2(-3.2, 0), Vector2(2.2, 1.5)], [Vector2(0, 0), Vector2(1.4, 0.9)], [Vector2(2.6, 0), Vector2(1.3, 1.2)]]:
			var pts := PackedVector2Array()
			for k in 10:
				var a := TAU * k / 10.0
				pts.append(c + (e[0] + Vector2(cos(a) * e[1].x, sin(a) * e[1].y)) * s)
			draw_colored_polygon(pts, col)
		for k in 3:
			for sd in [-1.0, 1.0]:
				var p0 := c + Vector2((k - 1) * 0.8, 0) * s
				draw_line(p0, p0 + Vector2((k - 1) * 1.8, sd * 2.6) * s, col, 0.9, true)
		if crown:
			draw_polyline(PackedVector2Array([c + Vector2(1.6, -2.4) * s, c + Vector2(2.1, -4.0) * s, c + Vector2(2.7, -2.9) * s,
				c + Vector2(3.3, -4.0) * s, c + Vector2(3.8, -2.4) * s]), Color(0.7, 0.5, 0.1), 1.0, true)

	func _draw() -> void:
		var c := size * 0.5
		match kind:
			"queen":
				_ant(c + Vector2(0, 1), 1.15, INK, true)
			"workers", "out", "nurses":
				_ant(c, 1.0, INK)
				if kind == "out":
					draw_line(c + Vector2(-7, 5), c + Vector2(7, 5), INK, 0.8)
				if kind == "nurses":
					draw_circle(c + Vector2(6.5, -2), 1.6, Color(0.95, 0.92, 0.8), true, -1.0, true)
					draw_arc(c + Vector2(6.5, -2), 1.6, 0, TAU, 8, INK, 0.7, true)
			"callow":
				_ant(c, 1.0, Color(0.7, 0.55, 0.38))
			"eggs":
				for p in [Vector2(-3, 1), Vector2(1, -1), Vector2(3, 2)]:
					draw_set_transform(c + p, 0.4, Vector2(1.0, 0.65))
					draw_circle(Vector2.ZERO, 2.4, Color(0.96, 0.94, 0.85), true, -1.0, true)
					draw_arc(Vector2.ZERO, 2.4, 0, TAU, 10, INK, 0.9, true)
					draw_set_transform(Vector2.ZERO)
			"larvae":
				draw_arc(c + Vector2(0, 1), 4.0, PI * 0.9, PI * 2.3, 10, Color(0.93, 0.88, 0.75), 3.4, true)
				draw_arc(c + Vector2(0, 1), 4.0, PI * 0.9, PI * 2.3, 10, INK, 0.7, true)
			"pupae":
				draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
				draw_circle(Vector2.ZERO, 5.0, Color(0.85, 0.72, 0.5), true, -1.0, true)
				draw_arc(Vector2.ZERO, 5.0, 0, TAU, 14, INK, 1.4, true)
				draw_set_transform(Vector2.ZERO)
			"sugar":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(3.6, 1), c + Vector2(0, 5), c + Vector2(-3.6, 1)]), Color(0.9, 0.6, 0.12))
				draw_circle(c + Vector2(0, 1.5), 3.6, Color(0.9, 0.6, 0.12), true, -1.0, true)
			"fat":
				draw_circle(c, 4.5, Color(0.95, 0.85, 0.5), true, -1.0, true)
				draw_arc(c, 4.5, 0, TAU, 12, INK, 0.9, true)
				draw_circle(c + Vector2(-1.5, -1.5), 1.2, Color(1, 1, 0.9), true, -1.0, true)
			"protein":
				draw_line(c + Vector2(-6, 4), c + Vector2(2, -3), INK, 2.2, true)
				draw_line(c + Vector2(2, -3), c + Vector2(6, 2), INK, 1.6, true)
				draw_circle(c + Vector2(-6, 4), 1.8, INK, true, -1.0, true)
			"nest_t":
				draw_line(c + Vector2(0, -6), c + Vector2(0, 3), INK, 2.4, true)
				draw_circle(c + Vector2(0, 4), 2.8, Color(0.75, 0.15, 0.1), true, -1.0, true)
				draw_line(c + Vector2(0, -1), c + Vector2(0, 3), Color(0.75, 0.15, 0.1), 1.2, true)
			"dead", "brood_dead":
				draw_line(c + Vector2(-4, -4), c + Vector2(4, 4), Color(0.6, 0.12, 0.08), 1.6, true)
				draw_line(c + Vector2(4, -4), c + Vector2(-4, 4), Color(0.6, 0.12, 0.08), 1.6, true)
			"dev", "cycle":
				draw_arc(c, 5.0, -PI * 0.8, PI * 0.9, 14, INK, 1.2, true)
				draw_colored_polygon(PackedVector2Array([c + Vector2(4.6, 2.6), c + Vector2(6.8, 4.8), c + Vector2(2.6, 5.2)]), INK)
			"vol", "depth":
				draw_rect(Rect2(c - Vector2(5, 4), Vector2(10, 8)), INK, false, 1.0, true)
				if kind == "depth":
					draw_line(c + Vector2(0, -4), c + Vector2(0, 3), INK, 1.2, true)
					draw_colored_polygon(PackedVector2Array([c + Vector2(-2, 2), c + Vector2(2, 2), c + Vector2(0, 5)]), INK)
				else:
					draw_line(c + Vector2(-5, 0), c + Vector2(5, 0), INK, 0.6)
			"size":
				draw_line(c + Vector2(-7, 2), c + Vector2(7, 2), INK, 1.2, true)
				for k in 5:
					draw_line(c + Vector2(-7 + k * 3.5, 2), c + Vector2(-7 + k * 3.5, -1 if k % 2 == 0 else 0), INK, 0.8)
