extends Node
## The screen on the wall behind the desk (the keeper, 2026-11-03; 43 inches, 2026-11-06): the colony running now, live - the
## colony's own world seen through a camera of its own, drawn small (640 x 360, 15-30 times a second) onto the screen. Its
## buttons are touched with the hand: which view (the title page's tour, the outworld, the nest, the queen), which tank -
## another tank's colony is loaded, the time it was away worked out, and the keeper still in the room - and off. Bought in the
## shop (home_store); drawn and moved only while it is on and in the keeper's view: the colony's views stand still otherwise
## as they do behind the room (main._process).

const Paper := preload("res://scripts/view/ui/paper.gd")
const Store := preload("res://scripts/game/save_store.gd")
const PX := Vector2i(640, 360)
const FPS_LOW := 15.0              # pictures a second at low quality, and above
const FPS_HIGH := 30.0
const FPS_SLOW := 8.0              # with the room's frames long: SLOW_FRAME seconds, smoothed
const SLOW_FRAME := 0.03
const TURN := 0.05                 # radians a second the locked views go slowly round (as the title page's tour does)
const QUEEN_EVERY := 1.0           # seconds between looks for where the queen has got to

var home_ui                        # game/home.gd
var main
var _sv: SubViewport
var _cam: Camera3D
var _at := Vector3.ZERO            # the screen's middle in the room
var _size := Vector2.ONE           # its picture, metres
var _on := true
var _mode := "auto"                # auto (the tour), outworld, nest, queen
var _seen := false                 # on, and in the keeper's view
var _tick := 0.0
var _slow := 0.0                   # the room's frame time, smoothed
var _queen_t := 0.0
var _hits: Array = []              # [{"c": Control, "do": Callable}]: the buttons on the screen
var _bar: Control
var _off_note: Label
var _busy: Label
var _hover: Control


func setup(ui) -> void:
	home_ui = ui
	main = ui.main
	_on = bool(main._settings.get("home_screen_on", true))
	_mode = String(main._settings.get("home_screen_mode", "auto"))
	_sv = SubViewport.new()
	_sv.size = PX
	_sv.world_3d = main.get_viewport().find_world_3d()     # (the colony's own world: nothing of it is made twice)
	_sv.msaa_3d = Viewport.MSAA_DISABLED
	_sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sv.gui_disable_input = true                           # (touched through click(): the hand's ray, not the pointer)
	add_child(_sv)
	_cam = Camera3D.new()
	_cam.current = true
	_sv.add_child(_cam)
	_ui()
	if _on and not main._opts.has("shot"):
		start()


func texture() -> Texture2D:
	return _sv.get_texture()


## The room built again: where the screen is now.
func placed(at: Vector3, size: Vector2) -> void:
	_at = at
	_size = size


func _ui() -> void:
	var h = main.hud
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = h._paper_theme
	_sv.add_child(root)
	_bar = VBoxContainer.new()
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar.offset_left = 8
	_bar.offset_right = -8
	_bar.offset_top = 8
	_bar.offset_bottom = -8
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bar)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	_bar.add_child(_strip(top))
	top.add_child(_button(tr("screen_auto"), _mode == "auto", func(): set_mode("auto")))
	top.add_child(_button(tr("screen_outworld"), _mode == "outworld", func(): set_mode("outworld")))
	top.add_child(_button(tr("screen_nest"), _mode == "nest", func(): set_mode("nest")))
	top.add_child(_button(tr("screen_queen"), _mode == "queen", func(): set_mode("queen")))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	top.add_child(_button(tr("screen_off"), false, func(): set_on(false)))
	var mid := Control.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bar.add_child(mid)
	var low := HBoxContainer.new()
	low.add_theme_constant_override("separation", 6)
	var low_strip := _strip(low)
	low_strip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN      # (as wide as the tanks there are)
	_bar.add_child(low_strip)
	for p in main.home.places():
		var s: int = p.slot
		var b := _button(tr("screen_tank") % p.number, s == main.slot and not main._demo, func(): _to_tank(s))
		b.disabled = not Store.exists(s)
		low.add_child(b)
	_off_note = h._label(tr("screen_touch"), 18, Color(0.75, 0.72, 0.66))
	_off_note.set_anchors_preset(Control.PRESET_CENTER)
	_off_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_off_note.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(_off_note)
	_busy = h._label("", 16, Color(0.95, 0.92, 0.85))
	_busy.set_anchors_preset(Control.PRESET_CENTER)
	_busy.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_busy.grow_vertical = Control.GROW_DIRECTION_BOTH
	_busy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_busy)
	_show_parts()


## A row of buttons on a strip of paper: on the picture itself they could not be read.
func _strip(row: Control) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Paper.page(6, 4))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	return p


func _button(text: String, pressed: bool, act: Callable) -> Button:
	var b: Button = main.hud._button(text, true)
	b.button_pressed = pressed
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	_hits.append({"c": b, "do": act})
	return b


func _show_parts() -> void:
	var busy: bool = main._catchup_left > 0
	_bar.visible = _on and not busy
	_off_note.visible = not _on and not busy
	_busy.visible = busy


func start() -> void:
	main.outworld.side_px = 0.0           # (the title page's room for its menu: not on the screen)
	main.nest_view._cam.h_offset = 0.0
	if _mode != "auto":
		_lock()


