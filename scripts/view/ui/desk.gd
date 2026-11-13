extends RefCounted
## The keeper's desk look for the HUD over the colony (the keeper, 2026-11-12: a clipboard on a wooden board with a brass
## clip, a brass gauge for the speeds, a leather strap for the views, wax seals for the buttons - after a picture they
## made): the colony's bar on the left and the side panel on the right are clipboards, the tool bar a wooden tray.
## Everything is drawn in code (the keeper's choice: crisp at any size, both languages): textures made once, and
## StyleBoxes that draw the board, the paper, the clip, the tray, leather and tags. The widgets: ui/desk_dial.gd,
## ui/desk_controls.gd.

const INK := Color(0.16, 0.11, 0.07)
const PENCIL := Color(0.36, 0.3, 0.24)
const CREAM := Color(0.95, 0.91, 0.81)
const BRASS := Color(0.78, 0.62, 0.3)
const BRASS_DARK := Color(0.42, 0.3, 0.12)
const BRASS_LIGHT := Color(0.97, 0.88, 0.6)
const WOOD := Color(0.45, 0.28, 0.15)
const LEATHER := Color(0.5, 0.3, 0.16)
const STITCH := Color(0.93, 0.8, 0.58, 0.85)

static var _wood: ImageTexture
static var _paper: ImageTexture
static var _leather: ImageTexture


# ---------------------------------------------------------------- textures (made once)

## Wooden boards: a warm brown with long grain along x, a few darker streaks.
static func wood() -> ImageTexture:
	if _wood == null:
		_wood = _noise_tex(256, 81, Color(0.36, 0.21, 0.11), Color(0.55, 0.35, 0.19), Vector2(0.15, 2.4), 0.5)
	return _wood


## The clipboard's sheet: cream, faint fibres.
static func paper() -> ImageTexture:
	if _paper == null:
		_paper = _noise_tex(256, 82, Color(0.9, 0.85, 0.73), Color(0.97, 0.94, 0.85), Vector2(1.0, 0.35), 0.18)
	return _paper


## Leather: brown, fine grain both ways.
static func leather() -> ImageTexture:
	if _leather == null:
		_leather = _noise_tex(128, 83, LEATHER.darkened(0.25), LEATHER.lightened(0.12), Vector2(1.0, 1.0), 0.3)
	return _leather


static func _noise_tex(n: int, seed_value: int, c0: Color, c1: Color, stretch: Vector2, streaks: float) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var base := FastNoiseLite.new()
	base.seed = seed_value
	base.frequency = 0.02
	base.fractal_octaves = 4
	var fine := FastNoiseLite.new()
	fine.seed = seed_value + 1
	fine.frequency = 0.08
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	for y in n:
		for x in n:
			# (seamless enough when tiled: the noise sampled on a torus would be exact; the boards hide the seam)
			var v := base.get_noise_2d(x * stretch.x, y * stretch.y) * 0.5 + 0.5
			var f := fine.get_noise_2d(x * stretch.x * 2.0, y * stretch.y * 2.0) * 0.5 + 0.5
			var c := c0.lerp(c1, clampf(v * 1.2 - 0.1, 0.0, 1.0))
			c = c.darkened(maxf(0.0, f - 0.6) * streaks)
			c = c.lightened(r.randf() * 0.03)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- drawing helpers (RenderingServer: for the StyleBoxes)

## A rounded rectangle's outline, corners of radius r.
static func round_rect(rect: Rect2, r: float, steps := 5) -> PackedVector2Array:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var cs := [rect.position + Vector2(rect.size.x - r, r), rect.end - Vector2(r, r),
		rect.position + Vector2(r, rect.size.y - r), rect.position + Vector2(r, r)]
	for k in 4:
		for i in steps + 1:
			var a := -PI * 0.5 + PI * 0.5 * (k + float(i) / steps)
			pts.append(cs[k] + Vector2.from_angle(a) * r)
	return pts


static func moved(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + by)
	return out


static func poly(ci: RID, pts: PackedVector2Array, col: Color) -> void:
	RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([col]))


## A polygon filled with a texture tiled at its own size (uv = position / tile).
static func poly_tex(ci: RID, pts: PackedVector2Array, tex: Texture2D, tile: float, tint := Color.WHITE) -> void:
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(p / tile)
	RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([tint]), uv, tex.get_rid())


