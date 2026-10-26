extends CanvasLayer
## The title screen (PART EA2): what the game opens on, and where the "เมนู" button (or Esc) goes back to. The game's
## logo at the top, the menu on a page of the keeper's field notebook on the left (a pencil scribbles when a word is
## clicked); behind it the last colony lives on, and the camera tours it - the outworld from above, a forager,
## the queen, the brood, a worker in the nest - and, once ants have names (EA3b), every other shot follows a named one.
## main.gd owns it: open() / close(); while it is open the HUD is hidden.

const SHOT_S := 14.0                  # seconds a shot lasts
const TURN := 0.05                    # radians a second the camera drifts round
const FIND_S := 2.0                   # seconds to find an ant in the nest just switched to (it is drawn after a few frames)
const MENU_PX := 470.0                # how much of the window's left the menu takes
const PAGE_W := 380.0                 # the notebook page
const LOGO_W := 760.0
const Paper := preload("res://scripts/view/ui/paper.gd")

var main
var is_open := false
var clip := false                     # the tour alone, no menu, nothing on screen (F8: the keeper films it, PART EA-R)
var _root: Control
var _go_on: Button                    # tr("title_go_on") (not for the colony shown before the first one is started)
var _go_on_note: Label
var _caption: Label                   # what the camera is looking at, bottom right
var _page                             # the notebook page the menu is written on (Page)
var _items: Array = []                # the menu's words (Buttons)
var _pen: AudioStreamPlayer           # the pencil, scribbling when a word is clicked
var _rng := RandomNumberGenerator.new()      # (only looks: never sim.rng, which keeps the colony reproducible)
var _shot := -1
var _shot_t := 0.0
var _named_turn := false
var _named_i := -1
var _follow = null                    # the ant the camera rides with (an Ant), or null
var _follow_t := 0.0                  # seconds it has been followed
var _view_before := "outworld"
var _xray_before := false
var pending_report: Array = []        # [title, text]: the time-away report, kept until the keeper goes on into the game


func setup(m) -> void:
	main = m
	layer = 10
	_rng.randomize()
	var h = main.hud
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP           # (the tour has the camera: no dragging it meanwhile)
	_root.theme = _menu_theme(h)
	add_child(_root)
	# the game's logo, top centre (the keeper's picture: assets/ui/logo.png, made by tools/ui/make_logo.py)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/ui/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.anchor_left = 0.5
	logo.anchor_right = 0.5
	logo.offset_left = -LOGO_W * 0.5
	logo.offset_right = LOGO_W * 0.5
	logo.offset_top = 18
	logo.offset_bottom = 18 + LOGO_W * 0.34
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(logo)
	# the menu: a page of the keeper's field notebook, taped on a little askew
	_page = Page.new()
	_page.anchor_top = 0.5
	_page.anchor_bottom = 0.5
	_page.offset_left = 56
	_page.offset_right = 56 + PAGE_W
	_page.offset_top = -170
	_page.offset_bottom = 225
	_page.rotation = -0.025
	_root.add_child(_page)
	var col := VBoxContainer.new()
	col.position = Vector2(56, 26)
	col.size = Vector2(PAGE_W - 80, 420)
	col.add_theme_constant_override("separation", 0)
	_page.add_child(col)
	var head: Label = h._label(tr("title_notebook"), 15, Paper.ACCENT)
	head.custom_minimum_size.y = Page.LINE * 1.5
	head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	col.add_child(head)
	_go_on = _item(col, tr("title_go_on"), close, true)
	_go_on_note = h._label("", 12, Paper.PENCIL)
	_go_on_note.custom_minimum_size.y = Page.LINE
	_go_on_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(_go_on_note)
	_item(col, tr("title_home"), func(): main.home_room.open())
	_item(col, tr("title_wild"), func(): h.open_colonies("wild"))
	_item(col, tr("settings"), func(): h.open_settings())
	_item(col, tr("wallpaper"), func(): main._enter_desktop())
	_item(col, tr("title_quit"), func(): main.get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST))
	var ver: Label = h._label("v%s" % ProjectSettings.get_setting("application/config/version", "dev"), 12, h.MUTED)
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 24
	ver.offset_top = -34
	_root.add_child(ver)
	_caption = h._label("", 15, h.INK, h._display)
	_caption.anchor_left = 1.0
	_caption.anchor_right = 1.0
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_right = -36
	_caption.offset_bottom = -32
	_caption.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_caption.add_theme_constant_override("shadow_offset_x", 1)
	_caption.add_theme_constant_override("shadow_offset_y", 1)
	_root.add_child(_caption)
	_pen = AudioStreamPlayer.new()
	_pen.volume_db = -4.0
	add_child(_pen)
	visible = false


