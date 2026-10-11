extends Node2D
## Top-down view of the outworld box: soil, litter, rocks, pheromone trails, food, ants,
## weather and the day/night light.

const Ant := preload("res://scripts/sim/ant.gd")
const Kit := preload("res://scripts/view/surface2d/draw_kit.gd")
const AntBatch := preload("res://scripts/view/surface2d/ant_batch.gd")
const FoodKinds := preload("res://scripts/sim/food_kinds.gd")

const PHER_HOME := Color(0.5, 0.66, 1.0)
const PHER_FOOD := Color(0.98, 0.68, 0.27)
const PHER_ALARM := Color(1.0, 0.22, 0.18)

var sim
var tool := "pan"          # "pan" = just look around; other tools place things
var show_pheromones := true:
	set(v):
		show_pheromones = v
		if _pher:
			_pher.visible = v
var hover := Vector2(-999, -999)
var time := 0.0
var _items_timer := 0.0
var _items_sig := -1
var _spider_drawn := false

var _soil: Sprite2D
var _damp: Sprite2D
var _grain: Sprite2D
var _decor: Node2D
var _pher: Sprite2D
var _items: Node2D
var _ants: Node2D
var _batch
var _fx: Node2D
var _light: CanvasModulate
var _pher_img: Image
var _pher_tex: ImageTexture
var _pher_bytes := PackedByteArray()
var _pher_row := 0
var _painting := false
var _last_paint := Vector2(-999, -999)

var _litter: Array = []
var _pebbles: Array = []
var _moss: Array = []
var _tufts: Array = []
var _crater: Array = []
var _midden_bits: Array = []
var _rain: Array = []


func setup(s) -> void:
	sim = s
	var size: Vector2 = sim.WORLD
	_soil = _noise_sprite(int(size.x), int(size.y), 0.006, 4, 11,
		[0.0, 0.3, 0.55, 0.8, 1.0],
		[Color("2f2117"), Color("47331f"), Color("5d4630"), Color("6f573d"), Color("85704f")])
	_damp = _noise_sprite(int(size.x / 2), int(size.y / 2), 0.008, 3, 23,
		[0.0, 0.45, 0.7, 1.0],
		[Color(0.1, 0.06, 0.04, 0.0), Color(0.1, 0.06, 0.04, 0.0), Color(0.12, 0.07, 0.04, 0.35), Color(0.08, 0.05, 0.03, 0.55)])
	_damp.scale = Vector2(2, 2)
	_grain = _noise_sprite(int(size.x), int(size.y), 0.45, 1, 37,
		[0.0, 0.12, 0.3, 0.75, 0.9, 1.0],
		[Color(0.07, 0.04, 0.02, 0.55), Color(0.07, 0.04, 0.02, 0.0), Color(0, 0, 0, 0), Color(0, 0, 0, 0),
			Color(0.85, 0.75, 0.58, 0.0), Color(0.88, 0.78, 0.6, 0.4)], FastNoiseLite.TYPE_CELLULAR)

	_build_decor()
	_decor = _layer(_draw_decor)

	_pher_img = Image.create(sim.gw, sim.gh, false, Image.FORMAT_RGBA8)
	_pher_bytes.resize(sim.gw * sim.gh * 4)
	_pher_bytes.fill(0)
	_pher_tex = ImageTexture.create_from_image(_pher_img)
	_pher = Sprite2D.new()
	_pher.centered = false
	_pher.texture = _pher_tex
	_pher.scale = Vector2(sim.CELL, sim.CELL)
	_pher.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain/pheromone.gdshader")
	_pher.material = mat
	add_child(_pher)

	_items = _layer(_draw_items)
	_batch = AntBatch.new()
	add_child(_batch)
	_ants = _layer(_draw_ants)
	_fx = _layer(_draw_fx)
	_layer(_draw_frame)
	_light = CanvasModulate.new()
	add_child(_light)
	for i in 180:
		_rain.append(Vector3(randf() * size.x, randf() * size.y, randf_range(0.7, 1.3)))