## A brass piece: a polygon shaded from light (top) to dark (bottom), with a dark rim.
static func brass(ci: RID, pts: PackedVector2Array, light := BRASS_LIGHT, dark := BRASS_DARK) -> void:
	var y0 := INF
	var y1 := -INF
	for p in pts:
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
	var cols := PackedColorArray()
	for p in pts:
		var u := (p.y - y0) / maxf(1.0, y1 - y0)
		cols.append(light.lerp(BRASS, minf(1.0, u * 1.6)).lerp(dark, maxf(0.0, u - 0.6) * 1.6))
	RenderingServer.canvas_item_add_polygon(ci, pts, cols)
	outline(ci, pts, BRASS_DARK.darkened(0.2), 1.0)


static func outline(ci: RID, pts: PackedVector2Array, col: Color, w: float) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	RenderingServer.canvas_item_add_polyline(ci, loop, PackedColorArray([col]), w, true)


## A dashed line (stitching).
static func dashes(ci: RID, pts: PackedVector2Array, col: Color, dash := 5.0, gap := 3.0, w := 1.2) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	var carry := 0.0
	for i in loop.size() - 1:
		var a: Vector2 = loop[i]
		var b: Vector2 = loop[i + 1]
		var l := a.distance_to(b)
		var t := carry
		while t < l:
			var e := minf(l, t + dash)
			RenderingServer.canvas_item_add_line(ci, a.lerp(b, t / l), a.lerp(b, e / l), col, w, true)
			t += dash + gap
		carry = t - l


static func circle(ci: RID, c: Vector2, r: float, col: Color) -> void:
	RenderingServer.canvas_item_add_circle(ci, c, r, col, true)


## Age on a sheet (v0.13.7, the keeper's picture of an old field-notebook page): its edges browned and darker in a soft
## band, a few faint stains (the same on a sheet of the same size), and - `dog_ear` - its bottom right corner turned
## up. Drawn over the paper already there.
static func age(ci: RID, r: Rect2, dog_ear := false) -> void:
	var band := clampf(minf(r.size.x, r.size.y) * 0.2, 10.0, 46.0)
	var inner := r.grow(-band)
	var edge := Color(0.36, 0.2, 0.07, 0.6)
	var clear := Color(0.36, 0.2, 0.07, 0.0)
	var o := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var i := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	for k in 4:
		var k2 := (k + 1) % 4
		RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([o[k], o[k2], i[k2], i[k]]),
			PackedColorArray([edge, edge, clear, clear]))
	# stains: a few soft rings of tea-brown, where the size of the sheet puts them
	var seed_value := int(r.size.x * 7.0 + r.size.y * 13.0)
	for k in 5:
		var h1 := fposmod(sin(float(seed_value + k * 17)) * 43758.55, 1.0)
		var h2 := fposmod(sin(float(seed_value * 3 + k * 29)) * 24634.63, 1.0)
		var h3 := fposmod(sin(float(seed_value + k * 51)) * 13758.21, 1.0)
		var c := r.position + Vector2(r.size.x * (0.08 + 0.84 * h1), r.size.y * (0.08 + 0.84 * h2))
		var rad := 4.0 + 18.0 * h3
		RenderingServer.canvas_item_add_circle(ci, c, rad, Color(0.48, 0.32, 0.12, 0.05 + 0.05 * h3))
		RenderingServer.canvas_item_add_circle(ci, c, rad * 0.6, Color(0.95, 0.88, 0.72, 0.05))
	if dog_ear:
		# the corner turned up: the paper's back showing, a shadow under the fold
		var s := clampf(minf(r.size.x, r.size.y) * 0.08, 10.0, 22.0)
		var e := r.end
		RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([e - Vector2(s, 0), e, e - Vector2(0, s)]),
			PackedColorArray([Color(0.14, 0.09, 0.05)]))
		RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([e - Vector2(s, 0) + Vector2(1.5, 2.5), e - Vector2(0, s) + Vector2(2.5, 1.5),
			e - Vector2(s, s) + Vector2(3, 3)]), PackedColorArray([Color(0, 0, 0, 0.25)]))
		RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([e - Vector2(s, 0), e - Vector2(0, s), e - Vector2(s, s)]),
			PackedColorArray([Color(0.86, 0.78, 0.62), Color(0.86, 0.78, 0.62), Color(0.97, 0.92, 0.8)]))


