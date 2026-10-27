extends CanvasLayer
## The Home (the keeper, 2026-10-26): a room seen through the keeper's own eyes, only their hand in the middle of the
## view. The tanks on the desk are the colonies (home_store.gd: one save slot each): a click on one goes into it, or
## starts a new colony in an empty one; the chair is sat on; the door is not open yet. The mouse turns the view (as in a
## first-person game: the keeper, 2026-10-27 - no button held), WASD / arrows walk, Tab frees the pointer for the bar at
## the top and the shop, Esc goes back to the title page. The room is drawn in a viewport of its own (its own world and
## light); the colony's views are not drawn meanwhile (the simulation goes on). Day and night, and the sun through the
## window, follow the computer's clock (home_room.set_hour).
## main.gd owns it: open() / close().

const Room := preload("res://scripts/view/home/home_room.gd")
const Paper := preload("res://scripts/view/ui/paper.gd")
const Store := preload("res://scripts/game/save_store.gd")
const Shop := preload("res://scripts/game/home_shop.gd")
const Hand := preload("res://scripts/view/home/home_hand.gd")
const EYE := 1.55                 # metres: the keeper's eyes
const EYE_SEATED := 1.15
const WALK := 1.3                 # metres a second
const LOOK := 0.0025              # radians a pixel of mouse
const MARGIN := 0.3               # how near a wall the keeper can walk
const SIT_S := 0.6                # seconds to sit down or get up
const START_Z := -0.15            # where the keeper stands at first: behind the chair, the desk in view (at -0.55, v0.11.49,
                                  # they stood inside the chair's room and could not take a step)

var main
var is_open := false
var _vp: SubViewport
var _box: SubViewportContainer
var _cam: Camera3D
var _room
var _env: Environment
var _yaw := 0.0
var _pitch := -0.42
var _hot = null                   # the item the hand is on (home_room.items), or null
var _tip: Label
var _toast: Label
var _toast_t := 0.0
var _purse: Label
var _help: Label
var shop                          # game/home_shop.gd: the shop page
var _hand: TextureRect            # the keeper's hand drawn flat, in the middle of the view (with the 3D hand off)
var _hand3d                       # view/home/home_hand.gd: the keeper's hand in 3D, lower right (settings "home_hand")
var _cross: ColorRect             # an aiming point in the middle of the view (settings "home_cross")
var _hand_open: Texture2D
var _hand_point: Texture2D
var _free := false                # Tab: the pointer free for the bar and the shop (the view stays still)
var _seated := false
var _move_from := Transform3D()   # sitting down / getting up: from where, to where, how far along
var _move_to := Transform3D()
var _move_t := 1.0
var _clock_t := 0.0
var _food: Label


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
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.05, 0.04, 0.035)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.0
	var low := String(main._settings.get("quality", "medium")) == "low"
	_env.glow_enabled = not low
	_env.glow_intensity = 0.55
	_env.glow_bloom = 0.08
	_env.adjustment_enabled = true                   # (a warmer, softer room: the keeper, 2026-10-27 "cozy")
	_env.adjustment_saturation = 1.08
	_env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = _env
	_vp.add_child(we)
	rebuild_room()
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.near = 0.03
	_cam.current = true
	_vp.add_child(_cam)
	_cam.position = Vector3(0.0, EYE, START_Z)
	if main._opts.has("home-fov"):
		_cam.fov = float(main._opts["home-fov"])          # (dev: a closer look)
	_hand3d = null
	if bool(main._settings.get("home_hand", true)):
		_hand3d = Hand.new()
		_cam.add_child(_hand3d)
	# the room's warm edges darkened a little (a vignette)
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = "shader_type canvas_item;\nvoid fragment() { vec2 d = UV - 0.5; float v = smoothstep(0.35, 0.85, length(d * vec2(1.0, 0.8))); COLOR = vec4(0.12, 0.06, 0.02, v * 0.45); }"
	var vm := ShaderMaterial.new()
	vm.shader = vs
	vig.material = vm
	root.add_child(vig)
	# the hand, in the middle
	_hand = TextureRect.new()
	_hand.texture = _hand_open
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand.anchor_left = 0.5
	_hand.anchor_right = 0.5
	_hand.anchor_top = 0.5
	_hand.anchor_bottom = 0.5
	_hand.offset_left = -19
	_hand.offset_top = -3
	root.add_child(_hand)
	# the aiming point: a small ring with a dot, wider while it is on something that can be clicked
	_cross = ColorRect.new()
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.anchor_left = 0.5
	_cross.anchor_right = 0.5
	_cross.anchor_top = 0.5
	_cross.anchor_bottom = 0.5
	_cross.offset_left = -11
	_cross.offset_right = 11
	_cross.offset_top = -11
	_cross.offset_bottom = 11
	var cs := Shader.new()
	cs.code = "shader_type canvas_item;
