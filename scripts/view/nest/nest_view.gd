extends "res://scripts/view/nest/parts/nest_mates.gd"
## 3D view of the underground nest: the soil block sliced open by a camera-facing cut plane, with
## diggers from the simulation, resting nestmates, brood piles and the queen. This file is the top of
## the chain: building the scene, switching on/off, the per-frame update and input.
## Layers: parts/nest_scene <- nest_camera <- nest_brood <- nest_piles <- nest_lifecycle <- nest_bodies <- nest_mates <- nest_view (see docs/ARCHITECTURE.md).


func setup(s) -> void:
	sim = s
	nest = sim.nest
	_feed = EventFeed.new(sim)
	target = Vector3(nest.nx / 2.0, nest.ny - 16.0, nest.nz / 2.0)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.035, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.45, 0.38)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.25

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 38
	_cam.far = 3000
	_cam.environment = env           # each 3D view has its own lighting mood
	add_child(_cam)
	var lamp := OmniLight3D.new()       # keeper's lamp riding with the camera so the cut face is lit
	lamp.light_color = Color(1.0, 0.85, 0.7)
	lamp.light_energy = 0.9
	lamp.omni_range = 600
	lamp.omni_attenuation = 0.6
	_cam.add_child(lamp)

	var grain := NoiseTexture2D.new()
	grain.width = 256
	grain.height = 256
	grain.seamless = true
	var gn := FastNoiseLite.new()
	gn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	gn.frequency = 0.03
	gn.fractal_octaves = 4
	grain.noise = gn
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/terrain/soil.gdshader")
	_mat.set_shader_parameter("grain", grain)
	_mat.set_shader_parameter("top_y", nest.ny - 0.5)
	_mat.set_shader_parameter("vol_size", Vector3(nest.nx, nest.ny, nest.nz))
	_xray_mat = ShaderMaterial.new()
	_xray_mat.shader = load("res://shaders/terrain/xray.gdshader")
	_xray_mat.set_shader_parameter("box_max", Vector3(nest.nx - 1, nest.ny - 1, nest.nz - 1))
	_xray_mat.set_shader_parameter("top_y", nest.ny - 0.5)
	_xray_mat.set_shader_parameter("grain", grain)
	_ghost = MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(nest.nx, nest.ny, nest.nz)
	_ghost.mesh = gb
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.42, 0.3, 0.2, 0.12)
	gm.cull_mode = BaseMaterial3D.CULL_FRONT
	gm.no_depth_test = false
	gm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_ghost.material_override = gm
	_ghost.position = Vector3(nest.nx / 2.0 - 0.5, nest.ny / 2.0 - 0.5, nest.nz / 2.0 - 0.5)
	_ghost.visible = false
	add_child(_ghost)
	_upload_volume()

	# the shelf the block sits on
	var shelf := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	shelf.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.07, 0.06, 0.06)
	sm.roughness = 0.7
	shelf.material_override = sm
	shelf.position = Vector3(nest.nx / 2.0, -1.0, nest.nz / 2.0)
	add_child(shelf)

	# Lasius niger: glossy dark body with a fine pubescence that gives the gaster a dull sheen
	# legs, antennae, head, mandibles and gaster are animated per ant by shaders/ant.gdshader
	var ant_mat := ShaderMaterial.new()
	ant_mat.shader = load("res://shaders/ants/ant.gdshader")
	_ant_meshes = {"hi": AntModel.make(), "lo": AntModel.make(0.0, false, false)}
	_ant_mm = _multimesh(_ant_meshes.lo, ant_mat, true)
	_ant_shader_mat = ant_mat
	_ant_mm.use_custom_data = true
	var egg_mat := _mat_simple(Color(0.95, 0.96, 0.95, 0.88), 0.12)     # translucent, glossy white
	egg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	egg_mat.rim_enabled = true
	egg_mat.rim = 0.5
	_egg_mm = _multimesh(_ellipsoid(0.32, 0.2), egg_mat, false)
	var larva_mesh: Mesh = Props.larva()
	var cocoon_mesh: Mesh = Props.cocoon()
	var larva_mat := _mat_vc(0.3)
	var cocoon_mat := _mat_vc(0.85)
	_larva_mm = _multimesh(larva_mesh, larva_mat, false)
	_pupa_mm = _multimesh(cocoon_mesh, cocoon_mat, true)
	_pellet_mm = _multimesh(_ellipsoid(0.42, 0.34), _mat_simple(Color(0.42, 0.3, 0.2), 0.95), false, false)
	_carry_larva_mm = _multimesh(larva_mesh, larva_mat, false)
	_carry_pellet_mm = _multimesh(_ellipsoid(0.8, 0.65), _mat_simple(Color(0.45, 0.32, 0.2), 0.95), false)
	_fx_egg_mm = _multimesh(_ellipsoid(0.32, 0.2), egg_mat, false)
	_fx_larva_mm = _multimesh(larva_mesh, larva_mat, false)
	var silk := StandardMaterial3D.new()
	silk.albedo_color = Color(0.97, 0.95, 0.9)
	silk.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	silk.vertex_color_use_as_albedo = true
	silk.roughness = 0.9
	_fx_silk_mm = _multimesh(_ellipsoid(1.35, 0.62), silk, true)
	_fx_cocoon_mm = _multimesh(cocoon_mesh, cocoon_mat, true)
	_carry_cocoon_mm = _multimesh(cocoon_mesh, cocoon_mat, false)
	_carry_shell_mm = _multimesh(cocoon_mesh, cocoon_mat, false)
	_fx_soil_mm = _multimesh(_ellipsoid(0.42, 0.34), _mat_simple(Color(0.42, 0.3, 0.2), 0.95), false)
	var dew := _mat_simple(Color(0.85, 0.55, 0.15, 0.8), 0.1)
	dew.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fx_drop_mm = _multimesh(_ellipsoid(0.16, 0.14), dew, false)
	_bits_mm = _multimesh(_ellipsoid(0.38, 0.26), _mat_simple(Color(0.45, 0.3, 0.18), 0.7), false)
	ant_mat.set_shader_parameter("limb_gain", AntModel.WORKER_LIMBS)
	# feet find the real floor in the soil volume (updated in place as the ants dig)
	ant_mat.set_shader_parameter("ground_mode", 1)
	ant_mat.set_shader_parameter("vol", _vol)
	ant_mat.set_shader_parameter("vol_size", Vector3(nest.nx, nest.ny, nest.nz))
	var queen_mat: ShaderMaterial = ant_mat.duplicate()
	queen_mat.set_shader_parameter("limb_gain", AntModel.QUEEN_LIMBS)
	var queen_mesh := AntModel.make(0.0, true, true)
	_queen_mm = _multimesh(queen_mesh, queen_mat, true)
	_queen_mm.use_custom_data = true
	# the selection outline: the clicked ant's body drawn again, white, from the inside
	var outline: Shader = load("res://shaders/ants/ant_outline.gdshader")
	var sel_mat: ShaderMaterial = ant_mat.duplicate()
	sel_mat.shader = outline
	_sel_mm = _multimesh(_ant_meshes.lo, sel_mat, true, false)
	_sel_mm.use_custom_data = true
	var selq_mat: ShaderMaterial = queen_mat.duplicate()
	selq_mat.shader = outline
	_sel_queen_mm = _multimesh(queen_mesh, selq_mat, true, false)
	# a clicked egg, larva or cocoon: its own shape again, white, grown a little and seen from inside (a rim)
	var selb := StandardMaterial3D.new()
	selb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selb.cull_mode = BaseMaterial3D.CULL_FRONT
	selb.albedo_color = Color.WHITE
	selb.grow = true
	selb.grow_amount = 0.05
	_sel_brood_mm = _multimesh(_egg_mm.mesh, selb, false, false)
	_sel_queen_mm.use_custom_data = true
	_cut_mats = [ant_mat, sel_mat]          # (cut at the cut plane as the soil is; not the queen - she cannot step away from
	                                        # it, and cut open she showed a hollow shell)

	if nest.slab:
		_build_ant_farm_case()
		yaw = 0.0
		pitch = 0.12
		cam_dist = 150.0
		target = Vector3(nest.nx / 2.0, nest.ny / 2.0 + 6.0, nest.nz / 2.0)
	reset_view()
	yaw = yaw_t
	pitch = pitch_t
	cam_dist = dist_t
	target = target_t
	# chunk -1 owns the block faces on the low sides (edges from outside into voxel 0)
	for kz in range(-1, (nest.nz + CH - 1) / CH + 1):
		for ky in range(-1, (nest.ny + CH - 1) / CH + 1):
			for kx in range(-1, (nest.nx + CH - 1) / CH + 1):
				_queue.append(Vector3i(kx, ky, kz))
	nest.dirty.clear()
	visible = false


