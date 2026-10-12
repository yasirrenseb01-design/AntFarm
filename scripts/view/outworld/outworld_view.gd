extends "res://scripts/view/outworld/parts/outworld_camera.gd"
## The outworld box in 3D: the same simulation and scenery layout as the top-down view, seen
## through an orbit camera. 1 unit = 1.5 mm (a nest voxel) = 3 px of the simulation's outworld.
## This file is the top of the chain: building the scene, the per-frame update and input.
## Layers: parts/outworld_scene <- outworld_props <- outworld_creatures <- outworld_camera <- outworld_view.


func setup(s, w) -> void:
	sim = s
	world = w
	_nest_xz = sim.nest_pos * U
	target = Vector3(sim.WORLD.x * U * 0.5, 0, sim.WORLD.y * U * 0.5)

	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.05, 0.04, 0.035)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.6, 0.55, 0.5)
	_env.ambient_light_energy = 0.55
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_intensity = 0.2

	_cam = Camera3D.new()
	_cam.fov = 38
	_cam.near = 0.5
	_cam.far = 4000
	_cam.environment = _env
	add_child(_cam)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.5
	_sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(28), 0)
	add_child(_sun)

	_prop_mat = StandardMaterial3D.new()
	_prop_mat.vertex_color_use_as_albedo = true
	_prop_mat.vertex_color_is_srgb = true
	_prop_mat.roughness = 0.8
	_prop_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_plant_mat = _sway_mat(true, Color(0.05, 0.07, 0.02), 0.7)
	_litter_mat = _sway_mat(true, Color(0.08, 0.05, 0.02), 0.8)
	_grass_mat = _sway_mat(false, Color(0.05, 0.07, 0.02), 0.65)
	_aphid_meshes = [Props.aphid(0), Props.aphid(1), Props.aphid(2)]
	_aphid_wings = Props.aphid_wings()
	_build_ground()
	_build_box()
	_build_scenery()
	_rock_root = Node3D.new()
	add_child(_rock_root)
	_food_root = Node3D.new()
	add_child(_food_root)

	var ant_mat := ShaderMaterial.new()
	ant_mat.shader = load("res://shaders/ants/ant.gdshader")
	ant_mat.set_shader_parameter("limb_gain", AntModel.WORKER_LIMBS)
	ant_mat.set_shader_parameter("ground_mode", 2)       # feet on the uneven outworld floor
	_ant_shader_mat = ant_mat
	# feet are set down on the litter as well as the ground (the grid was built with the scenery above)
	ant_mat.set_shader_parameter("prop_tex", _props_h.texture())
	ant_mat.set_shader_parameter("prop_size", Vector2(_props_h.w, _props_h.h) * PropHeights.CELL)
	ant_mat.set_shader_parameter("has_props", true)
	_ant_meshes = {"hi": AntModel.make(), "lo": AntModel.make(0.0, false, false)}
	_ant_mm = _multimesh(_ant_meshes.lo, ant_mat, true, true)
	_corpse_mm = _multimesh(_ant_meshes.lo, ant_mat, true, true)
	var sel_mat: ShaderMaterial = ant_mat.duplicate()       # the selection outline (filled with litter heights below)
	sel_mat.shader = load("res://shaders/ants/ant_outline.gdshader")
	_sel_mm = _multimesh(_ant_meshes.lo, sel_mat, true, false)
	_sel_mm.use_custom_data = true
	_sel_shader_mat = sel_mat
	_prey_mm = _multimesh(_blob_mesh(Vector3(0.75, 0.5, 0.6)), _mat(Color(0.5, 0.33, 0.18), 0.7), false)
	var sp_mat := ShaderMaterial.new()
	sp_mat.shader = load("res://shaders/creatures/spider.gdshader")
	_spider_mat = sp_mat
	_creature_views["wolf_spider"] = {"mm": _multimesh(Props.spider(), sp_mat, false, true), "mat": sp_mat,
		"scale": 0.85, "gait": 0.5}
	var ce_mat := ShaderMaterial.new()
	ce_mat.shader = load("res://shaders/creatures/centipede.gdshader")
	_creature_views["centipede"] = {"mm": _multimesh(Props.asset("creatures/centipede"), ce_mat, false, true), "mat": ce_mat,
		"scale": 1.0, "gait": 1.0}
	var be_mat := ShaderMaterial.new()
	be_mat.shader = load("res://shaders/creatures/beetle.gdshader")
	_creature_views["ground_beetle"] = {"mm": _multimesh(Props.asset("creatures/ground_beetle"), be_mat, false, true), "mat": be_mat,
		"scale": 1.0, "gait": 1.4}
	_mound = -1.0
	_update_mound()             # the creatures' shaders need the ground's shape too

	var drop := BoxMesh.new()
	drop.size = Vector3(0.12, 3.2, 0.12)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.8, 0.86, 0.95, 0.35)
	_rain_mm = _multimesh(drop, rm, false)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.75
	ring.outer_radius = 1.0
	ring.rings = 16
	ring.ring_segments = 4
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(0.85, 0.9, 1.0)
	_splash_mm = _multimesh(ring, sm, true)
	_dew_mm = _multimesh(_blob_mesh(Vector3(0.15, 0.14, 0.15)), _honey_mat(), false)
	var mist := StandardMaterial3D.new()
	mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist.albedo_color = Color(0.95, 0.97, 1.0, 0.35)
	_spray_mm = _multimesh(_blob_mesh(Vector3.ONE), mist, false)
	_soil_mm = _multimesh(_blob_mesh(Vector3(1.0, 0.75, 1.0)), _mat(Color(0.4, 0.29, 0.19), 0.95), false)
	for i in 320:
		_rain.append(Vector3(randf() * 400.0, randf() * 60.0, randf() * 250.0))

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 48
	_ring.mesh = torus
	var ringm := StandardMaterial3D.new()
	ringm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ringm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ringm.albedo_color = Color(1, 0.95, 0.85, 0.7)
	ringm.no_depth_test = true
	_ring.material_override = ringm
	_ring.visible = false
	add_child(_ring)

	reset_view()
	snap_camera()
	visible = false


