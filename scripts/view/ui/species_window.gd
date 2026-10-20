extends Window
## "Which ant?" - the first step of a new colony (PART EA2): each species the game has, what it is like and how hard it
## is to keep (from its CARD, with where each line comes from), and its castes and brood as the game's own 3D models,
## turning (drag to turn them yourself). "เลือกชนิดนี้" goes on to the new-colony window. Only Lasius niger so far.

const AntModel := preload("res://scripts/view/common/ant_model3d.gd")
const Props := preload("res://scripts/view/common/mesh_kit.gd")
const LasiusNiger := preload("res://scripts/sim/species/lasius_niger.gd")
const Paper := preload("res://scripts/view/ui/paper.gd")

const SPECIES := [LasiusNiger]
## what can be shown: [button, caption, kind, scale, body colour key]
const SHOWN := [
	["sp_queen", "sp_queen_cap", "queen", 1.75, ""],
	["sp_major", "sp_major_cap", "worker", 1.15, "body_color"],
	["sp_minor", "sp_minor_cap", "worker", 0.8, "body_color"],
	["sp_callow", "sp_callow_cap", "worker", 1.0, "callow_color"],
	["sp_egg", "sp_egg_cap", "egg", 1.0, ""],
	["sp_larva", "sp_larva_cap", "larva", 1.0, ""],
	["sp_pupa", "sp_pupa_cap", "pupa", 1.0, ""],
]

signal chosen(species_id: String)

var hud
var _vp: SubViewport
var _pivot: Node3D
var _caption: Label
var _mat: ShaderMaterial
var _queen_mat: ShaderMaterial
var _clock := 0.0
var _turn := 0.0
var _drag := false
var _ant_mm: MultiMesh


func setup(h) -> void:
	hud = h
	title = tr("sp_title")
	theme = h._colonies.theme
	transient = true
	exclusive = true
	unresizable = true
	wrap_controls = true
	close_requested.connect(queue_free)
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", Paper.page(18, 16))
	body.set_anchors_preset(Control.PRESET_FULL_RECT)          # (the paper fills the window: no dark strip under it)
	add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	body.add_child(row)
	# the list of species on the left (one, for now)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.custom_minimum_size.x = 170
	row.add_child(list)
	list.add_child(h._label(tr("sp_species"), 13, Paper.PENCIL))
	for S in SPECIES:
		var b: Button = h._button("%s\n%s" % [tr(S.DATA.name_th), S.DATA.name], true)
		b.button_pressed = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	list.add_child(_wrap(h, tr("sp_more_later"), 12, Paper.PENCIL, 170))
	_build_card(row, SPECIES[0])


func _wrap(h, text: String, size: int, color: Color, w: float) -> Label:
	var l: Label = h._label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l


func _build_card(row: Control, S) -> void:
	var h = hud
	var card: Dictionary = S.CARD
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 8)
	text.custom_minimum_size.x = 430
	row.add_child(text)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	name_row.add_child(h._label(tr(S.DATA.name_th), 26, Paper.INK, h._display))
	var latin: Label = h._label(S.DATA.name, 15, Paper.PENCIL)
	latin.size_flags_vertical = Control.SIZE_SHRINK_END
	name_row.add_child(latin)
	text.add_child(name_row)
	text.add_child(_wrap(h, tr(card.blurb), 13, Paper.INK, 430))
	text.add_child(h._label(tr("sp_traits"), 15, Paper.ACCENT))
	for t in card.traits:
		_point(text, t)
	var diff := HBoxContainer.new()
	diff.add_theme_constant_override("separation", 8)
	diff.add_child(h._label(tr("sp_difficulty"), 15, Paper.ACCENT))
	diff.add_child(h._label(tr(card.difficulty), 15, Paper.LEAF))
	text.add_child(diff)
	for t in card.care:
		_point(text, t)
	# the models, turning, on the right
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	var box := SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = Vector2(420, 340)
	box.gui_input.connect(_on_drag)
	right.add_child(box)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	box.add_child(_vp)
	_build_stage()
	var picks := HFlowContainer.new()
	picks.custom_minimum_size.x = 420
	picks.add_theme_constant_override("h_separation", 4)
	picks.add_theme_constant_override("v_separation", 4)
	right.add_child(picks)
	var g := ButtonGroup.new()
	for i in SHOWN.size():
		var b: Button = h._button(tr(SHOWN[i][0]), true, g)
		b.button_pressed = i == 0
		var k: int = i
		b.pressed.connect(func(): _show(k))
		picks.add_child(b)
	_caption = _wrap(h, "", 12, Paper.INK, 420)
	right.add_child(_caption)
	right.add_child(_wrap(h, tr("sp_models"), 11, Paper.PENCIL, 420))
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 8)
	var cancel: Button = h._button(tr("cancel"), false)
	cancel.pressed.connect(queue_free)
	foot.add_child(cancel)
	var go: Button = h._button(tr("sp_choose"), false)
	go.pressed.connect(func():
		chosen.emit(S.DATA.id)
		queue_free())
	foot.add_child(go)
	right.add_child(foot)
	_show(0)


