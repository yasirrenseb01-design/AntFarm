extends Control
## The time bar along the top of the screen (the keeper's sketch, 2026-11-09: "a bar of time on top, like this - only
## while the tab on the left is open; the time moved from the left tab up here"): a paper strip hanging from the top
## edge, its lower edge curved, a window of sky above a line of ground. Now is the middle: the sun (or the moon) over it,
## the day and the time under it; the hours before now run off to the left, the hours to come to the right, and the
## whole strip slides left as the time goes on.
##
## The ants walking the line are the colony's foraging, hour by hour (the keeper chose this over a plain pattern): a
## quarter of an hour gets an ant as often as the foragers are keen then - sim.activity_at, the same reckoning as the
## colony's own `activity` (warmth of the ground by the sun, rain keeping them in). Behind now it is what was (recorded
## here as the time passes, not saved: before that, reckoned); ahead it is reckoned from today's weather, the rain
## while it lasts. None while the colony rests for the winter or has no workers yet - nobody goes out.
## Clouds are drawn, not simulated (the game has rain or no rain): white and few, or grey and many over the rain.
## Along the ground, the season's plants (the keeper's four pictures, 2026-11-09: tools/ui/make_seasons.py), sliding with
## the time like the ants, dimmed by night as the sky over them is, and passing from one season into the next over a few
## days round each change (the seasons as sim.season_name has them).

const Kit := preload("res://scripts/view/ui/draw_kit.gd")
const Paper := preload("res://scripts/view/ui/paper.gd")

const H_MID := 112.0          # height of the strip in the middle (its lowest point)
const H_END := 70.0           # and at its ends
const STRIP := 32.0           # the paper under the ground line: the hours and the time are written on it
const HOURS_SHOWN := 5.2      # hours across the bar (the sketch: 10:00 to 14:00 round noon)
const SLOTS := 4              # ant places per hour
const ANT_SCALE := 1.6        # (the sketch's ants are big: about a fifth of an hour long)
const INK := Paper.INK
const SCENE_H := 54.0         # the plants' height over the middle of the ground line (less towards the ends)
const SCENE_PAD := 4.0 / 128.0      # the pictures' clear rows above and below (tools/ui/make_seasons.py PAD / H)
const SEASON_FADE := 10.0     # days each side of a change of season the two pictures pass into each other
# where the seasons change (day of the year, as sim.season_name): from, to
const SEASON_TURNS := [[59.0, "winter", "spring"], [151.0, "spring", "summer"], [243.0, "summer", "autumn"],
	[334.0, "autumn", "winter"]]
static var _scenes := {}      # season -> its picture (loaded once)

var sim
var mono: Font
var _font: Font
var _past := {}               # slot -> [activity, raining] as it was (slots of 1/SLOTS hour since the colony began)
var _pph := 120.0             # pixels per hour
var _drawn_at := -1.0e9
var _drawn_size := Vector2.ZERO
var _drawn_text := ""


func setup(s, mono_font: Font) -> void:
	sim = s
	mono = mono_font
	mouse_filter = Control.MOUSE_FILTER_STOP     # (not a click through to the camera; the tip says what it shows)
	tooltip_text = tr("timebar_tip")
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS      # (the plants are drawn at ~0.4 of their pixels)


## Placed between the colony's bar on the left (left) and the side panel or the screen's edge (right).
func place(left: float, right: float) -> void:
	var w := clampf(right - left - 24.0, 0.0, 780.0)
	visible = visible and w >= 360.0
	position = Vector2(roundf((left + right - w) * 0.5), 0.0)
	size = Vector2(w, H_MID + 6.0)
	_pph = w / HOURS_SHOWN


## Hours since the colony began (the game's clock, continuous).
func _now_h() -> float:
	return float(sim.tick) * 24.0 / float(sim.TPD)


