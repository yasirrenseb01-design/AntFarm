extends "res://scripts/view/outworld/parts/outworld_dumpers.gd"
## Outworld view, layer 4 of 5: the orbit camera and picking points on the ground.


# ---------------------------------------------------------------- camera

var follow_cid := 0          # an enemy the camera keeps in view (the HUD's enemy panel), 0 = none
var follow_wid := -1         # a worker the camera keeps in view (the HUD's star ants panel), -1 = none


## Keeps a worker in view while it is outside (the HUD's star ants panel), until the keeper moves the camera.
func follow_ant(id: int) -> void:
	follow_wid = id
	follow_cid = 0
	dist_t = minf(dist_t, 60.0)
	pitch_t = clampf(pitch_t, 0.6, 1.1)


## Keeps an enemy in view (sim.creatures id): the camera eases to it and rides along until it is gone or the keeper
## moves the camera.
func follow_creature(id: int) -> void:
	follow_cid = id
	follow_wid = -1
	dist_t = minf(dist_t, 110.0)
	pitch_t = clampf(pitch_t, 0.6, 1.1)


func snap_camera() -> void:
	yaw = yaw_t
	pitch = pitch_t
	cam_dist = dist_t
	target = target_t
	_update_camera()


func _fit_dist() -> float:
	var vp := get_viewport().get_visible_rect().size
	var area_w := maxf(200.0, vp.x - side_px)
	var tanh := tan(deg_to_rad(_cam.fov * 0.5))
	var by_w: float = sim.WORLD.x * U * 1.06 / area_w * vp.y / (2.0 * tanh)
	var by_h: float = sim.WORLD.y * U * 1.1 * sin(pitch_t) / (2.0 * tanh) + 40.0
	# (the box's rim, nearer the camera than the ground, in view too: a keeper's box is 20 cm tall - v0.11.52)
	return maxf(by_w, by_h) + (wall_h * 1.6 if sim.scenario != "wild" else 0.0)


func reset_view() -> void:
	follow_cid = 0
	follow_wid = -1
	yaw_t = 0.0
	pitch_t = 0.95
	target_t = Vector3(sim.WORLD.x * U * 0.5, 0, sim.WORLD.y * U * 0.5 + 6.0)
	dist_t = _fit_dist()


func top_down() -> void:
	follow_cid = 0
	follow_wid = -1
	yaw_t = 0.0
	pitch_t = 1.5
	target_t = Vector3(sim.WORLD.x * U * 0.5, 0, sim.WORLD.y * U * 0.5)
	dist_t = _fit_dist()


func focus_nest() -> void:
	follow_cid = 0
	follow_wid = -1
	target_t = _on_ground(sim.nest_pos)
	dist_t = 60.0
	pitch_t = clampf(pitch_t, 0.6, 1.1)


func zoom_by(f: float) -> void:
	dist_t = clampf(dist_t * f, 8.0, 900.0)


func turn_by(a: float) -> void:
	yaw_t += a


## A camera key held down - not while the keeper is typing (an ant's name: the letters are camera keys too).
func _key(k: Key) -> bool:
	return Input.is_key_pressed(k) and not (get_viewport().gui_get_focus_owner() is LineEdit)


func _ease_camera(delta: float) -> void:
	var mv := Vector2.ZERO
	if _key(KEY_A) or _key(KEY_LEFT):
		mv.x -= 1
	if _key(KEY_D) or _key(KEY_RIGHT):
		mv.x += 1
	if _key(KEY_W) or _key(KEY_UP):
		mv.y += 1
	if _key(KEY_S) or _key(KEY_DOWN):
		mv.y -= 1
	if mv != Vector2.ZERO:
		target_t += (_right() * mv.x + _forward() * mv.y) * dist_t * 0.9 * delta
		follow_cid = 0
		follow_wid = -1
	if follow_cid != 0:
		var c = sim._creature(follow_cid)
		if c == null:
			follow_cid = 0                    # it left, or the ants killed it (the camera stays on where it fell)
			follow_wid = -1
		else:
			target_t = _on_ground((c.pos as Vector2).clamp(Vector2.ZERO, sim.WORLD))
	if follow_wid >= 0:
		var w = null
		for o in sim.outside:
			if o.id == follow_wid:
				w = o
		if w == null:
			follow_wid = -1                   # it went in (the HUD follows it into the nest) or died
		else:
			var at: Vector2 = w.vpos if (w.vpos as Vector2).x != INF else w.pos
			target_t = _on_ground(at.clamp(Vector2.ZERO, sim.WORLD))
	# (Q/E the camera down and up - nearer the ground or farther - and Z/C turn: the same keys as in the nest)
	if _key(KEY_Q):
		zoom_by(1.0 - 1.2 * delta)
	if _key(KEY_E):
		zoom_by(1.0 + 1.2 * delta)
	if _key(KEY_Z):
		yaw_t += 1.4 * delta
	if _key(KEY_C):
		yaw_t -= 1.4 * delta
	if _key(KEY_R):
		pitch_t = clampf(pitch_t + 0.9 * delta, 0.12, 1.54)
	if _key(KEY_F):
		pitch_t = clampf(pitch_t - 0.9 * delta, 0.12, 1.54)
	if _key(KEY_EQUAL) or _key(KEY_KP_ADD):
		zoom_by(1.0 - 1.6 * delta)
	if _key(KEY_MINUS) or _key(KEY_KP_SUBTRACT):
		zoom_by(1.0 + 1.6 * delta)
	var hi := Vector3(sim.WORLD.x * U + 30.0, 0, sim.WORLD.y * U + 30.0)
	target_t = target_t.clamp(Vector3(-30, 0, -30), hi)
	target_t.y = clampf(ground_h(target_t.x, target_t.z), -2.0, 3.0)
	var k := 1.0 - exp(-10.0 * delta)
	yaw = lerp_angle(yaw, yaw_t, k)
	pitch = lerpf(pitch, pitch_t, k)
	cam_dist = lerpf(cam_dist, dist_t, k)
	target = target.lerp(target_t, k)


func _right() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


func _forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func _update_camera() -> void:
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	_cam.position = target + dir * cam_dist
	_cam.look_at(target, Vector3.UP if pitch < 1.55 else _forward())
	# keep the point of interest in the middle of the area left of the side panel
	var vp := get_viewport().get_visible_rect().size
	_cam.h_offset = side_px * 0.5 * 2.0 * cam_dist * tan(deg_to_rad(_cam.fov * 0.5)) / vp.y


## Point on the ground under a screen position (INF if the ray misses).
func pick(sp: Vector2) -> Vector3:
	var o := _cam.project_ray_origin(sp)
	var d := _cam.project_ray_normal(sp)
	if d.y > -0.01:
		return Vector3.INF
	var h := 0.0
	var p := Vector3.INF
	for i in 3:
		var t := (h - o.y) / d.y
		p = o + d * t
		h = ground_h(p.x, p.z)
	return p


func _px(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) / U