func _noise_sprite(w: int, h: int, freq: float, octaves: int, seed_value: int, offsets: Array, colors: Array,
		kind := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> Sprite2D:
	var n := FastNoiseLite.new()
	n.noise_type = kind
	n.seed = seed_value
	n.frequency = freq
	n.fractal_octaves = octaves
	if kind == FastNoiseLite.TYPE_CELLULAR:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := NoiseTexture2D.new()
	t.width = w
	t.height = h
	t.noise = n
	t.color_ramp = g
	var spr := Sprite2D.new()
	spr.centered = false
	spr.texture = t
	add_child(spr)
	return spr


func _layer(fn: Callable) -> Node2D:
	var n := Node2D.new()
	n.draw.connect(fn.bind(n))
	add_child(n)
	return n


# ---------------------------------------------------------------- static scenery

func _build_decor() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var size: Vector2 = sim.WORLD
	for i in 900:
		var p := Vector2(r.randf() * size.x, r.randf() * size.y)
		var tone := r.randf()
		var col := Color(0.45, 0.4, 0.34).lerp(Color(0.72, 0.64, 0.52), tone)
		if r.randf() < 0.25:
			col = Color(0.3, 0.22, 0.15).lerp(Color(0.5, 0.36, 0.24), tone)
		_pebbles.append({"p": p, "r": Vector2(r.randf_range(0.8, 2.6), r.randf_range(0.7, 2.0)), "a": r.randf() * TAU, "c": col})
	for i in 34:
		var p := Vector2(r.randf() * size.x, r.randf() * size.y)
		if p.distance_to(sim.nest_pos) < 60:
			continue
		var base: Color = [Color("7a4a24"), Color("8f5a2a"), Color("6b4a2c"), Color("a06b34"), Color("5a3d24")][r.randi() % 5]
		_litter.append({"p": p, "a": r.randf() * TAU, "l": r.randf_range(22, 46), "w": r.randf_range(7, 14),
			"c": base.lerp(Color("3d2a1b"), r.randf() * 0.3), "twig": r.randf() < 0.3, "curl": r.randf_range(-0.2, 0.2)})
	for i in 10:
		var c := Vector2(r.randf() * size.x, r.randf() * size.y)
		var blobs := []
		for k in 40:
			blobs.append([c + Vector2(r.randfn(0, 9), r.randfn(0, 6)), r.randf_range(1.5, 3.5), r.randf()])
		_moss.append(blobs)
	for i in 70:
		var edge := r.randi() % 4
		var t := r.randf()
		var p: Vector2 = [Vector2(t * size.x, r.randf() * 16), Vector2(size.x - r.randf() * 16, t * size.y),
			Vector2(t * size.x, size.y - r.randf() * 16), Vector2(r.randf() * 16, t * size.y)][edge]
		var blades := []
		for k in r.randi_range(5, 9):
			blades.append([r.randf() * TAU, r.randf_range(8, 22), r.randf()])
		_tufts.append({"p": p, "b": blades})
	# a lone founding queen has dug only a little; an established nest has a proper crater
	for i in (90 if sim.workers.is_empty() else 420):
		var a := r.randf() * TAU
		var d := 9.0 + absf(r.randfn(0, 1)) * 13.0
		_crater.append({"p": sim.nest_pos + Vector2.from_angle(a) * d, "r": r.randf_range(0.6, 1.8),
			"c": Color(0.6, 0.48, 0.34).lerp(Color(0.82, 0.7, 0.52), r.randf())})
	for i in 60:
		_midden_bits.append({"p": sim.midden_pos + Vector2(r.randfn(0, 7), r.randfn(0, 5)), "r": r.randf_range(0.6, 2.0),
			"c": Color(0.18, 0.12, 0.08).lerp(Color(0.38, 0.27, 0.16), r.randf())})


func _draw_decor(ci: Node2D) -> void:
	for m in _moss:
		for b in m:
			ci.draw_circle(b[0], b[1], Color(0.25, 0.36, 0.14).lerp(Color(0.38, 0.5, 0.2), b[2]))
	for p in _pebbles:
		Kit.ellipse(ci, p.p + Vector2(0.4, 0.6), p.r, Color(0, 0, 0, 0.25), p.a)
		Kit.ellipse(ci, p.p, p.r, p.c, p.a)
		Kit.ellipse(ci, p.p - p.r * 0.25, p.r * 0.45, p.c.lightened(0.2), p.a)
	for l in _litter:
		if l.twig:
			var d: Vector2 = Vector2.from_angle(l.a) * l.l
			ci.draw_line(l.p - d + Vector2(1.5, 2), l.p + d + Vector2(1.5, 2), Color(0, 0, 0, 0.25), 3.2, true)
			ci.draw_line(l.p - d, l.p + d, Color("4a3220"), 2.6, true)
			ci.draw_line(l.p - d * 0.9, l.p + d * 0.9, Color("6d4b30"), 1.0, true)
			ci.draw_line(l.p + d * 0.2, l.p + d * 0.2 + Vector2.from_angle(l.a + 0.7) * 9.0, Color("4a3220"), 1.3, true)
			continue
		ci.draw_set_transform_matrix(Transform2D(l.a, Vector2.ONE, l.curl, l.p + Vector2(2, 3)))
		ci.draw_colored_polygon(Kit.leaf_shape(l.l, l.w), Color(0, 0, 0, 0.22))
		ci.draw_set_transform_matrix(Transform2D(l.a, Vector2.ONE, l.curl, l.p))
		ci.draw_colored_polygon(Kit.leaf_shape(l.l, l.w), l.c)
		ci.draw_line(Vector2(-l.l * 0.55, 0), Vector2(l.l * 0.45, 0), l.c.darkened(0.3), 0.9, true)
		for v in 4:
			var vx: float = -l.l * 0.32 + v * l.l * 0.18
			ci.draw_line(Vector2(vx, 0), Vector2(vx + l.w * 0.6, -l.w * 0.6), l.c.darkened(0.22), 0.5, true)
			ci.draw_line(Vector2(vx, 0), Vector2(vx + l.w * 0.6, l.w * 0.6), l.c.darkened(0.22), 0.5, true)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	for rk in sim.rocks:
		_draw_rock(ci, rk)
	for t in _tufts:
		for b in t.b:
			var tip: Vector2 = t.p + Vector2.from_angle(b[0]) * b[1]
			ci.draw_line(t.p + Vector2(2, 3), tip + Vector2(3, 4), Color(0, 0, 0, 0.18), 1.6, true)
			ci.draw_line(t.p, tip, Color(0.33, 0.5, 0.2).lerp(Color(0.55, 0.68, 0.3), b[2]), 1.4, true)


func _draw_rock(ci: Node2D, rk: Dictionary) -> void:
	var c: Vector2 = rk.pos
	var poly: PackedVector2Array = rk.poly
	var tone: float = rk.tone
	var base := Color(0.42, 0.39, 0.36).lerp(Color(0.55, 0.49, 0.42), tone)
	var shadow := PackedVector2Array()
	for p in poly:
		shadow.append(p + Vector2(3.5, 5.0))
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.32))
	ci.draw_colored_polygon(poly, base.darkened(0.25))
	for layer in [[0.82, Vector2(-0.08, -0.1), 0.0], [0.6, Vector2(-0.16, -0.2), 0.12], [0.32, Vector2(-0.26, -0.32), 0.26]]:
		var pts := PackedVector2Array()
		for p in poly:
			pts.append(c + (p - c) * layer[0] + layer[1] * rk.r)
		ci.draw_colored_polygon(pts, base.lightened(layer[2]))
	ci.draw_polyline(poly + PackedVector2Array([poly[0]]), base.darkened(0.45), 0.8, true)