func tick_clock() -> void:
	var s := int(floor(_now_h() * SLOTS))
	if not _past.has(s):
		_past[s] = [float(sim.activity), bool(sim.climate.raining())]
		if _past.size() > 64:
			var keep := s - int(HOURS_SHOWN * SLOTS)
			for k in _past.keys():
				if k < keep:
					_past.erase(k)
	# drawn again when it has slid a pixel (or been moved, or the hour's text changed): not while paused
	var moved := (_now_h() - _drawn_at) * _pph
	if moved >= 1.0 or moved < 0.0 or size != _drawn_size or sim.clock_text() != _drawn_text:
		_drawn_at = _now_h()
		_drawn_size = size
		_drawn_text = sim.clock_text()
		queue_redraw()


## The lower edge and the ground line at x (both curve down to the middle).
func _bottom(x: float) -> float:
	var u := (x - size.x * 0.5) / (size.x * 0.5)
	return H_END + (H_MID - H_END) * (1.0 - u * u)


func _ground(x: float) -> float:
	return _bottom(x) - STRIP


func _x_of(h: float, now: float) -> float:
	return size.x * 0.5 + (h - now) * _pph


## Rain at an hour: as it was behind now; ahead, while the rain lasts.
func _rain_at(slot: int, now: float) -> bool:
	if _past.has(slot):
		return _past[slot][1]
	var ahead := float(slot) / SLOTS - now
	return ahead >= 0.0 and ahead * float(sim.TPD) / 24.0 < float(sim.climate.rain_ticks)


func _act_at(slot: int, now: float) -> float:
	if _past.has(slot):
		return _past[slot][0]
	var h := (float(slot) + 0.5) / SLOTS
	return sim.activity_at(fposmod(h / 24.0, 1.0), _rain_at(slot, now))


## A number 0..1 that stays the same for a slot (where its ant stands, whether it carries).
static func _hash01(n: int, salt: int) -> float:
	var v := sin(float(n) * 12.9898 + float(salt) * 78.233) * 43758.5453
	return v - floor(v)


func _sky(sun: float, rain: bool) -> Array:
	# [top, horizon]: day blue, a warm dawn or dusk, night
	var day := [Color(0.55, 0.74, 0.9), Color(0.86, 0.91, 0.93)]
	var dusk := [Color(0.5, 0.47, 0.66), Color(0.97, 0.69, 0.45)]
	var night := [Color(0.09, 0.11, 0.21), Color(0.17, 0.2, 0.32)]
	var out := []
	for i in 2:
		var c: Color
		if sun > 0.25:
			c = day[i]
		elif sun > -0.05:
			c = dusk[i].lerp(day[i], (sun + 0.05) / 0.3)
		else:
			c = night[i].lerp(dusk[i], clampf((sun + 0.3) / 0.25, 0.0, 1.0))
		if rain:
			c = c.lerp(Color(0.5, 0.52, 0.55) * c.get_luminance() * 1.6, 0.6)
		out.append(c)
	return out


