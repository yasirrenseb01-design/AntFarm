extends CanvasLayer
## The developer's 3D model room (PART 0.14 step 10, the keeper 2026-11-21: "open the files of the tools, the buildings,
## the soils that were made, as 3D cards"). From the title's Developer page (ui/dev_panel.gd), the developer's machine
## only. Each model on a card of its own (a SubViewport with a world of its own), turning; under it its name, its file
## or the code that makes it, its size in life and its vertices; a click shows it big - drag to turn it, the wheel to
## come nearer. Reads the models only: nothing of the game's state is touched.
##   the ants and brood, the enemies, the prey, the plants, stones and ground, the Home's things (game units of 1.5 mm,
##   the Home's in metres - ARCHITECTURE "units")

const AntModel := preload("res://scripts/view/common/ant_model3d.gd")
const MeshKit := preload("res://scripts/view/common/mesh_kit.gd")
const Props := preload("res://scripts/view/common/parts/mesh_kit_base.gd")
const HomeTools := preload("res://scripts/view/home/home_tools.gd")
const HomeFridge := preload("res://scripts/view/home/home_fridge.gd")
const Paper := preload("res://scripts/view/ui/paper.gd")
const GAME_MM := 1.5             # mm a game unit (the ants, the enemies, the prey, the plants)
const M_MM := 1000.0             # the Home's things: metres
const CARD := Vector2(300, 210)
const ANT_TINT := Color(0.16, 0.13, 0.11)     # (the ants' vertex colours multiply a tint: a dark worker's, for a look)

var main
var h
var _tabs: HBoxContainer
var _grid: GridContainer
var _big: PanelContainer
var _big_vp: SubViewport
var _big_label: Label
var _pivots: Array = []          # the cards' turning pivots
var _big_pivot: Node3D
var _big_cam: Camera3D
var _yaw := 0.0
var _pitch := 0.35
var _zoom := 1.0
var _r := 1.0
var _drag := false


func setup(m) -> void:
	main = m
	h = m.hud
	layer = 20
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = h._paper_theme
	add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	root.add_child(col)
	var head := HBoxContainer.new()
	var t: Label = h._label(tr("mdl_title"), 20, Paper.ACCENT, h._display)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x: Button = h._button("×", false)
	x.pressed.connect(queue_free)
	head.add_child(x)
	col.add_child(head)
	_tabs = HBoxContainer.new()
	col.add_child(_tabs)
	col.add_child(h._label(tr("mdl_note"), 12, Paper.PENCIL))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
	var g := ButtonGroup.new()
	var cats := _cats()
	for i in cats.size():
		var b: Button = h._button(tr(cats[i][0]), true, g)
		b.button_pressed = i == 0
		var k: int = i
		b.pressed.connect(func(): _show(k))
		_tabs.add_child(b)
	_build_big(root)
	var start := clampi(int(m._opts.get("model-room", "0")), 0, cats.size() - 1)     # (dev: --model-room=<tab>)
	_tabs.get_child(start).button_pressed = true
	_show(start)
	if m._opts.has("model-big"):                                   # (dev: --model-big=<card>: shown big)
		get_tree().create_timer(0.5).timeout.connect(func(): _open_big(cats[start][1][clampi(int(m._opts["model-big"]), 0, cats[start][1].size() - 1)]))


# ---------------------------------------------------------------- what there is