# ---------------------------------------------------------------- per frame

## Where a worker is drawn in the nest now (INF if it is not: outside, or not drawn as a nestmate) - the title
## screen's camera follows it. The queen: "queen" spot.
func mate_pos(wid: int) -> Vector3:
	for m in _mates:
		if int(m.get("wid", -1)) == wid and m.has("xf"):
			return (m.xf as Transform3D).origin
	# a digger is drawn at the dig face, not as a nestmate: the workers set to dig, lowest id first, one per digger
	# drawn (as pick_ant / info_for pair them)
	var dig_ws: Array = sim.workers.filter(func(w): return w.task == Ant.TASK_DIG and w.state == Ant.IN_NEST)
	dig_ws.sort_custom(func(a, b): return a.id < b.id)
	var ds: Array = nest.diggers.duplicate()
	ds.sort_custom(func(a, b): return a.id < b.id)
	for i in mini(ds.size(), dig_ws.size()):
		if dig_ws[i].id == wid:
			var v: Dictionary = _dig_vis.get(ds[i].id, {})
			if v.has("xf"):
				return (v.xf as Transform3D).origin
	return Vector3.INF


func queen_pos() -> Vector3:
	return _spots.queen if _spots.queen != Vector3.ZERO else Vector3.INF


func brood_pos(kind: String) -> Vector3:
	var at: Array = _spots.get(kind, [])
	return at[at.size() / 2] if not at.is_empty() else Vector3.INF


