extends "res://scripts/game/parts/main_base.gd"
## Game, layer 2 of 4: the top-down camera and the HUD's camera buttons for every view.


# ---------------------------------------------------------------- camera

func _view_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(Vector2.ZERO, Vector2(vp.x - hud.PANEL_W - 12, vp.y))


func _fit_zoom() -> float:
	var area := _view_rect()
	return minf(area.size.x / sim.WORLD.x, area.size.y / sim.WORLD.y) * 0.97


func _fit_camera() -> void:
	_zoom_t = _fit_zoom()
	_pos_t = _centre_offset(sim.WORLD * 0.5, _zoom_t)


func _centre_offset(p: Vector2, z: float) -> Vector2:
	# keep point p in the middle of the area left of the side panel
	var vp := get_viewport_rect().size
	return p + Vector2((vp.x * 0.5 - _view_rect().size.x * 0.5) / z, 0)


func _center_on(p: Vector2) -> void:
	_pos_t = _centre_offset(p, _zoom_t)
	camera.position = _pos_t
	camera.zoom = Vector2.ONE * _zoom_t


## World point under a screen position, using where the camera is heading (not where it is now).
func _screen_to_world_t(sp: Vector2) -> Vector2:
	return _pos_t + (sp - get_viewport_rect().size * 0.5) / _zoom_t


func surface_zoom(f: float, at_screen := Vector2.INF) -> void:
	var sp := at_screen if at_screen != Vector2.INF else _view_rect().get_center()
	var before := _screen_to_world_t(sp)
	_zoom_t = clampf(_zoom_t * f, _fit_zoom(), 8.0)
	_pos_t += before - _screen_to_world_t(sp)
	_clamp_camera()


func surface_focus(p: Vector2, zoom: float) -> void:
	_zoom_t = clampf(zoom, _fit_zoom(), 8.0)
	_pos_t = _centre_offset(p, _zoom_t)


func _ease_surface(delta: float) -> void:
	# keyboard: WASD / arrows move, +/- zoom
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv.y += 1
	if mv != Vector2.ZERO:
		_pos_t += mv * 700.0 * delta / _zoom_t
		_clamp_camera()
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		surface_zoom(1.0 + 1.6 * delta)
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		surface_zoom(1.0 / (1.0 + 1.6 * delta))
	var k := 1.0 - exp(-12.0 * delta)
	camera.zoom = Vector2.ONE * lerpf(camera.zoom.x, _zoom_t, k)
	camera.position = camera.position.lerp(_pos_t, k)


func _clamp_camera() -> void:
	var margin := Vector2(200, 200) / _zoom_t
	_pos_t = _pos_t.clamp(-margin, sim.WORLD + margin)


## Camera buttons on the HUD, shared by both views.
func _cam_action(a: String) -> void:
	if mode == "outworld":
		match a:
			"zoom_in": outworld.zoom_by(1.0 / 1.4)
			"zoom_out": outworld.zoom_by(1.4)
			"left": outworld.turn_by(0.5)
			"right": outworld.turn_by(-0.5)
			"reset": outworld.reset_view()
			"top": outworld.top_down()
			"nest": outworld.focus_nest()
	elif mode == "surface":
		match a:
			"zoom_in": surface_zoom(1.5)
			"zoom_out": surface_zoom(1.0 / 1.5)
			"reset": _fit_camera()
			"nest": surface_focus(sim.nest_pos, 3.0)
	else:
		match a:
			"zoom_in": nest_view.zoom_by(1.0 / 1.4)
			"zoom_out": nest_view.zoom_by(1.4)
			"left": nest_view.turn_by(0.5)
			"right": nest_view.turn_by(-0.5)
			"reset": nest_view.reset_view()
			_: nest_view.focus(a)