## [tab word key, [item]]; an item: [word key, where it comes from, mm a unit, maker -> Node3D].
func _cats() -> Array:
	var ants := []
	for n in ["worker", "queen", "gyne", "male"]:
		for d in ["hi", "lo"]:
			var path := "ants/%s_%s.antmesh" % [n, d]
			ants.append(["mdl_" + n + "_" + d, path, GAME_MM, func(): return _mesh(AntModel.load_antmesh("res://assets/models/" + path), ANT_TINT)])
	ants.append(["mdl_larva", "mesh_kit.larva()", GAME_MM, func(): return _mesh(MeshKit.larva())])
	ants.append(["mdl_cocoon", "mesh_kit.cocoon()", GAME_MM, func(): return _mesh(MeshKit.cocoon())])
	var foes := []
	for n in ["wolf_spider", "centipede", "ground_beetle"]:
		var path := "creatures/%s.antmesh" % n
		foes.append(["mdl_" + n, path, GAME_MM, func(): return _mesh(AntModel.load_antmesh("res://assets/models/" + path))])
	var prey := []
	for n in ["aphid_adult", "aphid_nymph", "aphid_winged"]:
		var path := "prey/%s.antmesh" % n
		prey.append(["mdl_" + n, path, GAME_MM, func(): return _mesh(AntModel.load_antmesh("res://assets/models/" + path))])
	prey.append(["mdl_cricket", "mesh_kit.cricket()", GAME_MM, func(): return _mesh(MeshKit.cricket(1.0, false))])
	prey.append(["mdl_cricket_rotten", "mesh_kit.cricket(rotten)", GAME_MM, func(): return _mesh(MeshKit.cricket(1.0, true))])
	prey.append(["mdl_fly", "mesh_kit.fly()", GAME_MM, func(): return _mesh(MeshKit.fly(1.0))])
	var plants := []
	for p in 3:
		for st in 4:
			var path := "plants/plant%d_%d.antmesh" % [p, st]
			var key := "mdl_plant"
			plants.append([key, path, GAME_MM, func(): return _mesh(AntModel.load_antmesh("res://assets/models/" + path))])
	plants.append(["mdl_aphid_plant", "mesh_kit.aphid_plant()", GAME_MM, func(): return _mesh(Props.aphid_plant(3, 3))])
	var ground := []
	for k in 3:
		var tone: float = k * 0.5
		var sd: int = 11 + k * 7
		ground.append(["mdl_stone", "mesh_kit.rock()", GAME_MM, func(): return _mesh(Props.rock(_round(14.0, sd), 14.0, tone, sd))])
	ground.append(["mdl_twig", "mesh_kit.twig()", GAME_MM, func(): return _mesh(Props.twig(16.0, 5))])
	ground.append(["mdl_leaf", "mesh_kit.leaf()", GAME_MM, func(): return _mesh(Props.leaf(9.0, 4.0, Color(0.55, 0.38, 0.16), 0.4))])
	ground.append(["mdl_blade", "mesh_kit.blade()", GAME_MM, func(): return _mesh(Props.blade())])
	ground.append(["mdl_tank_small", "home_kit._tank()", M_MM, func(): return _kit("_tank", [false])])
	ground.append(["mdl_tank_big", "home_kit._tank(big)", M_MM, func(): return _kit("_tank", [true])])
	var home := []
	for it in [["mdl_tubes", "_tubes", [Vector3.ZERO, 0.0]], ["mdl_aspirator", "_aspirator", [Vector3.ZERO, true]],
			["mdl_forceps", "_forceps", [Vector3.ZERO, 0.0]], ["mdl_brush", "_brush", [Vector3.ZERO, 0.0]],
			["mdl_syringe", "_syringe", [Vector3.ZERO, 0.0]], ["mdl_petri", "_petri", [Vector3.ZERO, true]],
			["mdl_lens", "_lens", [Vector3.ZERO, 0.0]], ["mdl_fluon", "_fluon", [Vector3.ZERO]], ["mdl_tray", "_tray", [Vector3.ZERO]],
			["mdl_notebook", "_notebook", [Vector3.ZERO, 0.0]], ["mdl_pencil", "_pencil", [Vector3.ZERO, 0.0]], ["mdl_chair", "_chair", []]]:
		var meth: String = it[1]
		var args: Array = it[2]
		home.append([it[0], "home_tools.%s()" % meth, M_MM, func(): return _kit(meth, args)])
	home.append(["mdl_fridge", "home_fridge.build()", M_MM, func():
		var n := Node3D.new()
		HomeFridge.build(n, Vector3.ZERO, 0.0)
		return n])
	for n in ["hand_open", "hand_point", "sleeve"]:
		var path := "hand/%s.antmesh" % n
		home.append(["mdl_" + n, path, M_MM, func(): return _mesh(AntModel.load_antmesh("res://assets/models/" + path))])
	for n in ["tree_a", "tree_b"]:
		var path := "trees/%s.antmesh" % n
		home.append(["mdl_tree", path, 0.0, func(): return _mesh(AntModel.load_antmesh("res://assets/models/" + path))])
	return [["mdl_tab_ants", ants], ["mdl_tab_enemies", foes], ["mdl_tab_prey", prey], ["mdl_tab_plants", plants],
		["mdl_tab_ground", ground], ["mdl_tab_home", home]]


