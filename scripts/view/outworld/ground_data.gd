extends RefCounted
## What the 3D outworld's ground is made from: the soil, damp and grain textures, the pheromone trail texture
## (kept current a few rows a frame), the scattered scenery (pebbles, litter, moss, grass tufts, the crater and the
## midden), the sky's light and the keeper's tool. (Until v0.11.5 this was the top-down 2D view, which drew it all too.)

const PHER_HOME := Color(0.5, 0.66, 1.0)
const PHER_FOOD := Color(0.98, 0.68, 0.27)
const PHER_ALARM := Color(1.0, 0.22, 0.18)
const GardenLayout := preload("res://scripts/view/outworld/garden_layout.gd")

var sim
var tool := "pan"          # "pan" = just look around; other tools place things
var show_pheromones := true

var soil_tex: Texture2D
var damp_tex: Texture2D
var grain_tex: Texture2D
var pher_tex: ImageTexture
var _pher_img: Image
var _pher_bytes := PackedByteArray()
var _pher_row := 0

var litter: Array = []
var pebbles: Array = []
var moss: Array = []
var tufts: Array = []
var boulders: Array = []           # the garden's big stones, outside the plot (garden_layout.gd; wild only)
var rosettes: Array = []           # low broad-leaved weeds (wild only)
var crater: Array = []
var midden_bits: Array = []


func setup(s) -> void:
	sim = s
	var size: Vector2 = sim.WORLD
	var ps: int = sim.plot_seed % 100000         # (0: the patches every colony had before v0.11.18)
	soil_tex = _noise(int(size.x), int(size.y), 0.006, 4, 11 + ps,
		[0.0, 0.3, 0.55, 0.8, 1.0],
		[Color("2f2117"), Color("47331f"), Color("5d4630"), Color("6f573d"), Color("85704f")])
	damp_tex = _noise(int(size.x / 2), int(size.y / 2), 0.008, 3, 23 + ps,
		[0.0, 0.45, 0.7, 1.0],
		[Color(0.1, 0.06, 0.04, 0.0), Color(0.1, 0.06, 0.04, 0.0), Color(0.12, 0.07, 0.04, 0.35), Color(0.08, 0.05, 0.03, 0.55)])
	grain_tex = _noise(int(size.x), int(size.y), 0.45, 1, 37 + ps,
		[0.0, 0.12, 0.3, 0.75, 0.9, 1.0],
		[Color(0.07, 0.04, 0.02, 0.55), Color(0.07, 0.04, 0.02, 0.0), Color(0, 0, 0, 0), Color(0, 0, 0, 0),
			Color(0.85, 0.75, 0.58, 0.0), Color(0.88, 0.78, 0.6, 0.4)], FastNoiseLite.TYPE_CELLULAR)
	_build_scenery()
	_pher_img = Image.create(sim.gw, sim.gh, false, Image.FORMAT_RGBA8)
	_pher_bytes.resize(sim.gw * sim.gh * 4)
	_pher_bytes.fill(0)
	pher_tex = ImageTexture.create_from_image(_pher_img)


func _noise(w: int, h: int, freq: float, octaves: int, seed_value: int, offsets: Array, colors: Array,
		kind := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> Texture2D:
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
	return t


## The scattered scenery: its own generator (not sim.rng, it is only looks), from the plot's seed - the same every time
## the colony is opened (colonies from before v0.11.18 all had the one, 4242).
func _build_scenery() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4242 if sim.plot_seed == 0 else sim.plot_seed
	var size: Vector2 = sim.WORLD
	if sim.scenario == "wild":
		GardenLayout.build(self, sim, r)          # grouped as a patch of garden looks (v0.11.37)
	else:
		_scatter(r, size)
	_crater_and_midden(r)


## The keeper's box: the scenery scattered evenly (as everywhere until v0.11.37).
func _scatter(r: RandomNumberGenerator, size: Vector2) -> void:
	for i in 900:
		var p := Vector2(r.randf() * size.x, r.randf() * size.y)
		var tone := r.randf()
		var col := Color(0.45, 0.4, 0.34).lerp(Color(0.72, 0.64, 0.52), tone)
		if r.randf() < 0.25:
			col = Color(0.3, 0.22, 0.15).lerp(Color(0.5, 0.36, 0.24), tone)
		pebbles.append({"p": p, "r": Vector2(r.randf_range(0.8, 2.6), r.randf_range(0.7, 2.0)), "a": r.randf() * TAU, "c": col})
	for i in 34:
		var p := Vector2(r.randf() * size.x, r.randf() * size.y)
		if p.distance_to(sim.nest_pos) < 60:
			continue
		var base: Color = [Color("7a4a24"), Color("8f5a2a"), Color("6b4a2c"), Color("a06b34"), Color("5a3d24")][r.randi() % 5]
		litter.append({"p": p, "a": r.randf() * TAU, "l": r.randf_range(22, 46), "w": r.randf_range(7, 14),
			"c": base.lerp(Color("3d2a1b"), r.randf() * 0.3), "twig": r.randf() < 0.3, "curl": r.randf_range(-0.2, 0.2)})
	for i in 10:
		var c := Vector2(r.randf() * size.x, r.randf() * size.y)
		var blobs := []
		for k in 40:
			blobs.append([c + Vector2(r.randfn(0, 9), r.randfn(0, 6)), r.randf_range(1.5, 3.5), r.randf()])
		moss.append(blobs)
	for i in 70:
		var edge := r.randi() % 4
		var t := r.randf()
		var p: Vector2 = [Vector2(t * size.x, r.randf() * 16), Vector2(size.x - r.randf() * 16, t * size.y),
			Vector2(t * size.x, size.y - r.randf() * 16), Vector2(r.randf() * 16, t * size.y)][edge]
		var blades := []
		for k in r.randi_range(5, 9):
			blades.append([r.randf() * TAU, r.randf_range(8, 22), r.randf()])
		tufts.append({"p": p, "b": blades})


func _crater_and_midden(r: RandomNumberGenerator) -> void:
	# a lone founding queen has dug only a little; an established nest has a proper crater
	for i in (90 if sim.workers.is_empty() else 420):
		var a := r.randf() * TAU
		var d := 9.0 + absf(r.randfn(0, 1)) * 13.0
		crater.append({"p": sim.nest_pos + Vector2.from_angle(a) * d, "r": r.randf_range(0.6, 1.8),
			"c": Color(0.6, 0.48, 0.34).lerp(Color(0.82, 0.7, 0.52), r.randf())})
	for i in 60:
		midden_bits.append({"p": sim.midden_pos + Vector2(r.randfn(0, 7), r.randfn(0, 5)), "r": r.randf_range(0.6, 2.0),
			"c": Color(0.18, 0.12, 0.08).lerp(Color(0.38, 0.27, 0.16), r.randf())})


## Keeps the trail texture current (a sixth of its rows a frame) while the outworld is on screen.
func tick_pheromones() -> void:
	if not show_pheromones:
		return
	var w: int = sim.gw
	var h: int = sim.gh
	var home = sim.home
	var food = sim.food
	for k in h / 6 + 1:
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
	pher_tex.update(_pher_img)


## The light outdoors: day, dusk and night, dimmer in rain, cold blue in the fridge.
func sky_color() -> Color:
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
	c = c.lerp(Color(0.32, 0.4, 0.55), sim.climate.fridge * 0.75)
	return c
