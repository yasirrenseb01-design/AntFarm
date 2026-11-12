extends Control
## The speeds as a brass gauge (the keeper, 2026-11-12, after their picture): a half dial, the speeds round its edge from
## Pause on the left to 5× on the right, a needle that swings to the one chosen, that segment lit. Click a speed's
## segment or its word to choose it. A developer speed (F10: 20×, 50×, 100×) pegs the needle past 5× and shows its number.
## Drawn in code (ui/desk.gd's colours).

const D := preload("res://scripts/view/ui/desk.gd")

signal picked(speed: float)

var speeds: Array = [0.0, 0.2, 0.5, 1.0, 2.0, 5.0]
var labels: Array = ["Pause", "0.2×", "0.5×", "1×", "2×", "5×"]
var font: Font
var value := 0.5                 # the speed shown
var _needle := -1.0              # the needle's angle now (it swings to the chosen speed's)
var _hover := -1


func _init() -> void:
	custom_minimum_size = Vector2(190, 108)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS          # (the needle swings while the game is paused too)
	focus_mode = Control.FOCUS_NONE


## Shows a speed without telling anyone (a developer speed: past the last stop).
func show_speed(v: float) -> void:
	value = v
	queue_redraw()


func _index() -> int:
	return speeds.find(value)


func _centre() -> Vector2:
	return Vector2(size.x * 0.5, size.y - 12.0)


func _radius() -> float:
	return minf(size.x * 0.5 - 34.0, size.y - 34.0)


## A stop's angle: Pause on the left (PI), 5× on the right (0), past it for a developer speed.
func _angle_of(i: int) -> float:
	return PI - PI * float(i) / float(speeds.size() - 1)


func _target() -> float:
	var i := _index()
	return _angle_of(i) if i >= 0 else -0.12


func _process(delta: float) -> void:
	var t := _target()
	if _needle < -0.5:
		_needle = t
	if absf(_needle - t) > 0.002:
		_needle = lerpf(_needle, t, 1.0 - exp(-delta * 9.0))      # (swings over, eases in)
		queue_redraw()


## The stop under a point (its segment of the dial or its word), or -1.
func _stop_at(p: Vector2) -> int:
	var c := _centre()
	var d := p - c
	if d.y > 6.0 or d.length() > _radius() + 30.0 or d.length() < 8.0:
		return -1
	var a := atan2(-d.y, d.x)
	if a < 0.0:
		a = 0.0 if d.x > 0 else PI
	var best := -1
	var bd := INF
	for i in speeds.size():
		var e := absf(a - _angle_of(i))
		if e < bd:
			bd = e
			best = i
	return best


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _stop_at(e.position)
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := _stop_at(e.position)
		if i >= 0:
			value = speeds[i]
			queue_redraw()
			picked.emit(value)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover >= 0:
		_hover = -1
		queue_redraw()