func _draw() -> void:
	if sim == null or size.x < 10.0:
		return
	if _font == null:
		_font = get_theme_font("font", "Label")
	var w := size.x
	var now := _now_h()
	var n := 40
	var edge := PackedVector2Array()        # the outline, round the strip
	var top := PackedFloat32Array()
	var bot := PackedFloat32Array()
	var gnd := PackedFloat32Array()
	var c_top := PackedColorArray()
	var c_hor := PackedColorArray()
	var c_scene := PackedColorArray()
	for i in n + 1:
		var x := w * i / n
		top.append(0.0)
		bot.append(_bottom(x))
		gnd.append(_ground(x) - 1.0)
		edge.append(Vector2(x, _bottom(x)))
		# the sky: each column edge the sky of its own hour (dawn comes in from the right), blended between
		var hm := now + (x - w * 0.5) / _pph
		var sky: Array = _sky(sim.sun_height(fposmod(hm / 24.0, 1.0)), _rain_at(int(floor(hm * SLOTS)), now))
		c_top.append(sky[0])
		c_hor.append(sky[1])
		c_scene.append(_scene_light(sim.sun_height(fposmod(hm / 24.0, 1.0)), _rain_at(int(floor(hm * SLOTS)), now)))
	var shade := PackedColorArray()
	shade.resize(n + 1)
	shade.fill(Color(0, 0, 0, 0.28))
	var white := PackedColorArray()
	white.resize(n + 1)
	white.fill(Color.WHITE)
	_strip(n, top, bot, shade, shade, Vector2(2, 4))
	_strip(n, top, bot, white, white, Vector2.ZERO, Paper.texture())
	_strip(n, top, gnd, c_top, c_hor, Vector2.ZERO)
	_draw_sun(now)
	for pair in _season_mix():
		_draw_scene(n, pair[0], pair[1], now, c_scene)
	_draw_clouds(now)
	_draw_air()

	# the ground line, the hours on the paper under it
	var line := PackedVector2Array()
	for i in n + 1:
		var x := w * i / n
		line.append(Vector2(x, _ground(x)))
	draw_polyline(line, INK, 2.0, true)
	var h0 := int(floor(now - HOURS_SHOWN * 0.5)) - 1
	for h in range(h0, h0 + int(HOURS_SHOWN) + 3):
		for half in 2:
			var x := _x_of(h + half * 0.5, now)
			if x < 2.0 or x > w - 2.0:
				continue
			var gy := _ground(x)
			draw_line(Vector2(x, gy), Vector2(x, gy + (7.0 if half == 0 else 4.0)), INK, 1.5 if half == 0 else 1.0)
			if half == 1:
				continue
			var fade := clampf((absf(x - w * 0.5) - 70.0) / 30.0, 0.0, 1.0)      # (clear of the time in the middle)
			if fade <= 0.0:
				continue
			var label := "%02d:00" % posmod(h, 24)
			draw_string(_font, Vector2(x - 30.0, gy + 23.0), label, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 13,
				Color(Paper.PENCIL, fade))
	_draw_ants(now)
	# now: the day and the time, in the middle
	var mid := Vector2(w * 0.5, _ground(w * 0.5))
	draw_line(mid, mid + Vector2(0, 7), Paper.ACCENT, 2.0)
	var text: String = tr("clock_line") % [sim.day(), sim.clock_text()]
	draw_string(mono, Vector2(mid.x - 110.0, mid.y + 25.0), text, HORIZONTAL_ALIGNMENT_CENTER, 220.0, 17, INK)
	var rim := edge.duplicate()
	rim.reverse()
	rim.insert(0, Vector2(w, 0))
	rim.append(Vector2(0, 0))
	draw_polyline(rim, Color(INK, 0.55), 1.5, true)


## n columns from top to bottom (each n+1 long, at the column edges) as one batch of triangles: shaded, or the paper.
## (draw_colored_polygon worked the triangles out again every time it drew - most of the bar's time.)
func _strip(n: int, top: PackedFloat32Array, bottom: PackedFloat32Array, c_top: PackedColorArray, c_bottom: PackedColorArray,
		off: Vector2, tex: Texture2D = null, uvs := PackedVector2Array()) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in n + 1:
		var x := size.x * i / n
		pts.append(Vector2(x, top[i]) + off)
		pts.append(Vector2(x, bottom[i]) + off)
		cols.append(c_top[i])
		cols.append(c_bottom[i])
		if tex != null and uvs.is_empty():       # (the paper: its texture tiled as it lies)
			uv.append(pts[i * 2] / 512.0)
			uv.append(pts[i * 2 + 1] / 512.0)
		if i < n:
			idx.append_array([i * 2, i * 2 + 2, i * 2 + 1, i * 2 + 1, i * 2 + 2, i * 2 + 3])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols, uv if uvs.is_empty() else uvs,
		PackedInt32Array(), PackedFloat32Array(), tex.get_rid() if tex != null else RID())