# ---------------------------------------------------------------- live layers

func _draw_items(ci: Node2D) -> void:
	for g in _crater:
		ci.draw_circle(g.p, g.r, g.c)
	var n: Vector2 = sim.nest_pos
	for i in 6:
		Kit.ellipse(ci, n, Vector2(9.0 - i * 1.1, 7.0 - i * 0.9), Color(0.05, 0.03, 0.02, 0.35 + i * 0.1), 0.3)
	for b in _midden_bits:
		ci.draw_circle(b.p, b.r, b.c)
	for c in sim.corpses:
		Kit.dead_ant(ci, c.pos, c.ang, clampf(1.0 - c.age / 30.0, 0.2, 1.0))
	for f in sim.foods:
		var left: float = f.amt / f.cap
		match f.kind:
			"aphids": Kit.aphid_plant(ci, f.pos, f.seed, left, 0.0)
			"honey": Kit.honey(ci, f.pos, left)
			"cricket": Kit.cricket(ci, f.pos, f.ang, left, f.rotten)
			"fly": Kit.fly(ci, f.pos, f.ang, left)
			"wolf_spider_dead": Kit.wolf_spider(ci, f.pos, f.ang, 0.0)
			"centipede_dead": Kit.centipede(ci, f.pos, f.ang, 0.0, true)
			"ground_beetle_dead": Kit.ground_beetle(ci, f.pos, f.ang, 0.0, true)
			_: Kit.ellipse(ci, f.pos, Vector2(f.r, f.r) * 0.6, Color(0.6, 0.45, 0.3))   # a kind with no drawing yet