func _arc(c: Vector2, r0: float, r1: float, a0: float, a1: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in steps + 1:
		pts.append(c + Vector2(cos(lerpf(a0, a1, float(k) / steps)), -sin(lerpf(a0, a1, float(k) / steps))) * r1)
	for k in range(steps, -1, -1):
		pts.append(c + Vector2(cos(lerpf(a0, a1, float(k) / steps)), -sin(lerpf(a0, a1, float(k) / steps))) * r0)
	return pts


func _draw() -> void:
	if _needle < -0.5:
		_needle = _target()              # (first drawn: already at the speed, no swing)
	var c := _centre()
	var r := _radius()
	var n := speeds.size()
	var half := PI / float(n - 1) * 0.5
	# the case: a thick brass rim round a half disc, its base a bar
	draw_colored_polygon(D.moved(_arc(c, 0.0, r + 7.0, PI + 0.06, -0.06, 40), Vector2(1.5, 3)), Color(0, 0, 0, 0.3))
	var rim := _arc(c, 0.0, r + 7.0, PI + 0.06, -0.06, 40)
	var cols := PackedColorArray()
	for p in rim:
		var u: float = clampf((p.y - (c.y - r)) / r, 0.0, 1.0)
		cols.append(D.BRASS_LIGHT.lerp(D.BRASS_DARK, u * 0.8))
	draw_polygon(rim, cols)
	# the face: brushed brass, lighter towards the top
	var face := _arc(c, 0.0, r, PI, 0.0, 40)
	var fc := PackedColorArray()
	for p in face:
		var u: float = clampf((c.y - p.y) / r, 0.0, 1.0)
		fc.append(Color(0.62, 0.5, 0.27).lerp(Color(0.86, 0.74, 0.47), u))
	draw_polygon(face, fc)
	for k in 7:                                  # (brushing: faint arcs)
		var rr := r * (0.35 + 0.09 * k)
		var arcp := PackedVector2Array()
		for j in 31:
			var a := PI * j / 30.0
			arcp.append(c + Vector2(cos(a), -sin(a)) * rr)
		draw_polyline(arcp, Color(1, 0.95, 0.8, 0.12), 1.0, true)
	# the chosen speed's segment, lit cream; the one under the pointer, a little
	var sel := _index()
	for i in n:
		if i == sel or i == _hover:
			var a := _angle_of(i)
			var seg := _arc(c, r * 0.55, r - 2.0, a + half, a - half, 8)
			draw_colored_polygon(seg, Color(1.0, 0.96, 0.82, 0.78 if i == sel else 0.3))
	# segment lines and tick marks
	for i in n + 1:
		var a := PI - PI * (float(i) - 0.5) / float(n - 1)
		if a <= PI and a >= 0.0:
			draw_line(c + Vector2(cos(a), -sin(a)) * r * 0.55, c + Vector2(cos(a), -sin(a)) * r, Color(0.3, 0.2, 0.08, 0.7), 1.2, true)
	for k in 61:
		var a := PI * k / 60.0
		var l := 7.0 if k % 12 == 0 else (4.5 if k % 3 == 0 else 2.5)
		draw_line(c + Vector2(cos(a), -sin(a)) * (r - 2.0 - l), c + Vector2(cos(a), -sin(a)) * (r - 2.0), Color(0.25, 0.16, 0.06, 0.85), 1.0, true)
	draw_arc(c, r * 0.55, PI, TAU, 40, Color(0.3, 0.2, 0.08, 0.6), 1.2, true)
	draw_arc(c, r - 1.0, PI, TAU, 50, Color(0.25, 0.16, 0.06, 0.9), 1.5, true)
	# the words round the outside
	if font != null:
		for i in n:
			var a := _angle_of(i)
			var s: String = labels[i]
			var fs := 12
			var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			# (the word's middle out from the rim by half its width sideways, half its height upwards)
			var p := c + Vector2(cos(a), -sin(a)) * (r + 11.0 + w * 0.5 * absf(cos(a)) + 6.0 * sin(a))
			var at := p + Vector2(-w * 0.5, 4.0 - (5.0 if sin(a) < 0.2 else 0.0))
			var ink := D.INK if i != sel else Color(0.5, 0.18, 0.06)
			draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		if sel < 0 and value > 0.0:
			var s2 := "%d×" % int(value)
			var w2 := font.get_string_size(s2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(font, c + Vector2(-w2 * 0.5, -r * 0.3), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.18, 0.06))
	# the needle, tapered, with its shadow, and the hub
	var dir := Vector2(cos(_needle), -sin(_needle))
	var side := Vector2(dir.y, -dir.x)
	var tip := c + dir * (r - 6.0)
	var nd := PackedVector2Array([c - dir * 9.0 + side * 3.2, tip, c - dir * 9.0 - side * 3.2])
	draw_colored_polygon(D.moved(nd, Vector2(2, 2.5)), Color(0, 0, 0, 0.35))
	draw_polygon(nd, PackedColorArray([Color(0.34, 0.24, 0.1), Color(0.2, 0.13, 0.05), Color(0.5, 0.38, 0.16)]))
	draw_circle(c, 7.5, D.BRASS_DARK, true, -1.0, true)
	draw_circle(c, 5.5, D.BRASS, true, -1.0, true)
	draw_circle(c + Vector2(-1.2, -1.2), 2.2, D.BRASS_LIGHT, true, -1.0, true)
	# the base bar
	var bar := Rect2(Vector2(c.x - r - 9.0, c.y), Vector2(r * 2.0 + 18.0, 6.0))
	draw_rect(Rect2(bar.position + Vector2(1, 2), bar.size), Color(0, 0, 0, 0.3))
	draw_rect(bar, D.BRASS)
	draw_line(bar.position, bar.position + Vector2(bar.size.x, 0), D.BRASS_LIGHT, 1.0)
	draw_line(bar.position + Vector2(0, bar.size.y), bar.end, D.BRASS_DARK, 1.0)