# ---------------------------------------------------------------- the StyleBoxes

## A clipboard: a wooden board with brass corners, a cream sheet on it and a brass clip at the top (drawn above the box).
class ClipboardBox extends StyleBox:
	var clip_w := 0.46            # the clip's width, of the board's

	func _init(pad_h := 22, pad_top := 38, pad_bottom := 18) -> void:
		content_margin_left = pad_h
		content_margin_right = pad_h
		content_margin_top = pad_top
		content_margin_bottom = pad_bottom

	func _draw(ci: RID, rect: Rect2) -> void:
		var D = load("res://scripts/view/ui/desk.gd")
		# a shadow on the scene, the board, its darker rim
		D.poly(ci, D.round_rect(Rect2(rect.position + Vector2(3, 5), rect.size), 12), Color(0, 0, 0, 0.35))
		var board: PackedVector2Array = D.round_rect(rect, 12)
		D.poly_tex(ci, board, D.wood(), 256.0)
		D.outline(ci, board, Color(0.2, 0.11, 0.05), 2.0)
		D.outline(ci, D.round_rect(rect.grow(-2), 10), Color(0.75, 0.52, 0.3, 0.35), 1.0)
		# brass corner caps
		for k in 4:
			var sx := 1.0 if k % 2 == 0 else -1.0
			var sy := 1.0 if k < 2 else -1.0
			var o := Vector2(rect.position.x if sx > 0 else rect.end.x, rect.position.y if sy > 0 else rect.end.y)
			var cap := PackedVector2Array([o + Vector2(2, 2) * Vector2(sx, sy), o + Vector2(26, 2) * Vector2(sx, sy),
				o + Vector2(26, 7) * Vector2(sx, sy), o + Vector2(7, 7) * Vector2(sx, sy), o + Vector2(7, 26) * Vector2(sx, sy),
				o + Vector2(2, 26) * Vector2(sx, sy)])
			D.brass(ci, cap)
		# the sheet: a little in from the board, its shadow, faint ruled darkening at its edge
		var sheet := Rect2(rect.position + Vector2(9, 22), rect.size - Vector2(18, 30))
		D.poly(ci, D.round_rect(Rect2(sheet.position + Vector2(1.5, 2.5), sheet.size), 2), Color(0, 0, 0, 0.3))
		var sp: PackedVector2Array = D.round_rect(sheet, 2)
		D.poly_tex(ci, sp, D.paper(), 256.0)
		D.age(ci, sheet, true)
		D.outline(ci, sp, Color(0.55, 0.45, 0.32, 0.5), 1.0)
		# the clip: a brass plate over the sheet's top, with a lever ring above the board
		var cw := maxf(70.0, rect.size.x * clip_w)
		var cx := rect.position.x + rect.size.x * 0.5
		var top := rect.position.y
		var ring := Rect2(cx - cw * 0.22, top - 12, cw * 0.44, 22)
		D.brass(ci, D.round_rect(ring, 9))
		D.poly(ci, D.round_rect(ring.grow(-5), 5), Color(0.18, 0.1, 0.05))
		var plate := PackedVector2Array([Vector2(cx - cw * 0.5, top + 6), Vector2(cx + cw * 0.5, top + 6),
			Vector2(cx + cw * 0.46, top + 30), Vector2(cx - cw * 0.46, top + 30)])
		D.poly(ci, D.moved(plate, Vector2(1.5, 3)), Color(0, 0, 0, 0.3))
		D.brass(ci, plate)
		RenderingServer.canvas_item_add_line(ci, Vector2(cx - cw * 0.44, top + 10), Vector2(cx + cw * 0.44, top + 10),
			Color(1, 0.95, 0.75, 0.6), 1.5, true)
		for s in [-1.0, 1.0]:
			var rv := Vector2(cx + s * cw * 0.38, top + 19)
			D.circle(ci, rv, 3.2, D.BRASS_DARK)
			D.circle(ci, rv - Vector2(0.8, 0.8), 2.0, D.BRASS_LIGHT)


