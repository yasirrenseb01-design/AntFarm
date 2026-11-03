extends RefCounted
## What the Home's shop sells, as it will stand in the room (the keeper, 2026-11-03: "show what is bought as a small
## square, or press + to see the 3D model first"): the room's own builders (view/home/home_room.gd - the tank, the
## shelves) make the model in a little world of its own; thumb() is the square on the shop's row, open() the large
## view, turning slowly, dragged round by the mouse, closed by its button or a click outside it.

const Room := preload("res://scripts/view/home/home_room.gd")
const Paper := preload("res://scripts/view/ui/paper.gd")


## The item's model (a tank with its soil - glass alone hardly showed; a shelf without tanks), its foot at the origin.
static func model(item: String) -> Node3D:
	var r = Room.new()
	match item:
		"big", "small":
			r._tank(r, Vector3.ZERO, item == "big", false, -1, 0, true, 0.0)      # (slot -1: no colony's pictures, plain soil)
		"shelf2", "shelf4":
			var u: Node3D = r._shelf(0, 2 if item == "shelf2" else 4)
			u.position = Vector3.ZERO
			u.rotation = Vector3.ZERO
	return r


## The box round everything drawn under n.
static func _bounds(n: Node, xf := Transform3D.IDENTITY) -> AABB:
	var out := AABB()
	var first := true
	for c in n.get_children():
		if not c is Node3D:
			continue
		var cx: Transform3D = xf * (c as Node3D).transform
		var b := AABB()
		var has := false
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			b = cx * (c as MeshInstance3D).mesh.get_aabb()
			has = true
		var sub := _bounds(c, cx)
		if sub.size != Vector3.ZERO:
			b = b.merge(sub) if has else sub
			has = true
		if has:
			out = b if first else out.merge(b)
			first = false
	return out


## A little world showing the model from the front and a little above, lit as the room is by day; turn: its yaw.
static func _stage(item: String, px: Vector2i, turn: float) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = px
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	var holder := Node3D.new()
	holder.name = "Holder"
	vp.add_child(holder)
	var m := model(item)
	holder.add_child(m)
	var b := _bounds(m)
	m.position = -b.get_center()
	holder.rotation.y = turn
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.79, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.8, 0.72)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var cam := Camera3D.new()
	cam.environment = env
	cam.fov = 30.0
	var size := b.size.length()
	cam.position = Vector3(0.0, size * 0.55, size * 1.75)
	vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3.ZERO, Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.2
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(30), 0)
	vp.add_child(sun)
	return vp


## The square on the shop's row: the model, and + in its corner (pressed: the large view).
static func thumb(item: String, host: Control) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(96, 72)
	var view := SubViewportContainer.new()
	view.stretch = true
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_stage(item, Vector2i(192, 144), 0.45))
	box.add_child(view)
	var frame := Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.draw_center = false
	fsb.border_color = Paper.INK.lerp(Paper.PENCIL, 0.4)
	fsb.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(frame)
	var plus := Button.new()
	plus.text = "+"
	plus.focus_mode = Control.FOCUS_NONE
	plus.tooltip_text = TranslationServer.translate("shop_view_3d")
	plus.anchor_left = 1.0
	plus.anchor_right = 1.0
	plus.anchor_top = 1.0
	plus.anchor_bottom = 1.0
	plus.offset_left = -24
	plus.offset_top = -24
	plus.offset_right = -2
	plus.offset_bottom = -2
	plus.pressed.connect(func(): open(item, host))
	box.add_child(plus)
	return box


## The large view over the room: the model turning slowly, a drag turns it, Close (or a click beside it) puts it away.
static func open(item: String, host: Control) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(shade)
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", Paper.page(16, 14))
	page.set_anchors_preset(Control.PRESET_CENTER)
	page.grow_horizontal = Control.GROW_DIRECTION_BOTH
	page.grow_vertical = Control.GROW_DIRECTION_BOTH
	shade.add_child(page)
	var col := VBoxContainer.new()
	page.add_child(col)
	var view := SubViewportContainer.new()
	view.stretch = true
	view.custom_minimum_size = Vector2(560, 400)
	var vp := _stage(item, Vector2i(560, 400), 0.45)
	view.add_child(vp)
	col.add_child(view)
	var hint := Label.new()
	hint.text = TranslationServer.translate("shop_view_hint")
	hint.add_theme_color_override("font_color", Paper.PENCIL)
	hint.add_theme_font_size_override("font_size", 12)
	col.add_child(hint)
	var close := Button.new()
	close.text = TranslationServer.translate("shop_view_close")
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(close)
	var holder: Node3D = vp.get_node("Holder")
	var state := {"drag": false, "idle": 0.0}
	view.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			state.drag = e.pressed
		elif e is InputEventMouseMotion and state.drag:
			holder.rotation.y += e.relative.x * 0.01
			holder.rotation.x = clampf(holder.rotation.x + e.relative.y * 0.006, -0.5, 0.6)
			state.idle = 0.0)
	var timer := Timer.new()
	timer.wait_time = 1.0 / 30.0
	timer.autostart = true
	timer.timeout.connect(func():
		state.idle = float(state.idle) + timer.wait_time
		if not state.drag and float(state.idle) > 1.5:
			holder.rotation.y += 0.25 * timer.wait_time)        # (turning slowly by itself until dragged)
	shade.add_child(timer)
	close.pressed.connect(func(): shade.queue_free())
	shade.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and not page.get_global_rect().has_point(e.global_position):
			shade.queue_free())
