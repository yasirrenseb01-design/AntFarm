extends Window
## The keeper's album of ant plates (the keeper, 2026-11-12: "a collector's book of drawings - a colony of this species
## that reaches its count gets the plate"): for each species, plates won by having that many workers at once in any of
## the keeper's colonies - Lasius niger: plate IIa (the queen and the brood) at 50 workers, IIb (the workers) at 200.
## Won for good (kept in the settings, "album"); one not yet won shows faint, with what wins it. The plates are the
## keeper's own pictures (reference/album/, cut by tools/ui/make_album.py).
## Since v0.13.13 (the keeper: "make it the notebook on the desk, open") it is that notebook - the leather-brown cover
## with its band and red ribbon (view/home/home_kit.gd _notebook) - lying open, a plate pasted on each page with photo
## corners. Opened from the queen's sketch on the colony bar, or by clicking the notebook on the Home's desk.

const Paper := preload("res://scripts/view/ui/paper.gd")
const Desk := preload("res://scripts/view/ui/desk.gd")
const Registry := preload("res://scripts/sim/species/registry.gd")

## species id -> its plates: [id, picture, caption key, workers that win it]
const PLATES := {
	"lasius_niger": [
		["a", "res://assets/ui/album/lasius_niger_a.webp", "album_plate_a", 50],
		["b", "res://assets/ui/album/lasius_niger_b.webp", "album_plate_b", 200],
	],
}
const BOOK := Vector2(1080, 680)             # the open book, cover to cover (scaled down to fit a small window)
const COVER := Color(0.36, 0.22, 0.13)       # the desk notebook's leather (home_kit.gd _notebook)
const RIBBON := Color(0.6, 0.15, 0.12)
const PLATE := Vector2(470, 322)

var _h
var _species := ""
var _won: Array = []
var _spread := 0                             # which two plates are open (0: the first two)
var _book: Control
var _pages: Control                          # what is on the pages now (built again on a page turn)


## The plates of a species won with `workers` at once that `have` (the ids already won) lacks.
static func newly_won(species: String, workers: int, have: Array) -> Array:
	var out := []
	for p in PLATES.get(species, []):
		if workers >= int(p[3]) and not have.has(p[0]):
			out.append(p[0])
	return out


static func caption_of(species: String, id: String) -> String:
	for p in PLATES.get(species, []):
		if p[0] == id:
			return p[2]
	return ""