## The tool bar's wooden tray: boards with a raised lighter rim and brass corner pieces.
class TrayBox extends StyleBox:
	func _init(pad_h := 16, pad_v := 11) -> void:
		content_margin_left = pad_h
		content_margin_right = pad_h
		content_margin_top = pad_v
		content_margin_bottom = pad_v

	func _draw(ci: RID, rect: Rect2) -> void:
		var D = load("res://scripts/view/ui/desk.gd")
		D.poly(ci, D.round_rect(Rect2(rect.position + Vector2(3, 5), rect.size), 9), Color(0, 0, 0, 0.35))
		var outer: PackedVector2Array = D.round_rect(rect, 9)
		D.poly_tex(ci, outer, D.wood(), 256.0, Color(1.08, 1.04, 1.0))
		D.outline(ci, outer, Color(0.2, 0.11, 0.05), 2.0)
		# the tray's floor: sunk in, darker, a shadow under its rim along the top
		var floor_r := rect.grow(-6)
		var fl: PackedVector2Array = D.round_rect(floor_r, 5)
		D.poly_tex(ci, fl, D.wood(), 200.0, Color(0.78, 0.74, 0.7))
		RenderingServer.canvas_item_add_rect(ci, Rect2(floor_r.position + Vector2(4, 0), Vector2(floor_r.size.x - 8, 3)), Color(0, 0, 0, 0.28))
		D.outline(ci, fl, Color(0.16, 0.08, 0.03, 0.8), 1.0)
		for k in 4:
			var sx := 1.0 if k % 2 == 0 else -1.0
			var sy := 1.0 if k < 2 else -1.0
			var o := Vector2(rect.position.x if sx > 0 else rect.end.x, rect.position.y if sy > 0 else rect.end.y)
			var cap := PackedVector2Array([o + Vector2(1, 1) * Vector2(sx, sy), o + Vector2(16, 1) * Vector2(sx, sy),
				o + Vector2(16, 5) * Vector2(sx, sy), o + Vector2(5, 5) * Vector2(sx, sy), o + Vector2(5, 16) * Vector2(sx, sy),
				o + Vector2(1, 16) * Vector2(sx, sy)])
			D.brass(ci, cap)


## Stitched leather (tabs, the views' strap): `raised` lighter, with a shadow under it.
class LeatherBox extends StyleBox:
	var raised := false
	var radius := 7.0
	var tint := Color.WHITE

	func _init(is_raised := false, pad_h := 12, pad_v := 6, r := 7.0, t := Color.WHITE) -> void:
		raised = is_raised
		radius = r
		tint = t
		content_margin_left = pad_h
		content_margin_right = pad_h
		content_margin_top = pad_v
		content_margin_bottom = pad_v

	func _draw(ci: RID, rect: Rect2) -> void:
		var D = load("res://scripts/view/ui/desk.gd")
		if raised:
			D.poly(ci, D.round_rect(Rect2(rect.position + Vector2(1, 2.5), rect.size), radius), Color(0, 0, 0, 0.4))
		var pts: PackedVector2Array = D.round_rect(rect, radius)
		D.poly_tex(ci, pts, D.leather(), 128.0, (Color(1.3, 1.22, 1.12) if raised else Color(0.92, 0.9, 0.9)) * tint)
		D.outline(ci, pts, Color(0.18, 0.09, 0.04), 1.2)
		if rect.size.y > 14:
			D.dashes(ci, D.round_rect(rect.grow(-3.5), maxf(2.0, radius - 3.0)), D.STITCH * Color(1, 1, 1, 0.85 if raised else 0.55), 4.0, 2.5, 1.1)


## A paper tag (the tool bar's buttons): cream, an inked edge; on, a honey-coloured wash; hovered, a little lighter.
class TagBox extends StyleBox:
	var state := "normal"

	func _init(s := "normal", pad_h := 10, pad_v := 5) -> void:
		state = s
		content_margin_left = pad_h
		content_margin_right = pad_h
		content_margin_top = pad_v
		content_margin_bottom = pad_v

	func _draw(ci: RID, rect: Rect2) -> void:
		var D = load("res://scripts/view/ui/desk.gd")
		var on := state.contains("pressed")
		var r := rect if not on else Rect2(rect.position + Vector2(0, 1), rect.size)
		D.poly(ci, D.round_rect(Rect2(r.position + Vector2(1, 2), r.size), 3), Color(0, 0, 0, 0.35 if not on else 0.2))
		var pts: PackedVector2Array = D.round_rect(r, 3)
		var tint := Color.WHITE
		if on:
			tint = Color(1.0, 0.86, 0.52)
		elif state == "hover":
			tint = Color(1.05, 1.04, 1.0)
		elif state == "disabled":
			tint = Color(0.75, 0.72, 0.68)
		D.poly_tex(ci, pts, D.paper(), 256.0, tint)
		D.outline(ci, pts, Color(0.3, 0.2, 0.1, 0.9 if on else 0.55), 1.0)