func set_active(on: bool) -> void:
	active = on
	visible = on
	_cam.current = on
	if on:
		_refresh_spots()
		_feed.skip()                   # what happened while we were away is not replayed


func refresh(delta: float) -> void:
	if not active:
		return
	_t += delta
	var t0 := Time.get_ticks_usec()
	if not nest.dirty.is_empty():
		_vol_dirty = true
		_floor_cache.clear()            # the floor moved: brood is set down on it afresh
		_lift_cache.clear()
		_fit_cache.clear()
		_gfit_cache.clear()
		_soil_gen += 1
	for k in nest.dirty:
		if not _queue.has(k):
			_queue.append(k)
		if not _soft.is_empty():
			_soft_build(k * 16 - Vector3i.ONE, k * 16 + Vector3i(16, 16, 16))     # (nest_voxels CHUNK, and a voxel round it)
	nest.dirty.clear()
	_vol_timer -= delta
	if _vol_dirty and _vol_timer <= 0.0:
		_upload_volume()
	_pump_chunks(_queue)
	t0 = _nprof("soil mesh", t0)
	_ease_camera(delta)
	_update_camera()
	var lod := "hi" if cam_dist < 40.0 else "lo"      # detailed ants only when they are big on screen
	if lod != _lod:
		_lod = lod
		_ant_mm.mesh = _ant_meshes[lod]
		_sel_mm.mesh = _ant_meshes[lod]
		_ant_shader_mat.set_shader_parameter("shadow_pose", lod == "hi")   # zoomed out: shadows in the rest pose
	_mat.set_shader_parameter("cut_plane", Vector4(_plane_n.x, _plane_n.y, _plane_n.z, _plane_w))
	for cm in _cut_mats:
		(cm as ShaderMaterial).set_shader_parameter("cut_plane", Vector4(_plane_n.x, _plane_n.y, _plane_n.z, 100000.0 if xray else _plane_w))
	_mat.set_shader_parameter("humidity", sim.humidity)
	_xray_mat.set_shader_parameter("humidity", sim.humidity)
	_spot_timer -= delta
	if _spot_timer <= 0.0:
		_spot_timer = 1.5
		_refresh_spots()
		_clear_brood_of_ants()        # (and any resting ant whose body lies over the brood gets up)
	# brood and the mound change slowly; rebuild their instances only when something moved
	t0 = _nprof("camera/spots", t0)
	_poll_events()
	_step_anims(delta * minf(speed, 1.0) if speed > 0 else 0.0)     # (slowed with the clock below 1x: slow motion)
	t0 = _nprof("life-cycle", t0)
	var sig := [sim.eggs.size(), sim.larvae.size(), sim.pupae.size(), nest.excavated / 2, snappedf(_plane_w, 0.5),
		snappedf(_plane_n.x, 0.05), _spot_timer > 1.45, _moved, _larva_group, _pending("egg"), _pending("pupate"), int(sim.protein * 1.5), sim.tick / 600,
		snappedf(_queen_turn, 0.12)]          # the queen turning round: the brood round her is laid out again
	if sig != _brood_sig:
		_brood_sig = sig
		_update_brood()
		_clear_brood_of_ants()
	t0 = _nprof("brood layout", t0)
	_queen_pose()
	t0 = _nprof("queen", t0)
	_update_ants(delta)
	t0 = _nprof("nestmates", t0)
	_show_selected_brood()
	_draw_anims()
	_nprof("life-cycle", t0)



