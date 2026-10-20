extends CanvasLayer
## The title screen (PART EA2): what the game opens on, and where the "เมนู" button (or Esc) goes back to. The menu
## sits on the left; behind it the last colony lives on, and the camera tours it - the outworld from above, a forager,
## the queen, the brood, a worker in the nest - and, once ants have names (EA3b), every other shot follows a named one.
## main.gd owns it: open() / close(); while it is open the HUD is hidden.

const SHOT_S := 14.0                  # seconds a shot lasts
const TURN := 0.05                    # radians a second the camera drifts round
const MENU_PX := 520.0                # how much of the window's left the menu takes

var main
var is_open := false
var _root: Control
var _go_on: Button                    # "เล่นต่อ" (not for the colony shown before the first one is started)
var _go_on_note: Label
var _caption: Label                   # what the camera is looking at, bottom right
var _rng := RandomNumberGenerator.new()      # (only looks: never sim.rng, which keeps the colony reproducible)
var _shot := -1
var _shot_t := 0.0
var _named_turn := false
var _named_i := -1
var _follow = null                    # the ant the camera rides with (an Ant), or null
var _view_before := "outworld"


func setup(m) -> void:
	main = m
	layer = 10
	_rng.randomize()
	var h = main.hud
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP           # (the tour has the camera: no dragging it meanwhile)
	_root.theme = h._make_theme()
	add_child(_root)
	# a dark band on the left, fading out to the right
	var band := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([Color(0.06, 0.045, 0.035, 0.94), Color(0.06, 0.045, 0.035, 0.8), Color(0.06, 0.045, 0.035, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	band.texture = gt
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.anchor_bottom = 1.0
	band.offset_right = 640
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(band)
	var col := VBoxContainer.new()
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = 72
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.add_theme_constant_override("separation", 10)
	_root.add_child(col)
	col.add_child(h._label("มดดำสวน", 52, h.INK, h._display))
	col.add_child(h._label("AntFarm · เลี้ยงมดแบบสมจริง", 16, h.MUTED))
	var gap := Control.new()
	gap.custom_minimum_size.y = 26
	col.add_child(gap)
	_go_on = _big(col, "เล่นต่อ", close, true)
	_go_on_note = h._label("", 13, h.MUTED)
	col.add_child(_go_on_note)
	_big(col, "รังใหม่", func(): main._title_new_colony())
	_big(col, "รังของฉัน", func(): h.open_colonies())
	_big(col, "ตั้งค่า", func(): h.open_settings())
	_big(col, "วอลเปเปอร์", func(): main._enter_desktop())
	_big(col, "ออกจากเกม", func(): main.get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST))
	var ver: Label = h._label("v%s" % ProjectSettings.get_setting("application/config/version", "dev"), 12, h.MUTED)
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 72
	ver.offset_top = -40
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
	visible = false


func _big(parent: Control, text: String, fn: Callable, accent := false) -> Button:
	var b: Button = main.hud._button(text, false)
	b.custom_minimum_size = Vector2(300, 46 if accent else 40)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 20 if accent else 17)
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


## Shows the title screen over the colony (`can_go_on`: false for the colony shown before any is started).
func open(can_go_on := true) -> void:
	is_open = true
	visible = true
	main.hud.visible = false
	_view_before = main.mode
	main.outworld.side_px = -MENU_PX                  # (the outworld centred right of the menu, not left of the side panel)
	_go_on.visible = can_go_on
	_go_on_note.visible = can_go_on
	var s = main.sim
	_go_on_note.text = "รัง %d · ปีที่ %d · %s · มดงาน %d ตัว%s" % [main.slot, s.year(), s.date_text(), s.workers.size(),
		"" if s.queen.alive else " · ราชินีตายแล้ว"]
	_shot = -1
	_named_turn = false
	_next_shot()


## Back to the game, in the view the keeper had.
func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	_follow = null
	main.outworld.follow_cid = 0
	main.nest_view._cam.h_offset = 0.0
	main.hud.visible = true
	main.hud.set_side_open(main.hud._side.visible, false)     # (the outworld's centre as the side panel has it)
	_set_view(_view_before)


func _set_view(m: String) -> void:
	if main.mode != m:
		main.hud._apply_mode(m)
		main._set_mode(m)


func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE):
		return
	if is_open and _go_on.visible:
		close()
		get_viewport().set_input_as_handled()
	elif not is_open and main.hud.visible and main.hud.ant_tip.sel.is_empty() and not main.desktop.on:
		open()
		get_viewport().set_input_as_handled()


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
		nv._cam.h_offset = -MENU_PX * 0.5 * 2.0 * nv.cam_dist * tan(deg_to_rad(nv._cam.fov * 0.5)) / vp.y
	if _follow != null:
		if not _keep_following(_follow):
			_next_shot()                       # (it went in or out, or died: on to the next shot)


## Ants with a name the keeper gave them (EA3b; none before that).
func _named() -> Array:
	return main.sim.workers.filter(func(w): return String(w.get("name") if w.get("name") != null else "") != "")


func _next_shot() -> void:
	_shot_t = SHOT_S
	_follow = null
	var named := _named()
	_named_turn = not _named_turn and not named.is_empty()        # every other shot a named ant, when there are some
	if _named_turn:
		_named_i = (_named_i + 1) % named.size()
		if _watch(named[_named_i], String(named[_named_i].get("name"))):
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
			_caption.text = "พื้นที่หาอาหาร" if s.scenario == "keeper" else "แปลงดินรอบรัง"
			return true
		1:
			var out: Array = s.outside.filter(func(a): return (a.vpos as Vector2).x != INF)
			if out.is_empty():
				return false
			return _watch(out[_rng.randi() % out.size()], "มดงานออกหากิน")
		2:
			if not s.queen.alive:
				return false
			_set_view("nest")
			var q: Vector3 = nv.queen_pos()
			if q == Vector3.INF:
				return false
			nv.pitch_t = 0.45
			nv.aim_at(q, 22.0)
			_caption.text = "ราชินี"
			return true
		3:
			_set_view("nest")
			for kind in (["larvae", "pupae", "eggs"] if _rng.randf() < 0.5 else ["pupae", "larvae", "eggs"]):
				var p: Vector3 = nv.brood_pos(kind)
				if p != Vector3.INF:
					nv.pitch_t = 0.5
					nv.aim_at(p, 20.0)
					_caption.text = {"larvae": "ตัวอ่อน", "pupae": "รังไหม (ดักแด้)", "eggs": "ไข่"}[kind]
					return true
			return false
		4:
			var inside: Array = s.workers.filter(func(w): return not s.outside.has(w))
			if inside.is_empty():
				return false
			return _watch(inside[_rng.randi() % inside.size()], "มดงานในรัง")
	return false


## Rides along with one ant, in whichever view it is in.
func _watch(w, caption: String) -> bool:
	var out: bool = main.sim.outside.has(w)
	_set_view("outworld" if out else "nest")
	if not out and main.nest_view.mate_pos(w.id) == Vector3.INF:
		_set_view("outworld")
		return false
	_follow = w
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
		return false
	main.nest_view.aim_at(p, 18.0)
	return true
