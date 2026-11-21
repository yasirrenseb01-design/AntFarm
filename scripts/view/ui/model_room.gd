extends CanvasLayer
## The developer's 3D model room (PART 0.14 step 10, the keeper 2026-11-21: "open the files of the tools, the buildings,
## the soils that were made, as 3D cards"; gone over in step 11: "near and far in one card, chosen inside"; the brood's
## stages and how one turns into the next; each enemy's poses; the cricket's states). From the title's Developer page and
## the playground (ui/dev_panel.gd), the developer's machine only. What there is: dev/model_catalog.gd.
## Each thing on a card of its own (a SubViewport with a world of its own), turning; under it its name, its file or the
## code that makes it, its size in life, its vertices and how many kinds it has; a click shows it big - its kinds (and
## an enemy's poses, the brood's cycle) chosen there, dragged to turn, the wheel to come nearer. Reads the models only.

const Catalog := preload("res://scripts/dev/model_catalog.gd")
const CreaturePose := preload("res://scripts/view/outworld/creature_pose.gd")
const CreatureRig := preload("res://scripts/view/outworld/creature_rig.gd")
const Paper := preload("res://scripts/view/ui/paper.gd")
const CARD := Vector2(300, 210)
const CYCLE := 12.0              # s: egg -> larva growing -> cocoon -> worker out, once round

var main
var h
var _tabs: HBoxContainer
var _grid: GridContainer
var _cats: Array = []
var _big: PanelContainer
var _big_vp: SubViewport
var _big_label: Label
var _big_row: HFlowContainer     # its kinds, its poses
var _big_item: Dictionary = {}
var _pivots: Array = []          # the cards' turning pivots
var _big_pivot: Node3D
var _big_cam: Camera3D
var _yaw := 0.0
var _pitch := 0.35
var _zoom := 1.0
var _r := 1.0
var _drag := false
var _t := 0.0
var _cycle_on := false
var _cycle: Dictionary = {}      # the brood cycle's pieces in the big view


func setup(m) -> void:
	main = m
	h = m.hud
	layer = 20
	_cats = Catalog.cats(self)
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
	for i in _cats.size():
		var b: Button = h._button(tr(_cats[i][0]), true, g)
		var k: int = i
		b.pressed.connect(func(): _show(k))
		_tabs.add_child(b)
	_build_big(root)
	var start := clampi(int(m._opts.get("model-room", "0")), 0, _cats.size() - 1)     # (dev: --model-room=<tab>)
	_tabs.get_child(start).button_pressed = true
	_show(start)
	if m._opts.has("model-big"):                 # (dev: --model-big=<card>[,<kind or pose word key>]: shown big)
		get_tree().create_timer(0.5).timeout.connect(_dev_big.bind(start))


func _dev_big(start: int) -> void:
	var mb: PackedStringArray = String(main._opts["model-big"]).split(",")
	var items: Array = _cats[start][1]
	_open_big(items[clampi(int(mb[0]), 0, items.size() - 1)])
	if mb.size() > 1:
		for b in _big_row.get_children():
			if b is Button and b.text == tr(mb[1]):
				b.pressed.emit()
				b.button_pressed = true


# ---------------------------------------------------------------- the cards

func _show(i: int) -> void:
	for c in _grid.get_children():
		c.queue_free()
	_pivots.clear()
	for it in _cats[i][1]:
		_grid.add_child(_card(it))


func _card(it: Dictionary) -> Control:
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
	var got := _stage(vp, it.vars[0][1])
	_pivots.append(got.pivot)
	box.add_child(h._label(tr(it.key), 13, Paper.INK))
	var more := ""
	if it.vars.size() > 1:
		more = " · " + tr("mdl_kinds") % it.vars.size()
	if it.has("poses"):
		more += " · " + tr("mdl_poses") % it.poses.size()
	box.add_child(h._label(_about(it, got.box, got.verts) + more, 11, Paper.PENCIL))
	svc.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_open_big(it))
	return box


## A model in its own world, lit, the camera framing it: {pivot, model, box, verts, cam, r}.
func _stage(vp: SubViewport, maker: Callable) -> Dictionary:
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
	var model: Node3D = maker.call()
	pivot.add_child(model)
	var box := _box_of(model)
	model.position = -box.get_center()
	var verts := 0
	for mi in _meshes(model):
		verts += _verts(mi.multimesh.mesh if mi is MultiMeshInstance3D else mi.mesh)
	var cam := Camera3D.new()
	var r := maxf(0.0001, box.size.length() * 0.5)
	cam.fov = 35.0
	cam.near = r * 0.01
	cam.far = r * 40.0
	world.add_child(cam)
	_place_cam(cam, Vector3(0, r * 0.9, r * 2.9))
	return {"pivot": pivot, "model": model, "box": box, "verts": verts, "cam": cam, "r": r}


func _place_cam(cam: Camera3D, at: Vector3) -> void:
	cam.transform = Transform3D.IDENTITY.looking_at(-at, Vector3.UP).translated(at)


