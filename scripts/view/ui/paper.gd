extends RefCounted
## The keeper's field notebook look (PART EA2, the player's idea): kraft paper made in code, pencil and ink colours,
## the theme for the windows (new colony, species, settings, my colonies, reports) and a pencil scribbling sound.
## The title screen's page is drawn on it too (game/title.gd). The HUD over the colony stays dark (it sits on the scene).

const INK := Color(0.16, 0.11, 0.07)          # brown-black ink
const PENCIL := Color(0.33, 0.29, 0.25)       # graphite, for notes and where a line comes from
const ACCENT := Color(0.62, 0.2, 0.1)         # red pencil: headings
const LEAF := Color(0.2, 0.38, 0.14)          # green pencil
const DANGER := Color(0.66, 0.12, 0.08)
const RULE := Color(0.36, 0.42, 0.55, 0.28)   # the ruled lines, faded blue
const MARGIN := Color(0.7, 0.22, 0.16, 0.45)  # the margin line
const HILITE := Color(0.95, 0.82, 0.38, 0.75) # a highlighter stroke (a button turned on)

static var _tex: ImageTexture
static var _sounds: Array = []


## The paper (one texture, made once): warm brown with darker fibres and a few flecks.
static func texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var base := FastNoiseLite.new()
	base.seed = 77
	base.frequency = 0.012
	base.fractal_octaves = 4
	var fib := FastNoiseLite.new()
	fib.seed = 78
	fib.frequency = 0.09
	fib.fractal_octaves = 2
	var r := RandomNumberGenerator.new()
	r.seed = 79
	var c0 := Color(0.74, 0.6, 0.43)
	var c1 := Color(0.82, 0.69, 0.52)
	for y in n:
		for x in n:
			var v := base.get_noise_2d(x, y) * 0.5 + 0.5
			var f := fib.get_noise_2d(x * 3.0, y * 0.6) * 0.5 + 0.5        # long fibres, mostly along the sheet
			var c := c0.lerp(c1, v)
			c = c.darkened(maxf(0.0, f - 0.62) * 0.35)
			c = c.lightened(r.randf() * 0.025)
			img.set_pixel(x, y, c)
	for i in 260:
		var p := Vector2i(r.randi() % n, r.randi() % n)
		img.set_pixelv(p, c0.darkened(0.35 + r.randf() * 0.3))
	_tex = ImageTexture.create_from_image(img)
	return _tex


## A sheet of the paper as a panel style (tiled, with a soft edge shadow from the window).
static func page(pad_h := 18, pad_v := 16) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture()
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb


static func _flat(bg: Color, border: Color, width := 1, radius := 3, pad_h := 10, pad_v := 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.anti_aliasing = true
	return sb


## The windows' theme: the HUD's fonts, on paper, in ink. `base` is the HUD theme (its fonts and sizes).
static func theme(base: Theme) -> Theme:
	var th: Theme = base.duplicate()
	var clear := Color(0, 0, 0, 0)
	th.set_stylebox("panel", "PanelContainer", page())
	for cls in ["AcceptDialog", "ConfirmationDialog", "PopupPanel"]:
		th.set_stylebox("panel", cls, page())
	# the window's frame: the paper runs on under its title bar (drawn outside the window's own rect)
	var frame := page(0, 0)
	frame.expand_margin_left = 6
	frame.expand_margin_right = 6
	frame.expand_margin_bottom = 6
	frame.expand_margin_top = 34
	th.set_stylebox("embedded_border", "Window", frame)
	th.set_stylebox("embedded_unfocused_border", "Window", frame)
	th.set_color("title_color", "Window", INK)
	th.set_icon("close", "Window", _cross(false))
	th.set_icon("close_pressed", "Window", _cross(true))
	for cls in ["Label", "Button", "CheckBox", "OptionButton", "MenuButton", "RichTextLabel"]:
		th.set_color("font_color", cls, INK)
		th.set_color("font_hover_color", cls, INK)
		th.set_color("font_focus_color", cls, INK)
		th.set_color("font_pressed_color", cls, INK)
		th.set_color("font_hover_pressed_color", cls, INK)
	th.set_color("default_color", "RichTextLabel", INK)
	th.set_color("font_disabled_color", "Button", PENCIL.lightened(0.25))
	# buttons: an inked outline on the page; hovered, a light pencil shading; on (toggled), a highlighter stroke
	th.set_stylebox("normal", "Button", _flat(clear, INK.lerp(PENCIL, 0.4)))
	th.set_stylebox("hover", "Button", _flat(Color(0.3, 0.2, 0.1, 0.12), INK))
	th.set_stylebox("pressed", "Button", _flat(HILITE, INK))
	th.set_stylebox("hover_pressed", "Button", _flat(HILITE.lightened(0.08), INK))
	th.set_stylebox("disabled", "Button", _flat(clear, PENCIL.lightened(0.3)))
	for cls in ["OptionButton", "MenuButton"]:
		th.set_stylebox("normal", cls, _flat(Color(1, 1, 1, 0.12), INK.lerp(PENCIL, 0.4)))
		th.set_stylebox("hover", cls, _flat(Color(0.3, 0.2, 0.1, 0.12), INK))
	th.set_stylebox("panel", "PopupMenu", page(8, 6))
	th.set_stylebox("hover", "PopupMenu", _flat(HILITE, clear, 0, 2, 4, 2))
	th.set_color("font_color", "PopupMenu", INK)
	th.set_color("font_hover_color", "PopupMenu", INK)
	th.set_icon("unchecked", "CheckBox", _tick(false))
	th.set_icon("checked", "CheckBox", _tick(true))
	# sliders: a pencil line with an ink blot to drag
	var line := StyleBoxLine.new()
	line.color = PENCIL
	line.thickness = 2
	th.set_stylebox("slider", "HSlider", line)
	th.set_stylebox("grabber_area", "HSlider", line)
	th.set_stylebox("grabber_area_highlight", "HSlider", line)
	th.set_icon("grabber", "HSlider", _dot(false))
	th.set_icon("grabber_highlight", "HSlider", _dot(true))
	th.set_stylebox("separator", "HSeparator", line)
	return th


## A pencilled tick box: a square, ticked in ink when on.
static func _tick(on: bool) -> ImageTexture:
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in n:
		for k in 2:
			for e in [k, n - 1 - k]:
				img.set_pixel(i, e, PENCIL)
				img.set_pixel(e, i, PENCIL)
	if on:
		for t in 40:
			var u := t / 39.0
			var p := Vector2(3, 8).lerp(Vector2(7, 14), u * 2.0) if u < 0.5 else Vector2(7, 14).lerp(Vector2(17, 1), (u - 0.5) * 2.0)
			for dy in [-1, 0, 1]:
				var q := Vector2i(int(p.x), int(p.y) + dy)
				if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n:
					img.set_pixel(q.x, q.y, INK)
	return ImageTexture.create_from_image(img)


## The window's close mark, pencilled.
static func _cross(hot: bool) -> ImageTexture:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in range(2, n - 2):
		for d in [-1, 0, 1]:
			for p in [Vector2i(i, i + d), Vector2i(i, n - 1 - i + d)]:
				if p.y >= 0 and p.y < n:
					img.set_pixelv(p, ACCENT if hot else INK)
	return ImageTexture.create_from_image(img)


static func _dot(hot: bool) -> ImageTexture:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var d := Vector2(x - 7.5, y - 7.5).length()
			if d < 6.5:
				img.set_pixel(x, y, (ACCENT if hot else INK) * Color(1, 1, 1, clampf(6.5 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## A pencil scribbling a word on paper (made in code): a few quick strokes of filtered noise with the grain of the
## paper in it. Three takes, so it does not sound the same every time.
static func pencil() -> AudioStreamWAV:
	if _sounds.is_empty():
		for take in 3:
			_sounds.append(_scribble(101 + take))
	return _sounds[randi() % _sounds.size()]


static func _scribble(seed_value: int) -> AudioStreamWAV:
	var rate := 22050
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	# strokes: [start, length, loudness]
	var strokes := []
	var t0 := 0.0
	for i in r.randi_range(3, 5):
		var l := r.randf_range(0.05, 0.11)
		strokes.append([t0, l, r.randf_range(0.6, 1.0)])
		t0 += l + r.randf_range(0.015, 0.05)
	var length := int(rate * (t0 + 0.05))
	var data := PackedByteArray()
	data.resize(length * 2)
	var lp := 0.0
	var lp2 := 0.0
	for i in length:
		var t := float(i) / rate
		var env := 0.0
		for s in strokes:
			var u: float = (t - s[0]) / s[1]
			if u >= 0.0 and u <= 1.0:
				env = maxf(env, sin(PI * u) * s[2])
		var noise := r.randf_range(-1.0, 1.0)
		if r.randf() < 0.02:
			noise *= 3.0                          # the grain of the paper catching the lead
		# band-pass: a high-pass (noise minus a slow low-pass) then a gentle low-pass - a dry, papery hiss
		lp += (noise - lp) * 0.08
		var hp := noise - lp
		lp2 += (hp - lp2) * 0.55
		var v := lp2 * env * 0.5
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	return st