## The season's pictures to draw now, [[season, opacity], ...]: one, or two either side of a change of season (each
## at full strength over its own half of the passing, the newer on top).
func _season_mix() -> Array:
	var d: float = sim.doy_f()
	for t in SEASON_TURNS:
		var off := fposmod(d - t[0] + 182.5, 365.0) - 182.5          # days past this change (- before it)
		if absf(off) < SEASON_FADE:
			var k := smoothstep(-SEASON_FADE, SEASON_FADE, off)
			return [[t[1], minf(1.0, 2.0 - 2.0 * k)], [t[2], minf(1.0, 2.0 * k)]]
	var name := "winter"
	for t in SEASON_TURNS:
		if d >= t[0]:
			name = t[2]
	return [[name, 1.0]]


## The plants under a sky: full colour by day, dark and blue at night, a little dim in the rain.
static func _scene_light(sun: float, rain: bool) -> Color:
	var c := Color(0.27, 0.31, 0.45).lerp(Color.WHITE, clampf((sun + 0.15) / 0.4, 0.0, 1.0))
	return c.darkened(0.15) if rain else c


## One season's plants along the ground line, the picture repeating, its bottom on the line and its top lower towards
## the ends (where the sky is narrower). light: each column's light (_scene_light), alpha the picture's opacity.
func _draw_scene(n: int, season: String, alpha: float, now: float, light: PackedColorArray) -> void:
	if alpha <= 0.0:
		return
	if not _scenes.has(season):
		_scenes[season] = load("res://assets/ui/seasons/%s.png" % season)
	var tex: Texture2D = _scenes[season]
	if tex == null:
		return
	var tile := tex.get_width() * SCENE_H / (tex.get_height() * (1.0 - 2.0 * SCENE_PAD))     # px across one on screen
	var shift := fposmod(now * _pph, tile)                         # (it slides with the time, kept small)
	var g_mid := _ground(size.x * 0.5)
	var top := PackedFloat32Array()
	var bot := PackedFloat32Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	for i in n + 1:
		var x := size.x * i / n
		var g := _ground(x)
		var hh := SCENE_H * (0.65 + 0.35 * g / g_mid)
		var pad := hh * SCENE_PAD / (1.0 - 2.0 * SCENE_PAD)
		top.append(g - hh - pad)
		bot.append(g + 1.0 + pad)
		cols.append(Color(light[i], alpha))
		var u := (x - size.x * 0.5 + shift) / tile
		uv.append(Vector2(u, 0.0))
		uv.append(Vector2(u, 1.0))
	_strip(n, top, bot, cols, cols, Vector2.ZERO, tex, uv)


## The sun over now, high or low as it is; under the horizon, the moon.
func _draw_sun(now: float) -> void:
	var c := Vector2(size.x * 0.5, _sun_y())
	var sh: float = sim.sun_height()
	if sh > -0.05:
		var col := Color(0.98, 0.76, 0.18)
		for k in 8:      # pencil rays, broken, as in the sketch
			var a := TAU * k / 8.0 + 0.2
			var d := Vector2.from_angle(a)
			draw_line(c + d * 18.0, c + d * 24.0, INK, 1.5, true)
		draw_circle(c, 13.0, col)
		draw_arc(c, 13.0, 0.0, TAU, 24, INK, 1.5, true)
	else:
		for k in 9:      # a few stars, where the sky over them is night
			var p := Vector2(_hash01(k, 3) * size.x, 8.0 + _hash01(k, 4) * 30.0)
			var hp := now + (p.x - size.x * 0.5) / _pph
			if p.y < _ground(p.x) - 6.0 and sim.sun_height(fposmod(hp / 24.0, 1.0)) < -0.15:
				draw_circle(p, 1.2, Color(1, 1, 0.9, 0.8))
		var moon := PackedVector2Array()        # a crescent: the outer edge round the left, a shallower one back up
		for k in 13:
			moon.append(c + Vector2.from_angle(PI * 0.5 + PI * k / 12.0) * 11.0)
		for k in range(1, 12):
			var a := PI * 1.5 - PI * k / 12.0
			moon.append(c + Vector2(cos(a) * 11.0 * 0.4, sin(a) * 11.0))
		draw_colored_polygon(moon, Color(0.97, 0.94, 0.78))
		moon.append(moon[0])
		draw_polyline(moon, INK, 1.2, true)


