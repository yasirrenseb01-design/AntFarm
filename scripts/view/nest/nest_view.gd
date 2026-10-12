extends "res://scripts/view/nest/parts/nest_mates.gd"
## 3D view of the underground nest: the soil block sliced open by a camera-facing cut plane, with
## diggers from the simulation, resting nestmates, brood piles and the queen. This file is the top of
## the chain: building the scene, switching on/off, the per-frame update and input.
## Layers: parts/nest_scene <- nest_camera <- nest_brood <- nest_lifecycle <- nest_bodies <- nest_mates <- nest_view (see docs/ARCHITECTURE.md).


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
	_sel_queen_mm.use_custom_data = true

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
	for k in nest.dirty:
		if not _queue.has(k):
			_queue.append(k)
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
	_mat.set_shader_parameter("humidity", sim.humidity)
	_xray_mat.set_shader_parameter("humidity", sim.humidity)
	_spot_timer -= delta
	if _spot_timer <= 0.0:
		_spot_timer = 1.5
		_refresh_spots()
	# brood and the mound change slowly; rebuild their instances only when something moved
	t0 = _nprof("camera/spots", t0)
	_poll_events()
	_step_anims(delta if speed > 0 else 0.0)
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