func _point(parent: Control, t: Array) -> void:
	var h = hud
	var l: Label = _wrap(h, "• " + tr(String(t[0])), 13, Paper.INK, 430)
	parent.add_child(l)
	var src: Label = _wrap(h, "   " + tr("sp_source") + tr(String(t[1])), 11, Paper.PENCIL, 430)
	parent.add_child(src)


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.1, 0.075)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.45)
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	_vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20), deg_to_rad(-140), 0)
	fill.light_energy = 0.45
	_vp.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 3.2, 8.5)
	_vp.add_child(cam)
	cam.look_at(Vector3(0, 0.6, 0))
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(0.36, 0.26, 0.18)
	floor_m.roughness = 0.95
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.2
	cyl.bottom_radius = 3.2
	cyl.height = 0.1
	disc.mesh = cyl
	disc.material_override = floor_m
	disc.position.y = -0.05
	_vp.add_child(disc)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/ants/ant.gdshader")
	_mat.set_shader_parameter("limb_gain", AntModel.WORKER_LIMBS)
	_queen_mat = _mat.duplicate()
	_queen_mat.set_shader_parameter("limb_gain", AntModel.QUEEN_LIMBS)


## Puts one of SHOWN on the turntable, sized to fill it.
func _show(i: int) -> void:
	for c in _pivot.get_children():
		c.queue_free()
	_ant_mm = null
	var s: Array = SHOWN[i]
	_caption.text = tr(s[1])
	var sp: Dictionary = LasiusNiger.DATA
	match s[2]:
		"queen", "worker":
			var queen: bool = s[2] == "queen"
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = AntModel.make(0.0, queen, true)
			mm.instance_count = 1
			var aabb: AABB = mm.mesh.get_aabb()
			var fit := 4.6 / maxf(aabb.size.x, aabb.size.z) * (float(s[3]) / (1.75 if queen else 1.15))
			mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * fit), Vector3.ZERO))
			mm.set_instance_color(0, AntModel.body_linear(Color(0.07, 0.055, 0.047) if queen else sp[s[4]]))
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = _queen_mat if queen else _mat
			_pivot.add_child(mi)
			_ant_mm = mm
		"egg":
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.95, 0.96, 0.95, 0.9)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.rim_enabled = true
			m.rim = 0.5
			m.roughness = 0.12
			for k in 5:
				var e := MeshInstance3D.new()
				var sph := SphereMesh.new()
				sph.radius = 0.32
				sph.height = 0.64
				e.mesh = sph
				e.scale = Vector3(1.6, 1.0, 1.0)
				e.material_override = m
				e.position = Vector3((k % 3 - 1) * 0.62 + (0.3 if k >= 3 else 0.0), 0.32 + (0.5 if k >= 3 else 0.0), 0.0)
				e.rotation.y = k * 0.7
				_pivot.add_child(e)
		"larva", "pupa":
			var mesh: Mesh = Props.larva() if s[2] == "larva" else Props.cocoon()
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.roughness = 0.3 if s[2] == "larva" else 0.85
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = m
			var aabb: AABB = mesh.get_aabb()
			var fit := 3.2 / maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
			mi.scale = Vector3.ONE * fit
			mi.position.y = -aabb.position.y * fit
			_pivot.add_child(mi)


func _process(delta: float) -> void:
	if _pivot == null:
		return
	_clock += delta
	if not _drag:
		_turn += delta * 0.4
	_pivot.rotation.y = _turn
	if _ant_mm != null:
		# antennating, the head now and then sweeping round (activity 15: stopped to scan)
		_ant_mm.set_instance_custom_data(0, Color(0.0, 15.0, fmod(_clock, 600.0), 0.0))


func _on_drag(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		_turn += e.relative.x * 0.01