## Leaving the room: the title page's views as it had them.
func stop() -> void:
	_seen = false
	if main.title.is_open:
		main.outworld.side_px = -main.title.MENU_PX


func set_on(on: bool) -> void:
	_on = on
	main._settings["home_screen_on"] = on
	Store.save_settings(main._settings)
	_show_parts()
	if on:
		start()
	_sv.render_target_update_mode = SubViewport.UPDATE_ONCE      # (dark, or the picture again)


func set_mode(m: String) -> void:
	_mode = m
	main._settings["home_screen_mode"] = m
	Store.save_settings(main._settings)
	var names := ["auto", "outworld", "nest", "queen"]
	for i in names.size():
		(_hits[i].c as Button).button_pressed = names[i] == m
	_lock()


func _lock() -> void:
	var t = main.title
	match _mode:
		"auto":
			t._next_shot()
		"outworld":
			t._set_view("outworld")
			main.outworld.reset_view()
			main.outworld.pitch_t = 0.8
		"nest":
			t._set_view("nest")
			var q: Vector3 = main.nest_view.queen_pos()
			main.nest_view.pitch_t = 0.45
			if q != Vector3.INF:
				main.nest_view.aim_at(q, 60.0)
		"queen":
			_queen_t = 0.0
			if not t._queen_shot(""):
				t._set_view("nest")


## Another tank's colony on the screen: the scene starts again for it, and the room comes back as the keeper left it.
func _to_tank(s: int) -> void:
	if s == main.slot and not main._demo:
		return
	home_ui.keep_pose()
	main.next_home = true
	home_ui._leave()
	main._go_to(s, "")


## The title page's tour goes on behind the room for the screen (title._process).
func tour() -> bool:
	return _seen and _mode == "auto"


## The colony's views to be moved this frame (main._process).
func live() -> bool:
	return _seen and main._catchup_left <= 0


## The hand's ray on the screen: where in its picture, or (-1, -1).
func _on_picture(from: Vector3, dir: Vector3) -> Vector2:
	if absf(dir.z) < 0.0001:
		return Vector2(-1, -1)
	var k := (_at.z - from.z) / dir.z
	var p := from + dir * k
	var u := (p.x - (_at.x - _size.x * 0.5)) / _size.x
	var v := ((_at.y + _size.y * 0.5) - p.y) / _size.y
	if k < 0.0 or u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return Vector2(-1, -1)
	return Vector2(u * PX.x, v * PX.y)


func _hit(at: Vector2):
	for h in _hits:
		var c: Control = h.c
		if c.is_visible_in_tree() and not (c is Button and (c as Button).disabled) and c.get_global_rect().has_point(at):
			return h
	return null


## The hand on the screen (null ray: off it): the button under it lit.
func hover(from: Vector3, dir: Vector3) -> void:
	var h = _hit(_on_picture(from, dir)) if _on else null
	var c: Control = h.c if h != null else null
	if c != _hover:
		if _hover != null:
			_hover.modulate = Color.WHITE
		_hover = c
		if _hover != null:
			_hover.modulate = Color(1.25, 1.2, 1.05)


func unhover() -> void:
	if _hover != null:
		_hover.modulate = Color.WHITE
	_hover = null


func click(from: Vector3, dir: Vector3) -> void:
	if main._catchup_left > 0:
		return
	if not _on:
		set_on(true)
		return
	var h = _hit(_on_picture(from, dir))
	if h != null:
		h.do.call()


func _process(delta: float) -> void:
	if not home_ui.is_open:
		return
	var busy: bool = main._catchup_left > 0
	_show_parts()
	if busy:
		_busy.text = main._overlay_label.text if main._overlay_label != null else ""
	var cam: Camera3D = home_ui._cam
	var was := _seen
	_seen = (_on and not main._demo and main.sim != null and cam != null and cam.is_position_in_frustum(_at))
	if _seen and not was:
		start()
	if not _seen and not busy:
		return
	_tick -= delta
	if _tick > 0.0:
		_slow = lerpf(_slow, delta, 0.1)
		return
	_tick = 1.0 / (FPS_LOW if String(main._settings.get("quality", "medium")) == "low" else FPS_HIGH)
	# (the room is not to pay for it: the outworld on the screen took an Intel UHD's room from 37 to 21 frames a second at high
	# quality - with the frame long, fewer pictures)
	_slow = lerpf(_slow, delta, 0.1)
	if _slow > SLOW_FRAME:
		_tick = 1.0 / FPS_SLOW
	if _mode == "queen":
		_queen_t -= delta
		if _queen_t <= 0.0:
			_queen_t = QUEEN_EVERY
			main.title._queen_shot("")
	if _mode != "auto" and not busy:
		if main.mode == "outworld":
			main.outworld.yaw_t += TURN * maxf(delta, 1.0 / FPS_HIGH)
		else:
			main.nest_view.yaw_t += TURN * maxf(delta, 1.0 / FPS_HIGH)
	var src: Camera3D = main.nest_view._cam if main.mode == "nest" else main.outworld._cam
	_cam.global_transform = src.global_transform
	_cam.fov = src.fov
	_cam.near = src.near
	_cam.far = src.far
	_cam.environment = src.environment
	_cam.h_offset = 0.0
	_sv.render_target_update_mode = SubViewport.UPDATE_ONCE