func _meshes(model: Node3D) -> Array:
	var list: Array = model.find_children("*", "MeshInstance3D", true, false) + model.find_children("*", "MultiMeshInstance3D", true, false)
	if model is MeshInstance3D or model is MultiMeshInstance3D:
		list.append(model)
	return list


func _verts(m: Mesh) -> int:
	if m is ArrayMesh:
		var n := 0
		for i in m.get_surface_count():
			n += m.surface_get_array_len(i)
		return n
	if m is PrimitiveMesh:
		return (m.get_mesh_arrays()[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return 0


## Its box in the model's own frame (its own scale in: an egg, a larva grown so far).
func _box_of(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(model):
		var mesh: Mesh = mi.multimesh.mesh if mi is MultiMeshInstance3D else mi.mesh
		if mesh == null:
			continue
		var xf := _xf_to(mi, model)
		if mi is MultiMeshInstance3D:
			xf = xf * mi.multimesh.get_instance_transform(0)
		var b: AABB = xf * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## n's transform into top's parent's frame (top's own transform in).
func _xf_to(n: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null:
		xf = (cur as Node3D).transform * xf
		if cur == top:
			break
		cur = cur.get_parent()
	return xf


## Its source, its size in life (length x width x height) and its vertices.
func _about(it: Dictionary, box: AABB, verts: int) -> String:
	var mm: float = it.mm
	var size := tr("mdl_size_none") if mm <= 0.0 else (tr("mdl_size_cm") % [box.size.x * mm / 10.0, box.size.z * mm / 10.0, box.size.y * mm / 10.0]
		if box.size.x * mm >= 100.0 else tr("mdl_size_mm") % [box.size.x * mm, box.size.z * mm, box.size.y * mm])
	return "%s\n%s · %s" % [it.src, size, tr("mdl_verts") % verts]


func _process(delta: float) -> void:
	_t += delta
	for p in _pivots:
		if is_instance_valid(p):
			p.rotation.y += delta * 0.5
			_pose_all(p, "mdl_pose_walk")
	if _big.visible and _big_cam != null:
		var d := _r * 2.9 * _zoom
		_place_cam(_big_cam, Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * d)
		if is_instance_valid(_big_pivot):
			_pose_all(_big_pivot, String(_big_pivot.get_meta("pose", "mdl_pose_walk")))
		if _cycle_on:
			_play_cycle()


# ---------------------------------------------------------------- an enemy's poses (its own shader: creature_pose.gd)

func _pose_all(pivot: Node3D, pose: String) -> void:
	for mmi in pivot.find_children("*", "MultiMeshInstance3D", true, false):
		if mmi.has_meta("creature"):
			_pose(mmi, pose)


## The shader's INSTANCE_CUSTOM as creature_pose.update gives it: x the gait, y 0..1 a strike / 3 + kick on its back /
## 5 feeding / 6 shaking prey, z the clock, w walking + 2 held (+ the centipede's bend packed above); on its back the
## body rolled over and lifted by its back's height.
func _pose(mmi: MultiMeshInstance3D, pose: String) -> void:
	var c: Dictionary = mmi.get_meta("creature")
	var mm := mmi.multimesh
	var t := _t
	var gait := 0.0
	var y := 0.0
	var w := 0.0
	var back := false
	match pose:
		"mdl_pose_walk":
			gait = fmod(t * 1.6 * TAU, TAU * 64.0)
			w = 1.0
		"mdl_pose_strike":
			y = smoothstep(0.0, 1.0, maxf(0.0, sin(t * 2.6)))
		"mdl_pose_held":
			gait = fmod(t * CreatureRig.HELD_TURNS * TAU, TAU * 64.0)
			w = 2.0
		"mdl_pose_back":
			back = true
			y = 3.0 + 0.85 + 0.15 * sin(t * 2.0)
			w = 2.0
		"mdl_pose_dead":
			back = true
			y = 3.0
		"mdl_pose_feed":
			y = 5.0
		"mdl_pose_shake":
			y = 6.0
	if c.kind == "centipede":
		w += 4.0 * 50.0                       # (its bend packed above: straight - centipede.gdshader)
	var sc: float = c.scale
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * sc), Vector3.ZERO)
	if back:
		var turn := PI + (0.22 * sin(t * 3.4) + 0.1 * sin(t * 7.9)) * (1.0 if pose == "mdl_pose_back" else 0.0)
		xf = Transform3D(Basis(Vector3.RIGHT, turn).scaled(Vector3.ONE * sc), Vector3(0, float(CreaturePose.BACK_LIFT.get(c.kind, 2.0)) * sc, 0))
	mm.set_instance_transform(0, xf)
	mm.set_instance_custom_data(0, Color(gait, y, fmod(t, 600.0), w))


# ---------------------------------------------------------------- one shown big

func _build_big(root: Control) -> void:
	_big = PanelContainer.new()
	_big.visible = false
	root.add_child(_big)
	var col := VBoxContainer.new()
	_big.add_child(col)
	var head := HBoxContainer.new()
	_big_label = h._label("", 14, Paper.ACCENT)
	_big_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_big_label)
	var x: Button = h._button("×", false)
	x.pressed.connect(func(): _big.visible = false)
	head.add_child(x)
	col.add_child(head)
	_big_row = HFlowContainer.new()
	_big_row.add_theme_constant_override("h_separation", 4)
	col.add_child(_big_row)
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(1000, 580)
	svc.stretch = true
	_big_vp = SubViewport.new()
	_big_vp.own_world_3d = true
	_big_vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(_big_vp)
	col.add_child(svc)
	col.add_child(h._label(tr("mdl_big_help"), 12, Paper.PENCIL))
	svc.gui_input.connect(_big_input)


func _open_big(it: Dictionary) -> void:
	_big_item = it
	_cycle_on = false
	for c in _big_row.get_children():
		c.queue_free()
	var g := ButtonGroup.new()
	if it.vars.size() > 1 or it.get("cycle", false):
		_big_row.add_child(h._label(tr("mdl_kind"), 12, Paper.PENCIL))
		for i in it.vars.size():
			var b: Button = h._button(tr(it.vars[i][0]), true, g)
			b.button_pressed = i == 0
			var k: int = i
			b.pressed.connect(func(): _load_big(k))
			_big_row.add_child(b)
	if it.get("cycle", false):
		var cy: Button = h._button(tr("mdl_cycle"), true, g)
		cy.pressed.connect(_start_cycle)
		_big_row.add_child(cy)
	if it.has("poses"):
		var gp := ButtonGroup.new()
		_big_row.add_child(h._label(tr("mdl_pose"), 12, Paper.PENCIL))
		for p in it.poses:
			var b: Button = h._button(tr(p), true, gp)
			b.button_pressed = p == it.poses[0]
			var pose: String = p
			b.pressed.connect(func():
				if is_instance_valid(_big_pivot):
					_big_pivot.set_meta("pose", pose))
			_big_row.add_child(b)
	_load_big(0)
	_yaw = 0.0
	_pitch = 0.35
	_zoom = 1.0
	_big.visible = true
	_big.reset_size()
	_big.position = (get_viewport().get_visible_rect().size - _big.size) * 0.5


func _load_big(i: int) -> void:
	_cycle_on = false
	for c in _big_vp.get_children():
		c.queue_free()
	var it := _big_item
	var got := _stage(_big_vp, it.vars[i][1])
	_big_pivot = got.pivot
	_big_cam = got.cam
	_r = got.r
	_big_label.text = "%s (%s) — %s" % [tr(it.key), tr(it.vars[i][0]), _about(it, got.box, got.verts).replace("\n", " · ")]


## The brood's stages one after another, each turning into the next (an egg; the larva growing; the cocoon spun round
## it and greying; the worker out of it) - the stages' own models and sizes; how the nest acts those moments out
## (nurses carrying, helping her out of the cocoon: nest_lifecycle.gd) is the nest's, not shown here.
func _start_cycle() -> void:
	for c in _big_vp.get_children():
		c.queue_free()
	var got := _stage(_big_vp, func():
		var n := Node3D.new()
		n.add_child(Catalog.egg())
		n.add_child(Catalog.larva(1.0))
		n.add_child(Catalog.cocoon(0.0))
		n.add_child(Catalog.ant(Catalog.AntModel.load_antmesh("res://assets/models/ants/worker_hi.antmesh")))
		return n)
	_big_pivot = got.pivot
	_big_cam = got.cam
	_r = got.r * 0.8
	var parts: Array = got.model.get_children()
	_cycle = {"egg": parts[0], "larva": parts[1], "cocoon": parts[2], "ant": parts[3], "t0": _t}
	_cycle_on = true


func _play_cycle() -> void:
	var c := _cycle
	var k := fmod(_t - float(c.t0), CYCLE) / CYCLE       # 0..1 round the cycle
	var eg := 1.0 - smoothstep(0.14, 0.2, k)
	var lv := smoothstep(0.14, 0.2, k) * (1.0 - smoothstep(0.55, 0.62, k))
	var co := smoothstep(0.55, 0.62, k) * (1.0 - smoothstep(0.82, 0.9, k))
	var an := smoothstep(0.82, 0.9, k)
	var p := clampf((k - 0.17) / 0.4, 0.0, 1.0)          # the larva's growth
	(c.egg as Node3D).scale = Vector3(0.32 / 0.2, 1, 1) * maxf(0.001, eg)
	(c.larva as Node3D).scale = Vector3.ONE * (0.28 + 0.8 * p) * maxf(0.001, lv)
	(c.cocoon as Node3D).scale = Vector3.ONE * maxf(0.001, co)
	((c.cocoon as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color.WHITE.lerp(Color(0.72, 0.72, 0.72), smoothstep(0.66, 0.82, k))
	(c.ant as Node3D).scale = Vector3.ONE * maxf(0.001, an)
	var stage := "mdl_egg" if k < 0.17 else ("mdl_larva_s" if k < 0.3 else ("mdl_larva_l" if k < 0.58 else ("mdl_cocoon" if k < 0.72
		else ("mdl_cocoon_late" if k < 0.86 else "mdl_worker"))))
	_big_label.text = "%s — %s (%d%%)" % [tr("mdl_cycle"), tr(stage), int(k * 100.0)]


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