# ---------------------------------------------------------------- input

func _unhandled_input(e: InputEvent) -> void:
	if not active:
		return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			zoom_by(1.0 / 1.18)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			zoom_by(1.18)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed and e.double_click:
				_focus_at(e.position)
			_pan = e.pressed and e.shift_pressed
			_rot = e.pressed and not e.shift_pressed
		elif e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE:
			_pan = e.pressed
			_rot = false
	elif e is InputEventMouseMotion:
		if _rot:
			yaw_t -= e.relative.x * 0.007
			pitch_t = clampf(pitch_t + e.relative.y * 0.006, -0.2, 1.45)
		elif _pan:
			var right := _cam.global_transform.basis.x
			var up := _cam.global_transform.basis.y
			target_t += (-right * e.relative.x + up * e.relative.y) * dist_t * 0.0016
	elif e is InputEventKey and e.pressed and e.keycode == KEY_HOME:
		reset_view()


# ---------------------------------------------------------------- dev traces (moved from parts/nest_mates.gd in v0.8.56)

## Dev (--trace): the nestmates within reach of the queen: role, activity, rest/wander left, position.
func trace_near_queen() -> String:
	var out := []
	for m in _mates:
		if m.has("xf") and (m.xf as Transform3D).origin.distance_to(_spots.queen) < 7.0:
			var o: Vector3 = (m.xf as Transform3D).origin
			out.append("%s%s a%d r%d w%d (%.1f,%.1f,%.1f) sep%.2f" % [m.role, "*" if m.has("script") else "", m.act, m.rest, m.wander,
				o.x, o.y, o.z, (m.get("sep", Vector3.ZERO) as Vector3).length()])
	return " | ".join(out)


## Dev (--trace-mates): every nestmate: role, activity, cell, goal room, carrying what, settle/step state.
func trace_mates() -> String:
	var out := []
	for m in _mates:
		var o: Vector3 = (m.xf as Transform3D).origin if m.has("xf") else Vector3(m.cell)
		var line := "w%s %s%s a%d c%s->%s goal%s carry%s/%s r%d w%d t%.2f set%d" % [m.get("wid", -1), m.role,
			"*" if m.has("script") else "", m.act, m.cell, m.to, m.get("goal", -9), m.carry, m.get("item", ""),
			m.rest, m.wander, m.t, (m.get("settle", []) as Array).size()]
		out.append(line + " here%d free%s lift%.2f" % [(_fields.get(m.goal, {}) as Dictionary).get(m.cell, -1), _cell_free(m, m.cell), float(m.get("over", 0.0))])
	for id in _dig_vis:
		out.append("dig%d" % id)
	return " | ".join(out)