# ---------------------------------------------------------------- per frame

func set_active(on: bool) -> void:
	active = on
	visible = on
	_cam.current = on
	if on:
		_rocks_n = -1


func refresh(delta: float) -> void:
	if not active:
		return
	_t += delta
	_ease_camera(delta)
	_update_camera()
	_items_timer -= delta
	if _items_timer <= 0.0:
		_items_timer = 0.4
		_sync_rocks()
		_sync_foods()
		_update_mound()
	_ease_foods(delta)
	_ground_mat.set_shader_parameter("pher_on", 1.0 if world.show_pheromones else 0.0)
	var raining: bool = sim.climate.raining()
	_wet = move_toward(_wet, 1.0 if raining else 0.0, delta * 0.3 * maxf(speed, 0.5))
	_ground_mat.set_shader_parameter("wet", _wet)
	_grass_mat.set_shader_parameter("wind", 1.3 + 1.8 * _wet)
	_plant_mat.set_shader_parameter("wind", 0.45 + 0.7 * _wet)
	_litter_mat.set_shader_parameter("wind", 0.35 + 0.6 * _wet)
	_seasons(delta)
	_light()
	var lod := "hi" if cam_dist < 80.0 else "lo"
	if lod != _lod:
		_lod = lod
		_ant_mm.mesh = _ant_meshes[lod]
		_sel_mm.mesh = _ant_meshes[lod]
		_ant_shader_mat.set_shader_parameter("shadow_pose", lod == "hi")   # zoomed out: shadows in the rest pose
	_update_ants(delta)
	_update_corpses()
	_update_creatures(delta)
	_update_rain(delta, raining)
	_update_ring()


# ---------------------------------------------------------------- input

func _unhandled_input(e: InputEvent) -> void:
	if not active:
		return
	var tool: String = world.tool
	if e is InputEventMouseButton:
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and e.pressed:
			var f := 1.0 / 1.18 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.18
			var at := pick(e.position)
			var before := dist_t
			zoom_by(f)
			if at != Vector3.INF:
				# zoom toward the point under the mouse
				target_t = at + (target_t - at) * (dist_t / before)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if tool == "pan":
				if e.pressed and e.double_click:
					var at := pick(e.position)
					if at != Vector3.INF:
						target_t = at
						dist_t = minf(dist_t * 0.5, 90.0)
				_pan = e.pressed and e.shift_pressed
				_rot = e.pressed and not e.shift_pressed
			elif e.pressed:
				_use_tool(tool, pick(e.position))
				_painting = tool in ["rock", "erase"]
			else:
				_painting = false
		elif e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE:
			_pan = e.pressed
			_rot = false
	elif e is InputEventMouseMotion:
		hover = pick(e.position)
		if _rot:
			yaw_t -= e.relative.x * 0.007
			pitch_t = clampf(pitch_t + e.relative.y * 0.006, 0.12, 1.54)
		elif _pan:
			var vp := get_viewport().get_visible_rect().size
			var upp := 2.0 * cam_dist * tan(deg_to_rad(_cam.fov * 0.5)) / vp.y
			target_t += (-_right() * e.relative.x + _forward() * e.relative.y / maxf(0.35, sin(pitch))) * upp
		elif _painting and hover != Vector3.INF:
			_use_tool(tool, hover)
	elif e is InputEventKey and e.pressed and e.keycode == KEY_HOME:
		reset_view()


func _use_tool(tool: String, at: Vector3) -> void:
	if at == Vector3.INF:
		return
	var p := _px(at)
	match tool:
		_ when FoodKinds.info(tool).has("tool"):
			sim.place_food(tool, p)
			_items_timer = 0.0
		"rock":
			if p.distance_to(_last_paint) > 9.0 and sim.can_place(p) and sim.add_rock(p, 10.0):
				_last_paint = p
				world.redraw_scenery()
				_items_timer = 0.0
		"erase":
			sim.erase_pheromones(p, 24.0)