## The ants: their vertex colours times a tint, as the game's shader takes them, the wings (part 12) pale and clear
## instead (ARCHITECTURE "ant models": alpha = part id / 16).
const ANT_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 tint = vec3(0.16, 0.13, 0.11);
void fragment() {
	float part = floor(COLOR.a * 16.0 + 0.5);
	bool wing = part > 11.5 && part < 12.5;
	ALBEDO = wing ? mix(COLOR.rgb, vec3(0.86, 0.84, 0.8), 0.6) : COLOR.rgb * tint;
	ROUGHNESS = wing ? 0.3 : 0.7;
	ALPHA = wing ? 0.55 : 1.0;
}
"""
static var _ant_shader: Shader = null


func _mesh(m: Mesh, tint := Color.WHITE) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	if tint != Color.WHITE:
		if _ant_shader == null:
			_ant_shader = Shader.new()
			_ant_shader.code = ANT_SHADER
		var sm := ShaderMaterial.new()
		sm.shader = _ant_shader
		sm.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		mi.material_override = sm
		return mi
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true      # (the models carry their colours per vertex; alpha is a part's id, not see-through)
	mat.albedo_color = tint
	mat.roughness = 0.75
	mi.material_override = mat
	return mi


## One of the Home's things, made by the room's own code (view/home/home_tools.gd, home_kit.gd) on a builder of its own.
func _kit(meth: String, args: Array) -> Node3D:
	var k = HomeTools.new()
	if meth == "_tank":
		if is_inside_tree():
			add_child(k)                     # (_tank reads its global place for the Home's hand: in the tree while it is made)
		k._tank(k, Vector3.ZERO, args[0], false, 0, 1, true, 0.0)       # (slot 0: no save of the keeper's read - plain soil)
		if k.get_parent() == self:
			remove_child(k)
	else:
		k.callv(meth, args)
	return k


func _round(r: float, sd: int) -> PackedVector2Array:
	var g := RandomNumberGenerator.new()
	g.seed = sd
	var o := PackedVector2Array()
	for i in 14:
		o.append(Vector2.from_angle(TAU * i / 14.0) * r * g.randf_range(0.75, 1.1))
	return o


# ---------------------------------------------------------------- the cards

func _show(i: int) -> void:
	for c in _grid.get_children():
		c.queue_free()
	_pivots.clear()
	for it in _cats()[i][1]:
		_grid.add_child(_card(it))


func _card(it: Array) -> Control:
	var box := VBoxContainer.new()
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = CARD
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_STOP
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	box.add_child(svc)
	var got := _stage(vp, it)
	_pivots.append(got[0])
	box.add_child(h._label(tr(it[0]), 13, Paper.INK))
	box.add_child(h._label(_about(it, got[1], got[2]), 11, Paper.PENCIL))
	svc.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_open_big(it))
	return box


## The model in its own world, lit, the camera framing it: [pivot, its box, its vertices].
func _stage(vp: SubViewport, it: Array) -> Array:
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.86, 0.8, 0.68)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.72, 0.68)
	env.environment.ambient_light_energy = 0.7
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	world.add_child(sun)
	var pivot := Node3D.new()
	world.add_child(pivot)
	var model: Node3D = (it[3] as Callable).call()
	pivot.add_child(model)
	var box := _box_of(model)
	model.position = -box.get_center()
	var verts := 0
	for mi in model.find_children("*", "MeshInstance3D", true, false) + ([model] if model is MeshInstance3D else []):
		verts += _verts(mi.mesh)
	var cam := Camera3D.new()
	var r := maxf(0.0001, box.size.length() * 0.5)
	cam.fov = 35.0
	cam.near = r * 0.01
	cam.far = r * 40.0
	world.add_child(cam)
	cam.transform = Transform3D.IDENTITY.looking_at(-Vector3(0, r * 0.9, r * 2.9), Vector3.UP).translated(Vector3(0, r * 0.9, r * 2.9))
	return [pivot, box, verts, cam, r]


func _verts(m: Mesh) -> int:
	if m is ArrayMesh:
		var n := 0
		for i in m.get_surface_count():
			n += m.surface_get_array_len(i)
		return n
	if m is PrimitiveMesh:
		return (m.get_mesh_arrays()[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return 0


func _box_of(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var list: Array = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		list.append(model)
	for mi in list:
		if mi.mesh == null:
			continue
		var b: AABB = _xf_to(mi, model) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _xf_to(n: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != top:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Its source, its size in life (length x width x height) and its vertices.
func _about(it: Array, box: AABB, verts: int) -> String:
	var mm: float = it[2]
	var size := tr("mdl_size_none") if mm <= 0.0 else (tr("mdl_size_cm") % [box.size.x * mm / 10.0, box.size.z * mm / 10.0, box.size.y * mm / 10.0]
		if box.size.x * mm >= 100.0 else tr("mdl_size_mm") % [box.size.x * mm, box.size.z * mm, box.size.y * mm])
	return "%s\n%s · %s" % [it[1], size, tr("mdl_verts") % verts]


func _process(delta: float) -> void:
	for p in _pivots:
		if is_instance_valid(p):
			p.rotation.y += delta * 0.5
	if _big.visible and _big_cam != null:
		var d := _r * 2.9 * _zoom
		var at := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * d
		_big_cam.transform = Transform3D.IDENTITY.looking_at(-at, Vector3.UP).translated(at)


# ---------------------------------------------------------------- one shown big

func _build_big(root: Control) -> void:
	_big = PanelContainer.new()
	_big.set_anchors_preset(Control.PRESET_CENTER)
	_big.visible = false
	root.add_child(_big)
	var col := VBoxContainer.new()
	_big.add_child(col)
	var head := HBoxContainer.new()
	_big_label = h._label("", 15, Paper.ACCENT)
	_big_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_big_label)
	var x: Button = h._button("×", false)
	x.pressed.connect(func(): _big.visible = false)
	head.add_child(x)
	col.add_child(head)
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(900, 620)
	svc.stretch = true
	_big_vp = SubViewport.new()
	_big_vp.own_world_3d = true
	_big_vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(_big_vp)
	col.add_child(svc)
	col.add_child(h._label(tr("mdl_big_help"), 12, Paper.PENCIL))
	svc.gui_input.connect(_big_input)


func _open_big(it: Array) -> void:
	for c in _big_vp.get_children():
		c.queue_free()
	var got := _stage(_big_vp, it)
	_big_pivot = got[0]
	_big_cam = got[3]
	_r = got[4]
	_yaw = 0.0
	_pitch = 0.35
	_zoom = 1.0
	_big_label.text = "%s — %s" % [tr(it[0]), _about(it, got[1], got[2]).replace("\n", " · ")]
	_big.visible = true
	_big.reset_size()
	_big.position = (get_viewport().get_visible_rect().size - _big.size) * 0.5


func _big_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_drag = e.pressed
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom = maxf(0.15, _zoom * 0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom = minf(4.0, _zoom * 1.1)
	elif e is InputEventMouseMotion and _drag:
		_yaw -= e.relative.x * 0.01
		_pitch = clampf(_pitch + e.relative.y * 0.01, -1.4, 1.4)
