extends "res://scripts/view/nest/parts/nest_scene.gd"
## Nest view, layer 2 of 8: the orbit camera, the cut plane, x-ray and focusing on places.


func snap_camera() -> void:
	yaw_t = yaw
	pitch_t = pitch
	dist_t = cam_dist
	target_t = target


func _ease_camera(delta: float) -> void:
	# keyboard: WASD / arrows move, Q/E turn, R/F tilt, +/- zoom
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv.y -= 1
	if mv != Vector2.ZERO:
		var right := _cam.global_transform.basis.x
		target_t += (right * mv.x + Vector3.UP * mv.y) * dist_t * 0.9 * delta
	if Input.is_key_pressed(KEY_Q):
		yaw_t += 1.4 * delta
	if Input.is_key_pressed(KEY_E):
		yaw_t -= 1.4 * delta
	if Input.is_key_pressed(KEY_R):
		pitch_t = clampf(pitch_t + 0.9 * delta, -0.2, 1.45)
	if Input.is_key_pressed(KEY_F):
		pitch_t = clampf(pitch_t - 0.9 * delta, -0.2, 1.45)
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		zoom_by(1.0 - 1.6 * delta)
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		zoom_by(1.0 + 1.6 * delta)
	var lo := Vector3(-30, -20, -30)
	var hi := Vector3(nest.nx + 30, nest.ny + 30, nest.nz + 30)
	target_t = target_t.clamp(lo, hi)
	var k := 1.0 - exp(-10.0 * delta)
	yaw = lerp_angle(yaw, yaw_t, k)
	pitch = lerpf(pitch, pitch_t, k)
	cam_dist = lerpf(cam_dist, dist_t, k)
	target = target.lerp(target_t, k)


func zoom_by(f: float) -> void:
	dist_t = clampf(dist_t * f, 6.0, 400.0)


func turn_by(a: float) -> void:
	yaw_t += a


func reset_view() -> void:
	if nest.slab:
		yaw_t = 0.0
		pitch_t = 0.12
		dist_t = 150.0
		target_t = Vector3(nest.nx / 2.0, nest.ny / 2.0 + 6.0, nest.nz / 2.0)
	elif nest.chambers.size() == 1:
		# a lone founding queen: start close on her chamber, with the cut just in front of it
		var c: Vector3 = nest.chambers[0].c
		yaw_t = 0.35
		pitch_t = 0.25
		dist_t = 32.0
		target_t = c
		# slice straight through her chamber
		var dir := Vector3(sin(yaw_t), 0, cos(yaw_t))
		cut_offset = clampf(dir.dot(c) - dir.dot(Vector3(nest.nx / 2.0, 0, nest.nz / 2.0)) + 1.0, -32, 32)
		cut_changed.emit(cut_offset)
	else:
		yaw_t = 0.55
		pitch_t = 0.22
		dist_t = 75.0
		target_t = Vector3(nest.nx / 2.0, nest.ny - 16.0, nest.nz / 2.0)


## Glide the camera to something worth looking at: "queen", "larvae", "pupae", "entrance".
func focus(what: String) -> void:
	var p := Vector3.INF
	match what:
		"queen":
			p = _spots.queen if _spots.queen != Vector3.ZERO else p
		"larvae":
			if not _spots.larvae.is_empty():
				p = _spots.larvae[_spots.larvae.size() / 2]
		"pupae":
			if not _spots.pupae.is_empty():
				p = _spots.pupae[_spots.pupae.size() / 2]
		"entrance":
			p = Vector3(nest.entrance)
			dist_t = 45.0
	if p == Vector3.INF:
		return
	target_t = p
	if what != "entrance":
		dist_t = minf(dist_t, 26.0)
	if not xray and not nest.slab:
		# slide the cut so the spot sits just behind it
		var dir := Vector3(sin(yaw_t), 0, cos(yaw_t))
		cut_offset = clampf(dir.dot(p) - dir.dot(Vector3(nest.nx / 2.0, 0, nest.nz / 2.0)) + 1.5, -32, 32)
		cut_changed.emit(cut_offset)


## Double-click: fly to the chamber (or queen) nearest the mouse.
func _focus_at(screen: Vector2) -> void:
	var best := Vector3.INF
	var bd := 140.0
	var cands: Array = []
	for r in _rooms:
		cands.append(Vector3(r.cell))
	if _spots.queen != Vector3.ZERO:
		cands.append(_spots.queen)
	cands.append(Vector3(nest.entrance))
	for c in cands:
		if _cam.is_position_behind(c):
			continue
		var d := _cam.unproject_position(c).distance_to(screen)
		if d < bd:
			bd = d
			best = c
	if best != Vector3.INF:
		target_t = best
		dist_t = minf(dist_t, 30.0)


func _update_camera() -> void:
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	_cam.position = target + dir * cam_dist
	_cam.look_at(target, Vector3.UP)
	_frustum = _cam.get_frustum()
	if nest.slab:
		# a glass ant farm is watched through the front pane: show the soil right behind the glass
		_plane_n = Vector3(0, 0, 1)
		_plane_w = nest.nz - 1.6
		return
	var h := Vector3(dir.x, 0, dir.z).normalized()
	_plane_n = h
	var centre := Vector3(nest.nx / 2.0, 0, nest.nz / 2.0)
	_plane_w = h.dot(centre) + cut_offset


func set_xray(on: bool) -> void:
	xray = on
	_ghost.visible = on
	for k in _chunks:
		_chunks[k].material_override = _xray_mat if on else _mat
	_brood_sig = []


func _visible(p: Vector3) -> bool:
	# on screen (with a margin for a body and its shadow): what is not is not sent to the graphics card at all -
	# every ant drawn costs its pose and its shadow passes, seen or not
	for pl in _frustum:
		if pl.distance_to(p) > 3.0:
			return false
	if xray:
		return true
	return _plane_n.dot(p) <= _plane_w + 0.3
