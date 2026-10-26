extends CanvasLayer
## The Home (the keeper, 2026-10-26): a room seen through the keeper's own eyes, only their hand as the pointer. The
## tanks on the desk are the colonies (home_store.gd: one save slot each): a click on one goes into it, or starts a new
## colony in an empty one; the door is not open yet. WASD / arrows walk, the right mouse button held looks round,
## Esc goes back to the title page. The room is drawn in a viewport of its own (its own world and light); the colony's
## views are not drawn meanwhile (the simulation goes on).
## main.gd owns it: open() / close().

const Room := preload("res://scripts/view/home/home_room.gd")
const Paper := preload("res://scripts/view/ui/paper.gd")
const Store := preload("res://scripts/game/save_store.gd")
const EYE := 1.55                 # metres: the keeper's eyes
const WALK := 1.3                 # metres a second
const LOOK := 0.005               # radians a pixel of mouse
const MARGIN := 0.3               # how near a wall the keeper can walk

var main
var is_open := false
var _vp: SubViewport
var _box: SubViewportContainer
var _cam: Camera3D
var _room
var _env: Environment
var _yaw := 0.0
var _pitch := -0.42
var _looking := false
var _hot = null                   # the item the pointer is on (home_room.items), or null
var _tip: Label
var _toast: Label
var _toast_t := 0.0
var _purse: Label
var _hand_open: Texture2D
var _hand_point: Texture2D


func setup(m) -> void:
	main = m
	layer = 11
	visible = false
	_hand_open = load("res://assets/ui/hand_open.png")
	_hand_point = load("res://assets/ui/hand_point.png")


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var h = main.hud
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = h._paper_theme
	add_child(root)
	_box = SubViewportContainer.new()
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.stretch = true
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_box.gui_input.connect(_on_input)
	root.add_child(_box)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X if String(main._settings.get("quality", "medium")) == "high" else Viewport.MSAA_DISABLED
	_vp.positional_shadow_atlas_size = 2048
	_box.add_child(_vp)
	var day := _is_day()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.05, 0.05, 0.06)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.75, 0.72, 0.68) if day else Color(0.35, 0.33, 0.38)
	_env.ambient_light_energy = 0.45 if day else 0.25
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.05
	var low := String(main._settings.get("quality", "medium")) == "low"
	_env.glow_enabled = not low
	_env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = _env
	_vp.add_child(we)
	_room = Room.new()
	_vp.add_child(_room)
	_room.build(main.home.tanks, func(s): return Store.exists(s), day)
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.near = 0.03
	_cam.current = true
	_vp.add_child(_cam)
	_cam.position = Vector3(0.0, EYE, -0.55)
	# a bar along the top on paper: back to the title page, the Home, the purse
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", Paper.page())
	bar.anchor_right = 1.0
	bar.offset_bottom = 46
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)
	var back: Button = h._button(tr("home_back"), false)
	back.pressed.connect(close)
	row.add_child(back)
	var title: Label = h._label(tr("home_title"), 18, Paper.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(title)
	_purse = h._label("", 14, Paper.INK)
	row.add_child(_purse)
	var help: Label = h._label(tr("home_help"), 12, Color(1, 1, 1, 0.85))
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 20
	help.offset_top = -30
	help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	help.add_theme_constant_override("shadow_offset_x", 1)
	help.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(help)
	_tip = _note(root, h)
	_toast = _note(root, h)


## A note on paper beside the pointer.
func _note(root: Control, h) -> Label:
	var l: Label = h._label("", 14, Paper.INK)
	var sb: StyleBox = Paper.page()
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	l.add_theme_stylebox_override("normal", sb)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	root.add_child(l)
	return l


func _is_day() -> bool:
	var hr := int(main._opts.get("home-hour", Time.get_datetime_dict_from_system().hour))
	return hr >= 6 and hr < 19


func open() -> void:
	if main.home == null:
		return
	_build()
	is_open = true
	visible = true
	main.title.visible = false
	get_viewport().disable_3d = true                 # (the colony's views: not drawn behind the room)
	_yaw = 0.0
	_pitch = -0.42
	_hot = null
	_aim()
	Input.set_custom_mouse_cursor(_hand_open, Input.CURSOR_ARROW, Vector2(19, 3))
	Input.set_custom_mouse_cursor(_hand_point, Input.CURSOR_POINTING_HAND, Vector2(16, 2))
	_update_purse()


## Back to the title page.
func close() -> void:
	if not is_open:
		return
	_leave()
	main.title.visible = true


## (also when the scene starts again for another colony: the window's viewport and the pointer outlive it)
func _exit_tree() -> void:
	if is_open:
		get_viewport().disable_3d = false
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)