uniform float hot = 0.0;
void fragment() { float d = length(UV - 0.5) * 22.0; float r = mix(5.0, 8.0, hot);
	float ring = (1.0 - smoothstep(0.6, 1.3, abs(d - r))) * hot; float dot = 1.0 - smoothstep(1.4, 2.2, d);
	float edge = (1.0 - smoothstep(1.3, 2.4, abs(d - r))) * hot + (1.0 - smoothstep(2.2, 3.2, d));
	float a = max(ring, dot); COLOR = vec4(vec3(1.0, 0.97, 0.9) * a, max(a * 0.95, edge * 0.45)); }"
	var cm := ShaderMaterial.new()
	cm.shader = cs
	_cross.material = cm
	root.add_child(_cross)
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
	row.add_child(h.with_harmony_icon(_purse, 22))
	var shop_b: Button = h._button(tr("home_shop"), false)
	row.add_child(shop_b)
	_help = h._label(tr("home_help"), 12, Color(1, 1, 1, 0.85))
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.offset_left = 20
	_help.offset_top = -30
	_help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_help.add_theme_constant_override("shadow_offset_x", 1)
	_help.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(_help)
	shop = Shop.new()
	root.add_child(shop)
	shop.setup(self)
	shop_b.pressed.connect(shop.toggle)
	_tip = _note(root, h)
	_toast = _note(root, h)
	_food = _note(root, h)                       # (the tanks whose sugar or protein is running out: _check_food)
	_food.add_theme_color_override("font_color", Color(0.75, 0.33, 0.05))
	_food.position = Vector2(20, 56)
	_set_clock()


## The room (again after something is bought): the tanks where home_store.places() puts them.
func rebuild_room() -> void:
	if _room != null and is_instance_valid(_room):
		_room.queue_free()
	_room = Room.new()
	_room.lamp_on = bool(main._settings.get("home_lamp", true))
	_vp.add_child(_room)
	_room.build(main.home.places(), main.home.shelves, func(s): return Store.exists(s), _hour(), _env)
	_hot = null


## A short note on paper under the bar, gone after a moment.
func toast(text: String, at := Vector2(-1, -1)) -> void:
	_toast.text = text
	_toast.reset_size()
	_toast.position = at if at.x >= 0.0 else Vector2((get_viewport().get_visible_rect().size.x - _toast.size.x) * 0.5, 70)
	_toast.visible = true
	_toast_t = 2.5


## A note on paper beside the hand.
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


## The hour now, on the computer's clock (--home-hour=<h>: dev, a fixed hour).
func _hour() -> float:
	if main._opts.has("home-hour"):
		return float(main._opts["home-hour"])
	var t := Time.get_datetime_dict_from_system()
	return float(t.hour) + float(t.minute) / 60.0


func _set_clock() -> void:
	if _room != null and is_instance_valid(_room):
		_room.set_hour(_hour())


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
	_free = false
	_seated = false
	_move_t = 1.0
	_aim()
	_update_purse()
	_check_food()