## A parchment ribbon behind a line of text (the points), its right end curled.
class RibbonBox extends StyleBox:
	func _init() -> void:
		content_margin_left = 12
		content_margin_right = 20
		content_margin_top = 3
		content_margin_bottom = 4

	func _draw(ci: RID, rect: Rect2) -> void:
		var D = load("res://scripts/view/ui/desk.gd")
		var x0 := rect.position.x
		var x1 := rect.end.x - 8.0
		var y0 := rect.position.y
		var y1 := rect.end.y
		var band := PackedVector2Array([Vector2(x0, y0 + 1), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1 - 1)])
		D.poly(ci, D.moved(band, Vector2(1, 2)), Color(0, 0, 0, 0.18))
		D.poly_tex(ci, band, D.paper(), 256.0, Color(0.97, 0.9, 0.76))
		D.outline(ci, band, Color(0.45, 0.33, 0.2, 0.7), 1.0)
		# the curl: a rolled end, darker inside
		var c := Vector2(x1 + 1.0, (y0 + y1) * 0.5)
		var h := (y1 - y0) * 0.5
		D.poly(ci, D.round_rect(Rect2(c - Vector2(4, h), Vector2(10, h * 2.0)), 4), Color(0.86, 0.76, 0.58))
		D.outline(ci, D.round_rect(Rect2(c - Vector2(4, h), Vector2(10, h * 2.0)), 4), Color(0.45, 0.33, 0.2, 0.7), 1.0)
		D.poly(ci, D.round_rect(Rect2(c + Vector2(0, -h * 0.45), Vector2(4, h * 0.9)), 2), Color(0.55, 0.42, 0.26))


## A loose sheet of the cream paper (the panels beside the bar: enemies, top ants, an ant's card): its shadow, a faint
## pencilled edge.
class SheetBox extends StyleBox:
	func _init(pad_h := 14, pad_v := 12) -> void:
		content_margin_left = pad_h
		content_margin_right = pad_h
		content_margin_top = pad_v
		content_margin_bottom = pad_v

	func _draw(ci: RID, rect: Rect2) -> void:
		var D = load("res://scripts/view/ui/desk.gd")
		D.poly(ci, D.round_rect(Rect2(rect.position + Vector2(2, 4), rect.size), 4), Color(0, 0, 0, 0.32))
		var pts: PackedVector2Array = D.round_rect(rect, 3)
		D.poly_tex(ci, pts, D.paper(), 256.0)
		D.age(ci, rect, true)
		D.outline(ci, pts, Color(0.45, 0.35, 0.24, 0.55), 1.0)