func _leave() -> void:
	is_open = false
	visible = false
	get_viewport().disable_3d = false
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
	for c in get_children():
		c.queue_free()


func _update_purse() -> void:
	var p: float = main.harmony.points
	_purse.text = tr("home_purse") % (str(int(p)) if p >= 100.0 else "%.1f" % p)


func _aim() -> void:
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if not is_open:
		return
	var mv := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if mv != Vector2.ZERO:
		var step := mv.normalized().rotated(-_yaw) * WALK * delta
		var p := _cam.position + Vector3(step.x, 0, step.y)
		var lim: float = Room.W * 0.5 - MARGIN
		p.x = clampf(p.x, -lim, lim)
		p.z = clampf(p.z, -lim, lim)
		# (not through the desk)
		var dz: float = Room.DESK.z + Room.DESK_SIZE.z * 0.5 + 0.25
		if absf(p.x - Room.DESK.x) < Room.DESK_SIZE.x * 0.5 + 0.2 and p.z < dz:
			p.z = dz
		_cam.position = p
	if _toast.visible:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.visible = false
	_update_purse()


func _on_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_RIGHT:
			_looking = e.pressed
		elif e.button_index == MOUSE_BUTTON_LEFT and e.pressed and _hot != null:
			_click(_hot)
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_cam.fov = maxf(35.0, _cam.fov - 3.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_cam.fov = minf(70.0, _cam.fov + 3.0)
	elif e is InputEventMouseMotion:
		if _looking:
			_yaw -= e.relative.x * LOOK
			_pitch = clampf(_pitch - e.relative.y * LOOK, -1.3, 1.1)
			_aim()
		_point(e.position)


## What the pointer is on: the nearest item its ray goes into.
func _point(at: Vector2) -> void:
	var from := _cam.project_ray_origin(at)
	var dir := _cam.project_ray_normal(at)
	var best = null
	var best_d := INF
	for it in _room.items:
		var hit = (it.box as AABB).intersects_ray(from, dir)
		if hit != null and from.distance_to(hit) < best_d:
			best_d = from.distance_to(hit)
			best = it
	if not is_same(best, _hot):
		_hot = best
		_room.hover(best)
		_box.mouse_default_cursor_shape = Control.CURSOR_ARROW if best == null else Control.CURSOR_POINTING_HAND
	_tip.visible = best != null
	if best != null:
		_tip.text = _describe(best)
		_tip.reset_size()
		_tip.position = at + Vector2(26, 18)
		var vs := get_viewport().get_visible_rect().size
		_tip.position.x = minf(_tip.position.x, vs.x - _tip.size.x - 8)
		_tip.position.y = minf(_tip.position.y, vs.y - _tip.size.y - 8)


func _describe(it) -> String:
	if it.kind == "door":
		return tr("home_door")
	var s: int = it.slot
	var m: Dictionary = Store.meta(s)
	if m.is_empty():
		return tr("home_tank_empty") % it.number
	return tr("home_tank") % [it.number, m.get("day", 1), m.get("workers", 0),
		"" if m.get("queen", true) else tr("title_queen_dead")]


func _click(it) -> void:
	if it.kind == "door":
		_toast.text = tr("home_soon")
		_toast.reset_size()
		_toast.position = _tip.position + Vector2(0, 40)
		_toast.visible = true
		_toast_t = 2.0
		return
	var s: int = it.slot
	if not Store.exists(s):
		main.hud.open_species(s, false, "keeper")
		return
	if s == main.slot and not main._demo:
		_leave()
		main.title.visible = true
		main.title.close()                      # (the colony already open: straight into it)
		return
	_leave()
	main._go_to(s, "")


func _unhandled_key_input(e: InputEvent) -> void:
	if is_open and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