## The keeper's colonies about to run out of sugar or protein (the keeper, 2026-10-27: "sometimes I forget"): the one
## open now from the simulation itself, the others from what they were when saved (save_store meta: sugar_days,
## protein_days - sim.food_days); under 2 game days (hud_controls.FOOD_WARN_DAYS). A founding queen and a colony
## without workers are not warned about.
func _check_food() -> void:
	var lines := []
	for p in main.home.places():
		var s: int = p.slot
		var w := ""
		if s == main.slot and not main._demo and main.sim != null and main.sim.scenario != "wild":
			w = main.hud.food_warning()
		else:
			var m: Dictionary = Store.meta(s)
			if m.is_empty() or int(m.get("workers", 0)) == 0 or bool(m.get("founding", false)):
				continue
			var parts := []
			for k in [["sugar_days", "food_low_sugar"], ["protein_days", "food_low_protein"]]:
				var d := float(m.get(k[0], 999.0))
				if d < main.hud.FOOD_WARN_DAYS:
					parts.append(tr(k[1]) % ("%.1f" % d))
			w = " · ".join(parts)
		if w != "":
			lines.append(tr("home_food_low") % [p.number, w])
	_food.text = ("⚠ " + "\n⚠ ".join(lines)) if not lines.is_empty() else ""
	_food.visible = not lines.is_empty()
	_food.reset_size()


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
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _leave() -> void:
	is_open = false
	visible = false
	get_viewport().disable_3d = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for c in get_children():
		c.queue_free()


func _update_purse() -> void:
	var p: float = main.harmony.points
	_purse.text = tr("home_purse") % (Shop.num(p) if p >= 100.0 else "%.1f" % p)
	if shop.visible and shop.purse != null and is_instance_valid(shop.purse):
		shop.purse.text = _purse.text


func _aim() -> void:
	if _move_t >= 1.0:
		_cam.rotation = Vector3(_pitch, _yaw, 0.0)


## The pointer: held in the middle (turning the view) unless the keeper freed it (Tab), the shop is open, or a window
## (a new colony, a question) is up.
func _pointer_free() -> bool:
	return _free or shop.visible or not get_viewport().get_embedded_subwindows().is_empty() or (main._opts.has("shot") and not main._opts.has("home-aim"))


func _process(delta: float) -> void:
	if not is_open:
		return
	var free := _pointer_free()
	var want := Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want:
		Input.mouse_mode = want
	_hand.visible = not free and _hand3d == null
	_cross.visible = not free and bool(main._settings.get("home_cross", true))
	if not free:
		_point(get_viewport().get_visible_rect().size * 0.5)
	# sitting down, getting up
	if _move_t < 1.0:
		_move_t = minf(1.0, _move_t + delta / SIT_S)
		var k := smoothstep(0.0, 1.0, _move_t)
		_cam.transform = _move_from.interpolate_with(_move_to, k)
		if _move_t >= 1.0:
			_aim()
	var mv := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if mv != Vector2.ZERO and _move_t >= 1.0:
		if _seated:
			_stand()
		else:
			_walk(mv, delta)
	if _hand3d != null:
		_hand3d.point(_hot != null)
		_hand3d.tick(delta, mv != Vector2.ZERO and not _seated)
	if _toast.visible:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.visible = false
	_clock_t += delta
	if _clock_t > 20.0:
		_clock_t = 0.0
		_set_clock()                                 # (the sun moves on)
		_check_food()
	_update_purse()


func _walk(mv: Vector2, delta: float) -> void:
	var step := mv.normalized().rotated(-_yaw) * WALK * delta
	var p := _cam.position + Vector3(step.x, 0, step.y)
	var lim: float = Room.W * 0.5 - MARGIN
	p.x = clampf(p.x, -lim, lim)
	p.z = clampf(p.z, -lim, lim)
	# (not through the desk, the chair or a shelf: each way on its own, so the keeper slides along it; one already in
	# something's room - got up from the chair, or a shelf bought where they stood - walks out of it freely)
	var q := _cam.position
	if _blocked(Vector2(q.x, q.z)):
		_cam.position = p
		return
	if _blocked(Vector2(p.x, q.z)):
		p.x = q.x
	if _blocked(Vector2(p.x, p.z)):
		p.z = q.z
	_cam.position = p