func setup(h, species: String, won: Array) -> void:
	_h = h
	_species = species
	_won = won
	title = tr("album_title") % tr(String(Registry.data(species).get("name_th", species)))
	theme = h._colonies.theme
	borderless = true
	transparent = true
	transparent_bg = true
	transient = true
	exclusive = true
	unresizable = true
	close_requested.connect(queue_free)
	window_input.connect(func(e):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			set_input_as_handled()            # (not on to the Home, which Esc would leave)
			queue_free())
	var vs: Vector2 = h.get_viewport().get_visible_rect().size
	size = Vector2i(vs)
	position = Vector2i.ZERO
	# the room dimmed round the book; a click there shuts it
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.02, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			queue_free())
	add_child(dim)
	_book = Book.new()
	_book.size = BOOK
	var k: float = minf(1.0, minf(vs.x * 0.94 / BOOK.x, (vs.y * 0.9 - 30.0) / BOOK.y))
	_book.scale = Vector2(k, k)
	_book.position = ((vs - BOOK * k) * 0.5).floor() - Vector2(0, 10)
	add_child(_book)
	var hint: Label = h._label(tr("album_close_hint"), 12, Color(0.95, 0.9, 0.8, 0.8))
	hint.position = Vector2(_book.position.x, _book.position.y + BOOK.y * k + 32 * k)
	hint.size = Vector2(BOOK.x * k, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	_fill()


## The pages: the album's name and count on the left page's head, a plate pasted on each page with its caption.
func _fill() -> void:
	if _pages != null:
		_pages.queue_free()
	_pages = Control.new()
	_pages.size = BOOK
	_pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(_pages)
	var plates: Array = PLATES.get(_species, [])
	var count := 0
	for p in plates:
		count += 1 if _won.has(p[0]) else 0
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Cambria", "Leelawadee UI"])
	serif.font_italic = true
	for side in 2:
		var page: Rect2 = Book.page_rect(side)
		var head: Label = _h._label(title if side == 0 else tr("album_count") % [count, plates.size()], 18 if side == 0 else 14,
			Paper.INK if side == 0 else Paper.PENCIL)
		head.add_theme_font_override("font", serif)
		head.position = Vector2(page.position.x, page.position.y + 18)
		head.size = Vector2(page.size.x, 26)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_pages.add_child(head)
		var i := _spread * 2 + side
		if i < plates.size():
			_plate(plates[i], page, side)
		var foot: Label = _h._label("— %d —" % (_spread * 2 + side + 1), 12, Paper.PENCIL)
		foot.add_theme_font_override("font", serif)
		foot.position = Vector2(page.position.x, page.end.y - 30)
		foot.size = Vector2(page.size.x, 18)
		foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_pages.add_child(foot)
	# the note at the foot of the right page, and a pencil lying across it
	var rp: Rect2 = Book.page_rect(1)
	var note: Label = _h._label(tr("album_note"), 11, Paper.PENCIL)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.position = Vector2(rp.position.x + 34, rp.end.y - 84)
	note.size = Vector2(rp.size.x - 68, 40)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pages.add_child(note)
	var pencil = load("res://scripts/view/ui/desk_controls.gd").Pencil.new()
	pencil.size = Vector2(250, 16)
	pencil.rotation = deg_to_rad(-14.0)
	pencil.position = Vector2(BOOK.x - 250, BOOK.y - 18)
	_book.add_child(pencil)
	# more plates than two pages: the corners turn the pages
	var spreads := ceili(plates.size() / 2.0)
	for s in [-1, 1]:
		var to: int = _spread + int(s)
		if to < 0 or to >= spreads:
			continue
		var b: Button = _h._button("‹" if s < 0 else "›", false)
		b.position = Vector2(Book.page_rect(0).position.x + 10, BOOK.y - 66) if s < 0 else Vector2(rp.end.x - 44, BOOK.y - 66)
		b.pressed.connect(func():
			_spread = to
			_fill())
		_pages.add_child(b)
	var shut: Button = _h._button("×", false)
	shut.tooltip_text = tr("album_close_hint")
	shut.position = Vector2(BOOK.x - 40, 4)
	shut.pressed.connect(queue_free)
	_pages.add_child(shut)


## One plate pasted on a page: tilted a little, photo corners at its four corners, its caption written under it - or,
## not won, its ghost with the count that wins it on a slip over it.
func _plate(p: Array, page: Rect2, side: int) -> void:
	var have: bool = _won.has(p[0])
	var at := Vector2(page.position.x + (page.size.x - PLATE.x) * 0.5, page.position.y + 78)
	var pasted := Pasted.new()
	pasted.have = have
	pasted.position = at
	pasted.size = PLATE
	pasted.pivot_offset = PLATE * 0.5
	pasted.rotation = deg_to_rad(-1.2 if side == 0 else 0.9)
	_pages.add_child(pasted)
	if have:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.18)
		shade.position = Vector2(3, 4)
		shade.size = PLATE
		shade.show_behind_parent = true
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pasted.add_child(shade)
	var pic := TextureRect.new()
	pic.texture = load(p[1])
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.modulate = Color.WHITE if have else Color(0.55, 0.5, 0.42, 0.2)
	pic.show_behind_parent = true
	pasted.add_child(pic)
	if not have:
		var mid := CenterContainer.new()
		mid.set_anchors_preset(Control.PRESET_FULL_RECT)
		pasted.add_child(mid)
		var lock: Label = _h._label(tr("album_locked") % int(p[3]), 15, Paper.INK)
		lock.add_theme_stylebox_override("normal", Paper.page(14, 7))       # (a slip of paper over the ghost)
		mid.add_child(lock)
	var cap: Label = _h._label(tr(p[2]), 13, Paper.INK if have else Paper.PENCIL)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.position = Vector2(page.position.x + 30, at.y + PLATE.y + 16)
	cap.size = Vector2(page.size.x - 60, 44)
	_pages.add_child(cap)