## The air's temperature beside the sun or the moon, in red (the keeper, 2026-11-09: "move the temperature from the left
## bar next to the sun and the moon, in red" - in the bar's weather line until v0.12.13), on a pale rim to read on the
## day's sky and the night's.
func _draw_air() -> void:
	var text := "%.1f°C" % float(sim.climate.air)
	var at := Vector2(size.x * 0.5 + 29.0, _sun_y() + 6.0)
	draw_string_outline(mono, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, 5, Color(1.0, 0.96, 0.86, 0.9))
	draw_string(mono, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.78, 0.08, 0.05))


## Where the sun (or the moon) stands over now: high at noon, down on the line at dawn and dusk.
func _sun_y() -> float:
	var g := _ground(size.x * 0.5)
	var sh: float = sim.sun_height()
	if sh > -0.05:
		return clampf(g - 16.0 - sh * 42.0, 20.0, g - 8.0)
	return clampf(g - 18.0 + sh * 40.0, 20.0, g - 12.0)


## Clouds in the sky over their hours (they slide past with the time): a few white ones, more and grey in the rain.
func _draw_clouds(now: float) -> void:
	var span := HOURS_SHOWN * 0.5 + 1.0
	var now_s := int(floor(now * 2.0))
	for s in range(int(floor((now - span) * 2.0)), int(ceil((now + span) * 2.0))):
		var slot := s * SLOTS / 2
		var rain := _rain_at(slot, now)
		var over_sun: bool = rain and s == now_s and sim.climate.raining()      # (a grey cloud over the sun while it rains)
		if _hash01(s, 1) > (0.85 if rain else 0.3) and not over_sun:
			continue
		var x := size.x * 0.5 if over_sun else _x_of(s * 0.5 + _hash01(s, 2) * 0.4, now)
		var y := _sun_y() + 4.0 if over_sun else 14.0 + _hash01(s, 5) * 16.0
		if y > _ground(x) - 22.0 and not over_sun:
			continue
		var col := Color(0.62, 0.64, 0.67, 0.92) if rain else Color(1, 1, 1, 0.85)
		col = col.darkened(clampf(-sim.sun_height(fposmod((s * 0.5) / 24.0, 1.0)) * 1.5, 0.0, 0.6))
		var r := 12.0 if over_sun else 7.0 + _hash01(s, 6) * 4.0
		for k in 4:
			Kit.ellipse(self, Vector2(x + (k - 1.5) * r * 0.9, y + (0.0 if k % 3 else 2.0) - (r * 0.35 if k in [1, 2] else 0.0)),
				Vector2(r, r * 0.7), col)
		if rain:
			for k in 4:
				var rx := x + (k - 1.5) * r * 0.9
				draw_line(Vector2(rx, y + r * 0.7), Vector2(rx - 3.0, y + r * 0.7 + 8.0), Color(0.35, 0.45, 0.6, 0.7), 1.0)


## The foragers along the ground, a quarter-hour each, walking left as the time goes on.
func _draw_ants(now: float) -> void:
	if sim.workers.is_empty() or sim.hibernating():
		return
	var span := HOURS_SHOWN * 0.5 + 0.3
	for slot in range(int(floor((now - span) * SLOTS)), int(ceil((now + span) * SLOTS))):
		if _hash01(slot, 7) >= _act_at(slot, now):
			continue
		var x := _x_of((float(slot) + 0.2 + _hash01(slot, 8) * 0.6) / SLOTS, now)
		if x < 20.0 or x > size.x - 20.0:      # (and on under the sun: they kept out of the middle in v0.12.12 - vanishing and
			# showing up again on the other side, the keeper, 2026-11-09)
			continue
		var slope := (_ground(x + 1.0) - _ground(x - 1.0)) * 0.5
		var phase := (x - _x_of(0.0, now)) * 0.45 + float(slot) * 1.3     # (legs move as the strip slides)
		var food := _hash01(slot, 9)
		_side_ant(Vector2(x, _ground(x) - 1.0), atan(slope), phase, 0 if food < 0.6 else (1 if food < 0.82 else 2))