## Dev (--trace-crowd, --follow-soil): whether part of a nestmate's body (belly height) is in the soil.
func _ant_in_soil(m: Dictionary) -> bool:
	if not m.has("xf"):
		return false
	# (its body as drawn: head, thorax, gaster at belly height and its sides, the head and gaster bent as the
	# shader bends them to the ground)
	var c := _soil_clearance(m.xf, float(m.size), m.get("bend", Vector2.ZERO))
	return c.x > 0.0 or c.y > 0.0


## Dev (--trace-crowd): where the nestmates are: on the ceiling / walls / floor, by the queen, and per chamber.
func trace_crowd() -> String:
	var ceil := 0
	var wall := 0
	var flr := 0
	var by_q := 0
	var walking := 0
	var by_ent := 0
	var ent_kinds := {}
	for m in _mates:
		var u: Vector3 = m.get("vu", m.up)
		if u.y < -0.3:
			ceil += 1
		elif u.y < 0.7:
			wall += 1
		else:
			flr += 1
		if m.has("xf") and _queen_mm.instance_count > 0 and _queen_gap((m.xf as Transform3D).origin) < 1.5:
			by_q += 1
		if m.act == ACT_WALK:
			walking += 1
		if Vector3(m.cell).distance_to(Vector3(nest.entrance)) < 9.0:
			by_ent += 1
			var key := "%s rest>0:%s stuck-at:%s here:%s" % [m.role, m.rest > 0, m.get("dbg_stuck", -1), (_fields.get(m.goal, {}) as Dictionary).get(m.cell, -1)]
			ent_kinds[key] = ent_kinds.get(key, 0) + 1
	var top := 0
	for m in _mates:
		if m.has("xf") and (m.xf as Transform3D).origin.y > float(nest.ny) - 1.6:
			top += 1
	var dtop := 0
	for v in _dig_vis.values():
		if v.has("xf") and (v.xf as Transform3D).origin.y > float(nest.ny) - 1.6:
			dtop += 1
	var near_mates := _mates.filter(func(q): return q.has("xf"))
	var in_soil := 0
	var why := {}
	for m in near_mates:
		if _ant_in_soil(m):
			in_soil += 1
			# (what it is doing: a hint at why)
			var k := "walking" if float(m.get("mv", 0.0)) > 0.3 else "still"
			if float(m.get("over", 0.0)) > 0.1:
				k += "+climbing"
			if (m.get("sep", Vector3.ZERO) as Vector3).length() > 0.25:
				k += "+pushed"
			if m.has("script"):
				k += "+scripted"
			var up: Vector3 = m.get("vu", m.up)
			k += "/floor" if up.y > 0.7 else ("/ceiling" if up.y < -0.3 else "/wall")
			why[k] = why.get(k, 0) + 1
	var dig_soil := 0
	var dig_why := {}
	for v in _dig_vis.values():
		if not v.has("xf"):
			continue
		var c := _soil_clearance(v.xf, float(v.size), v.get("bend", Vector2.ZERO), float(v.get("still", 0.0)) > 0.25)
		if c.x > 0.0 or c.y > 0.0:
			dig_soil += 1
			var k := ("digging" if float(v.get("still", 0.0)) > 0.25 else "walking") + (" stuck%d" % int(c.y) if c.y > 0 else " rise%.1f" % c.x) + " clr%.1f" % float(v.get("clr", 0.0))
			dig_why[k] = dig_why.get(k, 0) + 1
	if dig_soil > 0:
		print("   diggers in soil: ", dig_why)
	if not why.is_empty() or dig_soil > 0:
		print("   in the soil, by what they do: %s  diggers in the soil: %d of %d" % [why, dig_soil, _dig_vis.size()])
	# feet that cannot reach the ground (the shader sets each foot down on the ground within ~0.5 of where it would
	# stand on a flat floor, x the ant's size) and bodies standing clear above the ground
	var feet_air := 0
	var lifted := 0
	for m in near_mates:
		if not m.has("xf") or m.has("script"):
			continue
		var x: Transform3D = m.xf
		var up := x.basis.y.normalized()
		var sz := x.basis.y.length()
		var n := 0
		for fl in [Vector3(0.9, 0, 1.07), Vector3(0.03, 0, 1.07), Vector3(-0.88, 0, 1.07), Vector3(0.9, 0, -1.07), Vector3(0.03, 0, -1.07), Vector3(-0.88, 0, -1.07)]:
			if _ground_off(x * fl, up) < -0.55 * sz:
				n += 1
		if n >= 2:
			feet_air += 1
		if _ground_off(x.origin, up) < -0.35 and float(m.get("over", 0.0)) < 0.05:
			lifted += 1
	print("   of %d drawn: 2+ feet off the ground %d, standing clear above it %d; climbing over a nestmate: %d (in narrow places %d)" % [near_mates.size(), feet_air, lifted,
		_mates.filter(func(q): return float(q.get("over", 0.0)) > 0.1).size(), _mates.filter(func(q): return q.get("narrow", false)).size()])
	var bis := brood_in_soil()
	print("   in the soil (any body point): %d   overlapping pairs: %d   larvae / cocoons in the soil: %d / %d   larvae off the floor: %d" % [in_soil, mate_overlaps(), bis.x, bis.y, bis.z])
	return "nest %.1fC | by entrance %d | work %d diggers %d/%d er %.2f | mates %d floor %d wall %d ceiling %d | by queen %d | walking %d | air %d target %d chambers %s" % [sim.climate.nest, by_ent, nest.work_left, nest.diggers.size(), sim.diggers_wanted, nest.entrance_r, _mates.size(), flr, wall, ceil, by_q, walking,
		nest.air, sim.target_air(), nest.chambers.map(func(c): return "%s g%.1f%s" % [c.kind, c.goal, "" if c.get("open", true) else "(dig)"])]