## The open notebook: the leather cover round two cream ruled pages, a page block's edges under them, the fold's shadow
## down the middle, the elastic band at the right and the red ribbon marker across the right page.
class Book extends Control:
	const M := 26.0              # the cover showing round the pages

	static func page_rect(side: int) -> Rect2:
		var w := (BOOK.x - 2.0 * M) * 0.5
		return Rect2(M + side * w + (4.0 if side == 1 else 0.0), M - 6.0, w - 4.0, BOOK.y - 2.0 * M + 10.0)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP     # (a click on the book does not shut it)

	func _draw() -> void:
		var ci := get_canvas_item()
		var r := Rect2(Vector2.ZERO, BOOK)
		Desk.poly(ci, Desk.round_rect(Rect2(r.position + Vector2(8, 12), r.size), 16), Color(0, 0, 0, 0.45))
		var cover := Desk.round_rect(r, 16)
		Desk.poly_tex(ci, cover, Desk.leather(), 160.0, COVER.lightened(0.25))
		Desk.outline(ci, cover, Color(0.14, 0.08, 0.04), 2.0)
		# a stitched line round the cover's edge
		var st := Desk.round_rect(r.grow(-9), 10)
		for i in st.size():
			var a: Vector2 = st[i]
			var b: Vector2 = st[(i + 1) % st.size()]
			var n := int(a.distance_to(b) / 9.0)
			for k in n:
				if k % 2 == 0:
					draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), Color(0.78, 0.62, 0.42, 0.55), 1.2)
		for side in 2:
			var p := page_rect(side)
			var out := -1.0 if side == 0 else 1.0
			# the page block: a few page edges showing at the outer side and the foot
			for e in range(4, 0, -1):
				var off := Vector2(out * e * 1.6, e * 1.4)
				draw_rect(Rect2(p.position + off, p.size), Color(0.8, 0.74, 0.6).darkened(0.05 * e))
				draw_rect(Rect2(p.position + off, p.size), Color(0.55, 0.47, 0.35, 0.5), false, 1.0)
			Desk.poly_tex(ci, Desk.round_rect(p, 3), Desk.paper(), 256.0)
			Desk.age(ci, p)
			# faint rules, a margin line
			var y := p.position.y + 92.0
			while y < p.end.y - 40.0:
				draw_line(Vector2(p.position.x + 18, y), Vector2(p.end.x - 18, y), Color(0.45, 0.55, 0.65, 0.12), 1.0)
				y += 28.0
			# the fold's shadow, deepest at the gutter
			var gx := p.end.x if side == 0 else p.position.x
			var wdt := 46.0 * (-1.0 if side == 0 else 1.0)
			RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([Vector2(gx, p.position.y), Vector2(gx + wdt, p.position.y),
				Vector2(gx + wdt, p.end.y), Vector2(gx, p.end.y)]), PackedColorArray([Color(0.2, 0.12, 0.05, 0.38),
				Color(0.2, 0.12, 0.05, 0.0), Color(0.2, 0.12, 0.05, 0.0), Color(0.2, 0.12, 0.05, 0.38)]))
		# the spine's crease
		var cx := BOOK.x * 0.5 + 2.0
		draw_line(Vector2(cx, M - 6.0), Vector2(cx, BOOK.y - M + 4.0), Color(0.25, 0.15, 0.08, 0.6), 2.0)
		# the elastic band, down the cover past the right page, and the ribbon across the right page and out at the foot
		draw_rect(Rect2(BOOK.x - 15.0, 0, 8.0, BOOK.y), Color(0.1, 0.07, 0.05))
		draw_line(Vector2(BOOK.x - 13.0, 0), Vector2(BOOK.x - 13.0, BOOK.y), Color(1, 1, 1, 0.08), 1.0)
		# (the ribbon down the fold, as a marker lies in a book left open: across the page it lay over the plates)
		var rx := cx + 3.0
		var rib := PackedVector2Array([Vector2(rx, M - 6.0), Vector2(rx + 11, M - 6.0), Vector2(rx + 19, BOOK.y + 24.0),
			Vector2(rx + 13, BOOK.y + 18.0), Vector2(rx + 6, BOOK.y + 27.0)])
		draw_colored_polygon(Desk.moved(rib, Vector2(2, 2)), Color(0, 0, 0, 0.2))
		draw_colored_polygon(rib, RIBBON)


## A plate pasted on the page: dark paper photo corners over its corners (its picture and shadow drawn behind them).
class Pasted extends Control:
	var have := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var c := Color(0.17, 0.12, 0.08, 0.92 if have else 0.35)
		var s := 26.0
		for k in 4:
			var o := Vector2(r.position.x if k % 2 == 0 else r.end.x, r.position.y if k < 2 else r.end.y)
			var dx := 1.0 if k % 2 == 0 else -1.0
			var dy := 1.0 if k < 2 else -1.0
			var tri := PackedVector2Array([o + Vector2(-4 * dx, -4 * dy), o + Vector2((s - 4) * dx, -4 * dy), o + Vector2(-4 * dx, (s - 4) * dy)])
			draw_colored_polygon(tri, c)
			draw_line(tri[1], tri[2], Color(1, 1, 1, 0.12), 1.0)