func _blocked(at: Vector2) -> bool:
	for r in _room.blocks:
		if (r as Rect2).grow(0.25).has_point(at):
			return true
	return false


## On the chair: the eyes lowered to a seated keeper's, facing the desk.
func _sit(it) -> void:
	_seated = true
	_move_from = _cam.transform
	var seat: Vector3 = it.seat
	_yaw = float(it.face)
	_pitch = -0.45
	_move_to = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0.0)), Vector3(seat.x, EYE_SEATED, seat.z))
	_move_t = 0.0


func _stand() -> void:
	_seated = false
	_move_from = _cam.transform
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw)) * 0.55          # (a step back from the desk)
	var p := Vector3(_cam.position.x, EYE, _cam.position.z) + back
	_move_to = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0.0)), p)
	_move_t = 0.0


func _on_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT and _hand3d != null:
			_hand3d.poke()
		if e.button_index == MOUSE_BUTTON_LEFT and _hot != null:
			_click(_hot)
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam.fov = maxf(35.0, _cam.fov - 3.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam.fov = minf(70.0, _cam.fov + 3.0)
	elif e is InputEventMouseMotion and _pointer_free():
		_point(e.position)


func _input(e: InputEvent) -> void:
	if not is_open or not (e is InputEventMouseMotion) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_yaw -= e.relative.x * LOOK
	_pitch = clampf(_pitch - e.relative.y * LOOK, -1.3, 1.1)
	_aim()


## What the hand is on: the nearest item the view's ray through that point goes into.
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
		_hand.texture = _hand_open if best == null else _hand_point
		(_cross.material as ShaderMaterial).set_shader_parameter("hot", 0.0 if best == null else 1.0)
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
	if it.kind == "lamp":
		return tr("home_lamp_off") if _room.lamp_on else tr("home_lamp_on")
	if it.kind == "fridge":
		var r: Array = it.resting
		return tr("home_fridge_none") if r.is_empty() else tr("home_fridge") % ", ".join(r.map(func(n): return str(n)))
	if it.kind == "chair":
		return tr("home_stand") if _seated else tr("home_chair")
	var s: int = it.slot
	var m: Dictionary = Store.meta(s)
	if m.is_empty():
		return tr("home_tank_empty") % it.number
	return tr("home_tank") % [it.number, m.get("day", 1), m.get("workers", 0),
		"" if m.get("queen", true) else tr("title_queen_dead")]


func _click(it) -> void:
	if it.kind == "door":
		toast(tr("home_soon"), _tip.position + Vector2(0, 40))
		return
	if it.kind == "fridge":
		return
	if it.kind == "lamp":
		# its switch (kept in the settings: the lamp round a box in the game is the same lamp - keeper_room.gd)
		_room.lamp_on = not _room.lamp_on
		main._settings["home_lamp"] = _room.lamp_on
		Store.save_settings(main._settings)
		_set_clock()
		_tip.text = _describe(it)
		return
	if it.kind == "chair":
		if _seated:
			_stand()
		else:
			_sit(it)
		return
	var s: int = it.slot
	if not Store.exists(s):
		main.hud.open_species(s, false, "keeper", main.home.nest_of(s))
		return
	if s == main.slot and not main._demo:
		_leave()
		main.title.visible = true
		main.title.close()                      # (the colony already open: straight into it)
		return
	_leave()
	main._go_to(s, "")


func _unhandled_key_input(e: InputEvent) -> void:
	if not is_open or not (e is InputEventKey and e.pressed and not e.echo):
		return
	if e.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif e.keycode == KEY_TAB:
		_free = not _free                        # (the pointer for the bar at the top, or back to turning the view)
		get_viewport().set_input_as_handled()