## A worker seen from the side, facing left, feet on the line: gaster, waist, thorax, head, three legs, an antenna
## (the sketch's ants were drawn from the side). carry: 0 nothing, 1 a crumb of prey, 2 a full crop. The body's outlines
## are made once (_parts); the legs and the antenna, which move, in one batch of lines.
func _side_ant(foot: Vector2, ang: float, phase: float, carry: int) -> void:
	if _parts.is_empty():
		_make_parts()
	draw_set_transform(foot, ang, Vector2(ANT_SCALE, ANT_SCALE))
	var body := Color(0.12, 0.09, 0.07)
	var lines := PackedVector2Array()
	lines.resize(16)
	for k in 3:
		var hip := Vector2(-1.5 + k * 2.4, -LIFT)
		var tip := Vector2(hip.x - 2.2 + k * 1.5 + sin(phase + k * 2.1) * 1.6, 0.0)
		var knee := Vector2((hip.x + tip.x) * 0.5 + 1.2, -LIFT - 1.6)
		lines[k * 4] = hip
		lines[k * 4 + 1] = knee
		lines[k * 4 + 2] = knee
		lines[k * 4 + 3] = tip
	lines[12] = Vector2(-4.6, -LIFT - 2.0)
	lines[13] = Vector2(-5.8, -LIFT - 5.0)
	lines[14] = lines[13]
	lines[15] = Vector2(-8.2, -LIFT - 3.4 + sin(phase * 0.7) * 0.5)
	draw_multiline(lines, body, 1.0)
	var b: Array = _parts[carry]
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), b[2], b[0], b[1])
	draw_set_transform(Vector2.ZERO)


const LIFT := 4.6             # (the side ant: its body over its feet)
static var _parts := {}


## The three bodies (carry 0, 1, 2), each [points, colours, triangles]: ellipses as fans round their centres.
static func _make_parts() -> void:
	var body := Color(0.12, 0.09, 0.07)
	var gaster := [Vector2(5.5, -LIFT - 0.6), Vector2(3.4, 2.4), -0.15, body]
	var rest := [[Vector2(2.1, -LIFT - 0.2), Vector2(0.8, 0.9), 0.0, body],              # waist
		[Vector2(-0.4, -LIFT - 0.5), Vector2(2.3, 1.3), 0.1, body],                     # thorax
		[Vector2(-4.0, -LIFT - 1.0), Vector2(1.6, 1.4), 0.0, body]]                     # head
	var kinds := [[gaster] + rest,
		[gaster] + rest + [[Vector2(-6.6, -LIFT + 0.3), Vector2(1.6, 1.2), 0.0, Kit.PREY_TINT]],     # a crumb of prey
		[[Vector2(6.0, -LIFT - 0.6), Vector2(4.0, 3.0), -0.15, body.lerp(Kit.SUGAR_TINT, 0.4)]] + rest]   # a full crop
	for kind in 3:
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		for e in kinds[kind]:
			var c0 := pts.size()
			pts.append(e[0])
			cols.append(e[3])
			for i in 12:
				pts.append(e[0] + (Vector2.from_angle(TAU * i / 12.0) * e[1]).rotated(e[2]))
				cols.append(e[3])
				idx.append_array([c0, c0 + 1 + i, c0 + 1 + (i + 1) % 12])
		_parts[kind] = [pts, cols, idx]