## The menu's words: written on the page, no boxes; under the pointer a pencil line is drawn beneath one.
func _menu_theme(h) -> Theme:
	var th: Theme = h._make_theme().duplicate()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		th.set_stylebox(st, "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Paper.INK)
	th.set_color("font_hover_color", "Button", Paper.ACCENT)
	th.set_color("font_pressed_color", "Button", Paper.ACCENT)
	th.set_color("font_hover_pressed_color", "Button", Paper.ACCENT)
	th.set_color("font_focus_color", "Button", Paper.INK)
	return th


func _item(parent: Control, text: String, fn: Callable, first := false) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(PAGE_W - 90, Page.LINE)
	b.add_theme_font_size_override("font_size", 24 if first else 20)
	b.mouse_entered.connect(func(): _page.hover(b))
	b.mouse_exited.connect(func(): _page.hover(null))
	b.pressed.connect(func():
		_pen.stream = Paper.pencil()
		_pen.play()
		fn.call())
	parent.add_child(b)
	_items.append(b)
	return b


## The notebook page: kraft paper, ruled lines and a margin, a strip of tape at the top; under the word the pointer is
## on, a pencil line is drawn in, quickly, a little wobbly.
class Page extends Control:
	const LINE := 38.0                 # the ruling
	var _hot: Button = null
	var _hot_t := 0.0
	var _seed := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func hover(b: Button) -> void:
		_hot = b
		_hot_t = 0.0
		_seed += 1
		queue_redraw()

	func _process(delta: float) -> void:
		if _hot != null and _hot_t < 1.0:
			_hot_t = minf(1.0, _hot_t + delta * 4.0)       # drawn in over a quarter of a second
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(Rect2(r.position + Vector2(7, 9), r.size), Color(0, 0, 0, 0.35))      # its shadow
		draw_texture_rect(Paper.texture(), r, true)
		var y := 26.0 + LINE * 1.5
		while y < size.y - 12.0:
			draw_line(Vector2(10, y), Vector2(size.x - 10, y), Paper.RULE, 1.0)
			y += LINE
		draw_line(Vector2(44, 6), Vector2(44, size.y - 6), Paper.MARGIN, 1.5)
		# a strip of tape holding it on
		draw_set_transform(Vector2(size.x * 0.5, 3), 0.06, Vector2.ONE)
		draw_rect(Rect2(-48, -15, 96, 30), Color(0.93, 0.89, 0.76, 0.6))
		draw_set_transform_matrix(Transform2D.IDENTITY)
		if _hot != null and is_instance_valid(_hot) and _hot.is_visible_in_tree():
			var at: Vector2 = _hot.position + (_hot.get_parent() as Control).position
			var font: Font = _hot.get_theme_font("font")
			var w: float = font.get_string_size(_hot.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _hot.get_theme_font_size("font_size")).x + 22.0
			var rr := RandomNumberGenerator.new()
			rr.seed = _seed
			var pts := PackedVector2Array()
			var n := 18
			for i in n + 1:
				var u := float(i) / n * _hot_t
				pts.append(at + Vector2(4 + u * w, _hot.size.y - 6 + sin(u * 9.0 + _seed) * 1.6 + rr.randf_range(-0.6, 0.6)))
			draw_polyline(pts, Paper.PENCIL, 2.0, true)


## Shows the title screen over the colony (`can_go_on`: false for the colony shown before any is started).
func open(can_go_on := true) -> void:
	is_open = true
	visible = true
	main.hud.visible = false
	_view_before = main.mode
	_xray_before = main.nest_view.xray
	main.nest_view.set_xray(true)                      # (underground the tour sees through the soil: never a shot of bare soil)
	main.outworld.side_px = -MENU_PX                  # (the outworld centred right of the menu, not left of the side panel)
	_go_on.visible = can_go_on
	_go_on_note.visible = can_go_on
	var s = main.sim
	_go_on_note.text = (tr("title_colony_note_wild") if s.scenario == "wild" else tr("title_colony_note")) % [main.hud.slot_no(main.slot), s.year(), s.date_text(), s.workers.size(),
		"" if s.queen.alive else tr("title_queen_dead")]
	_shot = -1
	_named_turn = false
	_next_shot()
	if main._opts.has("title-hover"):
		_page.hover(_items[int(main._opts["title-hover"])])         # (dev: as if the pointer were on that word)


## Clip mode (F8): the camera tour with nothing on screen - no menu, no captions, no HUD - for the keeper to film.
func open_clip() -> void:
	open(true)
	clip = true
	visible = false
	main.outworld.side_px = 0.0                        # (the whole window is the picture)


## Back to the game, in the view the keeper had.
func close() -> void:
	if not is_open:
		return
	is_open = false
	var was_clip := clip
	clip = false
	visible = false
	_follow = null
	main.outworld.follow_cid = 0
	main.nest_view._cam.h_offset = 0.0
	main.nest_view.set_xray(_xray_before)
	main.hud.visible = true
	main.hud.set_side_open(main.hud._side.visible, false)     # (the outworld's centre as the side panel has it)
	_set_view(_view_before)
	if not main._demo and not was_clip:
		main.hud.maybe_guide()
	if not pending_report.is_empty():
		main.hud.show_report(pending_report[0], pending_report[1])
		pending_report = []


func _set_view(m: String) -> void:
	if main.mode != m:
		main.hud._apply_mode(m)
		main._set_mode(m)


func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if main.home_room != null and main.home_room.is_open:
		return                                        # (the Home has the keys)
	if e.keycode == KEY_F8 and not main.desktop.on and (clip or not is_open):
		# clip mode: the tour with nothing on screen, F8 (or Esc) again to stop
		if clip:
			close()
		elif main.hud.visible or _ui_hidden:
			_show_ui(true)
			open_clip()
		get_viewport().set_input_as_handled()
		return
	if e.keycode == KEY_F9 and not is_open and not main.desktop.on:
		_show_ui(_ui_hidden)                          # nothing on screen but the colony, the camera the keeper's own
		get_viewport().set_input_as_handled()
		return
	if e.keycode != KEY_ESCAPE:
		return
	if clip:
		close()
		get_viewport().set_input_as_handled()
	elif _ui_hidden:
		_show_ui(true)
		get_viewport().set_input_as_handled()
	elif is_open and _go_on.visible:
		close()
		get_viewport().set_input_as_handled()
	elif not is_open and main.hud.visible and main.hud.ant_tip.sel.is_empty() and not main.desktop.on:
		open()
		get_viewport().set_input_as_handled()


## F9: the HUD (and the ant's info box with it) hidden or back; hidden, the outworld centres on the whole window.
var _ui_hidden := false

func _show_ui(on: bool) -> void:
	_ui_hidden = not on
	main.hud.visible = on
	if on:
		main.hud.set_side_open(main.hud._side.visible, false)
	else:
		main.outworld.side_px = 0.0


# ---------------------------------------------------------------- the camera tour

func _process(delta: float) -> void:
	if not is_open:
		return
	_shot_t -= delta
	if _shot_t <= 0.0:
		_next_shot()
	if main.mode == "outworld":
		main.outworld.yaw_t += TURN * delta
	else:
		var nv = main.nest_view
		nv.yaw_t += TURN * delta
		# what the camera looks at, right of the menu (the outworld does it with side_px)
		var vp: Vector2 = nv.get_viewport().get_visible_rect().size
		nv._cam.h_offset = 0.0 if clip else -MENU_PX * 0.5 * 2.0 * nv.cam_dist * tan(deg_to_rad(nv._cam.fov * 0.5)) / vp.y
	if _follow != null:
		_follow_t += delta
		if not _keep_following(_follow):
			_next_shot()                       # (it went in or out, or died: on to the next shot)


## Ants with a name the keeper gave them (EA3b; none before that) - the queen first ("queen") when she has one.
func _named() -> Array:
	var out: Array = ["queen"] if main.sim.queen.alive and String(main.sim.queen.get("name", "")) != "" else []
	return out + main.sim.workers.filter(func(w): return String(w.get("name") if w.get("name") != null else "") != "")


func _next_shot() -> void:
	_shot_t = SHOT_S
	_follow = null
	var named := _named()
	_named_turn = not _named_turn and not named.is_empty()        # every other shot a named ant, when there are some
	if _named_turn:
		_named_i = (_named_i + 1) % named.size()
		if named[_named_i] is String:
			if _queen_shot(String(main.sim.queen.name)):        # (the named queen)
				return
		elif _watch(named[_named_i], String(named[_named_i].get("name"))):
			return
	for tries in 5:
		_shot = (_shot + 1) % 5
		if _take(_shot):
			return


## One of the colony's sights; false if there is nothing to see there now (no forager out, no brood...).
func _take(i: int) -> bool:
	var s = main.sim
	var ow = main.outworld
	var nv = main.nest_view
	match i:
		0:
			_set_view("outworld")
			ow.reset_view()
			ow.pitch_t = 0.8
			ow.yaw_t = _rng.randf_range(-0.6, 0.6)
			_caption.text = tr("shot_outworld") if s.scenario == "keeper" else tr("shot_plot")
			return true
		1:
			var out: Array = s.outside.filter(func(a): return (a.vpos as Vector2).x != INF)
			if out.is_empty():
				return false
			return _watch(out[_rng.randi() % out.size()], tr("shot_forager"))
		2:
			return _queen_shot("")
		3:
			_set_view("nest")
			for kind in (["larvae", "pupae", "eggs"] if _rng.randf() < 0.5 else ["pupae", "larvae", "eggs"]):
				var p: Vector3 = nv.brood_pos(kind)
				if p != Vector3.INF:
					nv.pitch_t = 0.5
					nv.aim_at(p, 20.0)
					_caption.text = {"larvae": tr("larvae"), "pupae": tr("shot_cocoons"), "eggs": tr("eggs")}[kind]
					return true
			return false
		4:
			var inside: Array = s.workers.filter(func(w): return not s.outside.has(w))
			if inside.is_empty():
				return false
			return _watch(inside[_rng.randi() % inside.size()], tr("shot_nest_worker"))
	return false


## Rides along with one ant, in whichever view it is in.
## The queen in the nest (caption: her name, if the keeper gave her one); false if she is dead or not placed yet.
func _queen_shot(qname: String) -> bool:
	var nv = main.nest_view
	if not main.sim.queen.alive:
		return false
	_set_view("nest")
	var q: Vector3 = nv.queen_pos()
	if q == Vector3.INF:
		return false
	nv.pitch_t = 0.45
	nv.aim_at(q, 22.0)
	_caption.text = tr("queen") if qname == "" else tr("shot_queen_named") % qname
	return true


func _watch(w, caption: String) -> bool:
	var out: bool = main.sim.outside.has(w)
	_set_view("outworld" if out else "nest")
	_follow = w
	_follow_t = 0.0
	_caption.text = caption
	if out:
		main.outworld.dist_t = 40.0
		main.outworld.pitch_t = 0.7
	else:
		main.nest_view.pitch_t = 0.45
	return _keep_following(w)


func _keep_following(w) -> bool:
	var s = main.sim
	if not s.workers.has(w):
		return false
	if s.outside.has(w):
		if main.mode != "outworld":
			return false
		var vp: Vector2 = w.vpos if (w.vpos as Vector2).x != INF else w.pos
		main.outworld.target_t = Vector3(vp.x, 0, vp.y) * main.outworld.U
		return true
	if main.mode != "nest":
		return false
	var p: Vector3 = main.nest_view.mate_pos(w.id)
	if p == Vector3.INF:
		# (just switched to the nest: it places its ants over the first frames - up to FIND_S to find this one)
		return _follow_t < FIND_S
	main.nest_view.aim_at(p, 18.0)
	return true