func debug_summary() -> String:
	var roles := {}
	var acts := {}
	var carrying := 0
	for m in _mates:
		roles[m.role] = roles.get(m.role, 0) + 1
		acts[m.act] = acts.get(m.act, 0) + 1
		if m.carry:
			carrying += 1
	return "anims %d cam %s d%.1f yaw%.2f cut%.1f | %s %s  roles %s  acts %s  carrying %d  larvae moved %d/%d (%s→%s)  rooms %d  fields %d" % [_anims.size(), target, cam_dist, yaw, cut_offset, sim.clock_text(),
		"air>nest" if sim.climate.air > sim.climate.nest + 0.5 else "air<nest", roles, acts, carrying,
		mini(_moved, sim.larvae.size()), sim.larvae.size(), _larva_prev, _larva_group, _rooms.size(), _fields.size()]


## The rim round a clicked egg, larva or cocoon (ui/ant_tip.gd sets sel_kind / sel_id: its kind and view tag).
func _show_selected_brood() -> void:
	var n := 0
	if sel_kind in ["eggs", "larvae", "pupae"]:
		for e in _brood_drawn[sel_kind]:
			if int((e[1] as Dictionary).get("_v", -1)) == sel_id:
				var mesh: Mesh = _egg_mm.mesh if sel_kind == "eggs" else (_larva_mm.mesh if sel_kind == "larvae" else _pupa_mm.mesh)
				if _sel_brood_mm.mesh != mesh:
					_sel_brood_mm.instance_count = 0
					_sel_brood_mm.mesh = mesh
				_sel_brood_mm.instance_count = 1
				_sel_brood_mm.set_instance_transform(0, e[0])
				n = 1
				break
	if n == 0:
		_sel_brood_mm.instance_count = 0