func _draw_ants(ci: Node2D) -> void:
	# foragers are batched in AntBatch; only the predator is drawn here
	for c in sim.creatures:
		match c.kind:
			"wolf_spider": Kit.wolf_spider(ci, c.pos, c.ang, c.phase)
			"centipede": Kit.centipede(ci, c.pos, c.ang, c.phase)
			"ground_beetle": Kit.ground_beetle(ci, c.pos, c.ang, c.phase)


func _draw_fx(ci: Node2D) -> void:
	if sim.climate.raining():
		for d in _rain:
			var p := Vector2(d.x, d.y)
			ci.draw_line(p, p + Vector2(-3, 12) * d.z, Color(0.8, 0.86, 0.95, 0.35), 1.0, true)
			if fmod(d.y, 97.0) < 3.0:
				ci.draw_arc(p + Vector2(0, 14), 3.0 * d.z, 0, TAU, 12, Color(0.85, 0.9, 1.0, 0.25), 0.8, true)
	if tool in ["rock", "erase"] and hover.x > -100:
		ci.draw_arc(hover, 10.0 if tool == "rock" else 24.0, 0, TAU, 32, Color(1, 0.95, 0.85, 0.6), 1.0, true)


func _draw_frame(ci: Node2D) -> void:
	# glass-walled outworld box: dark surround, inner shadow along the walls, a lit rim
	var s: Vector2 = sim.WORLD
	var out := 2000.0
	var wall := Color(0.07, 0.055, 0.045)
	ci.draw_rect(Rect2(-out, -out, s.x + out * 2, out), wall)
	ci.draw_rect(Rect2(-out, s.y, s.x + out * 2, out), wall)
	ci.draw_rect(Rect2(-out, 0, out, s.y), wall)
	ci.draw_rect(Rect2(s.x, 0, out, s.y), wall)
	for i in 10:
		var w := 2.0 + i * 2.5
		var a := 0.045
		ci.draw_rect(Rect2(0, 0, s.x, w), Color(0, 0, 0, a))
		ci.draw_rect(Rect2(0, s.y - w, s.x, w), Color(0, 0, 0, a))
		ci.draw_rect(Rect2(0, 0, w, s.y), Color(0, 0, 0, a))
		ci.draw_rect(Rect2(s.x - w, 0, w, s.y), Color(0, 0, 0, a))
	ci.draw_rect(Rect2(-3, -3, s.x + 6, s.y + 6), Color(0.85, 0.8, 0.72, 0.35), false, 2.0)
	ci.draw_rect(Rect2(-8, -8, s.x + 16, s.y + 16), Color(0.2, 0.16, 0.13), false, 6.0)