## A window (the reports, settings, my colonies, the species, the album...) on a clipboard: the board round it, the
## cream sheet under its title and body, the brass clip over the title's top. Drawn round the window's rect, which
## leaves out its title bar (TITLE above it).
class WindowBox extends StyleBox:
	const TITLE := 34.0
	const EDGE := 12.0

	func _draw(ci: RID, rect: Rect2) -> void:
		var D = load("res://scripts/view/ui/desk.gd")
		var board := rect.grow_individual(EDGE, TITLE + EDGE + 8.0, EDGE, EDGE)
		D.poly(ci, D.round_rect(Rect2(board.position + Vector2(4, 7), board.size), 12), Color(0, 0, 0, 0.4))
		var bp: PackedVector2Array = D.round_rect(board, 12)
		D.poly_tex(ci, bp, D.wood(), 256.0)
		D.outline(ci, bp, Color(0.2, 0.11, 0.05), 2.0)
		D.outline(ci, D.round_rect(board.grow(-2), 10), Color(0.75, 0.52, 0.3, 0.35), 1.0)
		for k in 4:
			var sx := 1.0 if k % 2 == 0 else -1.0
			var sy := 1.0 if k < 2 else -1.0
			var o := Vector2(board.position.x if sx > 0 else board.end.x, board.position.y if sy > 0 else board.end.y)
			D.brass(ci, PackedVector2Array([o + Vector2(2, 2) * Vector2(sx, sy), o + Vector2(28, 2) * Vector2(sx, sy),
				o + Vector2(28, 7) * Vector2(sx, sy), o + Vector2(7, 7) * Vector2(sx, sy), o + Vector2(7, 28) * Vector2(sx, sy),
				o + Vector2(2, 28) * Vector2(sx, sy)]))
		var sheet := rect.grow_individual(3, TITLE, 3, 3)
		D.poly(ci, D.round_rect(Rect2(sheet.position + Vector2(1.5, 2.5), sheet.size), 2), Color(0, 0, 0, 0.3))
		var sp: PackedVector2Array = D.round_rect(sheet, 2)
		D.poly_tex(ci, sp, D.paper(), 256.0)
		D.age(ci, sheet, true)
		D.outline(ci, sp, Color(0.55, 0.45, 0.32, 0.5), 1.0)
		# the clip, on the board above the sheet
		var cw := clampf(board.size.x * 0.3, 90.0, 220.0)
		var cx := board.get_center().x
		var top := board.position.y
		var ring := Rect2(cx - cw * 0.22, top - 11, cw * 0.44, 20)
		D.brass(ci, D.round_rect(ring, 8))
		D.poly(ci, D.round_rect(ring.grow(-5), 5), Color(0.18, 0.1, 0.05))
		var plate := PackedVector2Array([Vector2(cx - cw * 0.5, top + 4), Vector2(cx + cw * 0.5, top + 4),
			Vector2(cx + cw * 0.46, top + 22), Vector2(cx - cw * 0.46, top + 22)])
		D.poly(ci, D.moved(plate, Vector2(1.5, 3)), Color(0, 0, 0, 0.3))
		D.brass(ci, plate)
		for s in [-1.0, 1.0]:
			var rv := Vector2(cx + s * cw * 0.38, top + 13)
			D.circle(ci, rv, 3.0, D.BRASS_DARK)
			D.circle(ci, rv - Vector2(0.8, 0.8), 1.8, D.BRASS_LIGHT)


## A page of the paper, aged at its edges (Paper.page() since v0.13.7: the windows' bodies, the banner, the Home's
## panels). No shadow or outline: it lies on whatever holds it.
class PageBox extends StyleBox:
	var dog_ear := false

	func _init(pad_h := 18, pad_v := 16, ear := false) -> void:
		dog_ear = ear
		content_margin_left = pad_h
		content_margin_right = pad_h
		content_margin_top = pad_v
		content_margin_bottom = pad_v

	func _draw(ci: RID, rect: Rect2) -> void:
		var D = load("res://scripts/view/ui/desk.gd")
		RenderingServer.canvas_item_add_texture_rect(ci, rect, D.paper().get_rid(), true)
		D.age(ci, rect, dog_ear)


## The keeper's journal on the side panel: a page with a stitched leather spine down its left edge (the keeper's picture).
class JournalBox extends StyleBox:
	func _init() -> void:
		content_margin_left = 22
		content_margin_right = 8
		content_margin_top = 6
		content_margin_bottom = 6

	func _draw(ci: RID, rect: Rect2) -> void:
		var D = load("res://scripts/view/ui/desk.gd")
		D.poly(ci, D.round_rect(Rect2(rect.position + Vector2(1.5, 2.5), rect.size), 3), Color(0, 0, 0, 0.25))
		RenderingServer.canvas_item_add_texture_rect(ci, rect, D.paper().get_rid(), true)
		D.age(ci, rect, true)
		var spine := Rect2(rect.position, Vector2(14, rect.size.y))
		D.poly_tex(ci, D.round_rect(spine, 3), D.leather(), 128.0)
		D.outline(ci, D.round_rect(spine, 3), Color(0.18, 0.09, 0.04), 1.0)
		var y := rect.position.y + 6.0
		while y < rect.end.y - 6.0:
			RenderingServer.canvas_item_add_line(ci, Vector2(rect.position.x + 7, y), Vector2(rect.position.x + 7, y + 4), D.STITCH, 1.2, true)
			y += 7.0