func refresh(delta: float, sim_speed: float) -> void:
	time += delta
	if sim.climate.raining() and sim_speed > 0:
		var size: Vector2 = sim.WORLD
		for i in _rain.size():
			var d: Vector3 = _rain[i]
			d.y += 520.0 * delta * d.z
			d.x -= 130.0 * delta * d.z
			if d.y > size.y:
				d.y -= size.y
				d.x = randf() * size.x
			if d.x < 0:
				d.x += size.x
			_rain[i] = d
	# food, corpses and the mound change slowly: redraw them a few times a second, not every frame
	_items_timer -= delta
	var sig: int = sim.foods.size() * 1000 + sim.corpses.size()
	if _items_timer <= 0.0 or sig != _items_sig:
		_items_timer = 0.4
		_items_sig = sig
		_items.queue_redraw()
	_batch.update(sim.outside, sim.sp["body_color"], sim.sp["callow_color"], 1.15, delta, sim_speed > 0)
	if not sim.creatures.is_empty() or _spider_drawn:
		_spider_drawn = not sim.creatures.is_empty()
		_ants.queue_redraw()
	_fx.queue_redraw()
	if show_pheromones:
		_update_pheromones(sim.gh / 6 + 1)
	_light.color = _sky_color()


## Keeps the trail texture current while the 3D outworld (which shares it) is on screen.
func tick_pheromones() -> void:
	if show_pheromones:
		_update_pheromones(sim.gh / 6 + 1)


func redraw_scenery() -> void:
	_decor.queue_redraw()


func _update_pheromones(rows: int) -> void:
	var w: int = sim.gw
	var h: int = sim.gh
	var home = sim.home
	var food = sim.food
	for k in rows:
		var y := _pher_row
		_pher_row = (_pher_row + 1) % h
		for x in w:
			var i := y * w + x
			var ah := minf(1.0, home.read_i(i) / 3.0) * 0.28
			var af := minf(1.0, food.read_i(i) / 1.8) * 0.85
			var al := minf(1.0, sim.alarm.read_i(i) / 1.5) * 0.9
			var s := ah + af + al
			var o := i * 4
			if s < 0.02:
				_pher_bytes[o + 3] = 0
				continue
			_pher_bytes[o] = int((PHER_HOME.r * ah + PHER_FOOD.r * af + PHER_ALARM.r * al) / s * 255.0)
			_pher_bytes[o + 1] = int((PHER_HOME.g * ah + PHER_FOOD.g * af + PHER_ALARM.g * al) / s * 255.0)
			_pher_bytes[o + 2] = int((PHER_HOME.b * ah + PHER_FOOD.b * af + PHER_ALARM.b * al) / s * 255.0)
			_pher_bytes[o + 3] = int(minf(1.0, s) * 190.0)
	_pher_img.set_data(w, h, false, Image.FORMAT_RGBA8, _pher_bytes)
	_pher_tex.update(_pher_img)


func _sky_color() -> Color:
	var sun: float = sim.sun_height()       # outdoors the sun rises earlier and sets later in summer
	var night := Color(0.4, 0.42, 0.56)
	var dusk := Color(1.0, 0.76, 0.6)
	var day := Color(1.0, 0.98, 0.95)
	var c: Color
	if sun > 0.25:
		c = dusk.lerp(day, clampf((sun - 0.25) / 0.45, 0.0, 1.0))
	elif sun > -0.15:
		c = night.lerp(dusk, (sun + 0.15) / 0.4)
	else:
		c = night
	if sim.climate.raining():
		c *= Color(0.78, 0.82, 0.9)
	# inside the fridge: dark, with a cold blue glow
	c = c.lerp(Color(0.32, 0.4, 0.55), sim.climate.fridge * 0.75)
	return c


# ---------------------------------------------------------------- input

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			var p := get_global_mouse_position()
			match tool:
				"pan":
					pass
				_ when FoodKinds.info(tool).has("tool"):
					sim.place_food(tool, p)
				_:
					_painting = true
					_paint(p)
		else:
			_painting = false
	elif e is InputEventMouseMotion:
		hover = get_global_mouse_position()
		if _painting:
			_paint(hover)


func _paint(p: Vector2) -> void:
	if tool == "rock":
		if p.distance_to(_last_paint) > 9.0 and sim.can_place(p) and sim.add_rock(p, 10.0):
			_last_paint = p
			redraw_scenery()
	elif tool == "erase":
		sim.erase_pheromones(p, 24.0)
